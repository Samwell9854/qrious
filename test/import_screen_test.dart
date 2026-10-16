import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/wifi_format.dart';
import 'package:qrious/image_clipboard.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/qr_decoding.dart';
import 'package:qrious/screens/home_screen.dart';

final wifiPayload = WifiFormat().buildQrString({
  'ssid': 'Cafe',
  'security': 'WPA/WPA2',
  'password': 'hunter2',
  'hidden': 'false',
});

const vcardWithNote =
    'BEGIN:VCARD\nVERSION:3.0\nN:Doe;Jo;;;\nFN:Jo Doe\nNOTE:hi\nEND:VCARD';

final bytes = Uint8List.fromList([1, 2, 3]);

/// Pumps the screen with every way of getting an image stubbed. [payloads] is
/// what "decoding" the image finds.
Future<void> pumpHome(
  WidgetTester tester, {
  List<String> payloads = const [],
  Future<Uint8List?> Function()? pick,
  Future<Uint8List?> Function()? clipboard,
  Future<bool> Function()? onlyImage,
  Future<bool> Function()? imageFile,
  Future<Uint8List> Function(Uint8List)? rasterize,
  Future<List<String>> Function(Uint8List)? decode,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        pickImageFile: pick ?? () async => bytes,
        readClipboardImage: clipboard ?? () async => bytes,
        clipboardOffersOnlyImage: onlyImage ?? () async => false,
        clipboardOffersImageFile: imageFile ?? () async => false,
        decodeImage: decode ?? (_) async => payloads,
        rasterizeSvgImage: rasterize,
      ),
    ),
  );
}

Future<void> openMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Read a QR code'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> openImage(WidgetTester tester) =>
    openMenuItem(tester, 'Open image…');

String payload(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byType(SelectableText)).data!;

String selectedFormat(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<QrFormat>>(
      find.byType(DropdownButtonFormField<QrFormat>),
    )
    .initialValue!
    .name;

Finder get notice => find.text('Recognised as Contact (vCard)');

void main() {
  testWidgets('an SVG file is drawn to pixels before it is decoded', (
    tester,
  ) async {
    final svg = Uint8List.fromList(
      '<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits,
    );
    final pixels = Uint8List.fromList([9, 9, 9]);
    Uint8List? drawn;
    Uint8List? decoded;
    await pumpHome(
      tester,
      pick: () async => svg,
      rasterize: (input) async {
        drawn = input;
        return pixels;
      },
      decode: (input) async {
        decoded = input;
        return [wifiPayload];
      },
    );
    await openImage(tester);

    expect(drawn, svg);
    expect(decoded, pixels);
    expect(find.text('Code read into Wi-Fi'), findsOneWidget);
  });

  testWidgets('a raster file skips the SVG drawing', (tester) async {
    var drew = false;
    await pumpHome(
      tester,
      payloads: [wifiPayload],
      rasterize: (input) async {
        drew = true;
        return input;
      },
    );
    await openImage(tester);

    expect(drew, isFalse);
  });

  testWidgets('an exact Wi-Fi code fills the Wi-Fi form', (tester) async {
    await pumpHome(tester, payloads: [wifiPayload]);
    await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plain Text').last);
    await tester.pumpAndSettle();

    await openImage(tester);

    expect(find.text('Code read into Wi-Fi'), findsOneWidget);
    expect(selectedFormat(tester), 'Wi-Fi');
    expect(payload(tester), wifiPayload);
    expect(find.textContaining('Opened as text'), findsNothing);
  });

  testWidgets('a code the form would change opens as text with a notice', (
    tester,
  ) async {
    await pumpHome(tester, payloads: [vcardWithNote]);
    await openImage(tester);

    expect(find.text('Code read into Plain Text'), findsOneWidget);
    expect(selectedFormat(tester), 'Plain Text');
    expect(payload(tester), vcardWithNote);
    expect(notice, findsOneWidget);
    expect(find.textContaining('hold NOTE'), findsOneWidget);

    await tester.tap(find.text('Open in Contact (vCard) form'));
    await tester.pumpAndSettle();

    expect(selectedFormat(tester), 'Contact (vCard)');
    expect(find.text('Code read into Contact (vCard)'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'First Name'), findsOneWidget);
    expect(find.text('Jo'), findsOneWidget);
    expect(notice, findsNothing);
  });

  testWidgets('a reordered Wi-Fi code says the layout differs', (tester) async {
    await pumpHome(tester, payloads: ['WIFI:S:x;T:WPA;P:y;;']);
    await openImage(tester);

    expect(selectedFormat(tester), 'Plain Text');
    expect(find.text('Recognised as Wi-Fi'), findsOneWidget);
    expect(find.textContaining('write it the same way'), findsOneWidget);
  });

  testWidgets('the notice goes away on dismiss, edit, switch and clear', (
    tester,
  ) async {
    Future<void> read() async {
      await openImage(tester);
      expect(notice, findsOneWidget);
    }

    await pumpHome(tester, payloads: [vcardWithNote]);
    await read();
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(notice, findsNothing);

    await read();
    await tester.enterText(find.byType(TextFormField), '$vcardWithNote!');
    await tester.pump();
    expect(notice, findsNothing);

    await read();
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pump();
    expect(notice, findsNothing);

    await read();
    await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wi-Fi').last);
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
  });

  testWidgets('several codes are listed, and the chosen one is read', (
    tester,
  ) async {
    await pumpHome(tester, payloads: ['https://example.com', wifiPayload]);
    await openImage(tester);

    expect(find.text('Several codes found'), findsOneWidget);
    expect(find.text('https://example.com'), findsOneWidget);
    expect(find.text(wifiPayload), findsOneWidget);

    await tester.tap(find.text(wifiPayload));
    await tester.pumpAndSettle();

    expect(find.text('Several codes found'), findsNothing);
    expect(selectedFormat(tester), 'Wi-Fi');
    expect(payload(tester), wifiPayload);
  });

  testWidgets('Cancel in the list of codes reads nothing', (tester) async {
    await pumpHome(tester, payloads: ['a', 'b']);
    await openImage(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Code read into Plain Text'), findsNothing);
    expect(selectedFormat(tester), 'Wi-Fi');
  });

  testWidgets('an image without a code says so', (tester) async {
    await pumpHome(tester);
    await openImage(tester);
    expect(find.text('No QR code found in this image.'), findsOneWidget);
  });

  testWidgets('a file that is no image says so', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          pickImageFile: () async => bytes,
          decodeImage: (_) async => throw const UnreadableImageException(),
        ),
      ),
    );
    await openImage(tester);
    expect(
      find.text("That file isn't an image Qrious can open."),
      findsOneWidget,
    );
    // And the entry point works again.
    expect(
      tester.widget<IconButton>(find.byType(IconButton).first).onPressed,
      isNotNull,
    );
  });

  testWidgets('cancelling the picker does nothing', (tester) async {
    await pumpHome(tester, payloads: [wifiPayload], pick: () async => null);
    await openImage(tester);
    expect(find.byType(SnackBar), findsNothing);
  });

  group('undo', () {
    Future<void> readOverTypedWifi(WidgetTester tester) async {
      await pumpHome(tester, payloads: ['https://example.com']);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Network Name (SSID)'),
        'MyNetwork',
      );
      await tester.pump();
      await openImage(tester);
      expect(selectedFormat(tester), 'URL / Website');
    }

    testWidgets('the snackbar brings back the previous format', (tester) async {
      await readOverTypedWifi(tester);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(selectedFormat(tester), 'Wi-Fi');
      expect(payload(tester), contains('S:MyNetwork'));
    });

    testWidgets('Ctrl+Z does the same', (tester) async {
      await readOverTypedWifi(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(selectedFormat(tester), 'Wi-Fi');
      expect(payload(tester), contains('S:MyNetwork'));
    });

    testWidgets('does nothing once something is typed', (tester) async {
      await readOverTypedWifi(tester);
      await tester.enterText(find.byType(TextFormField).first, 'https://x.io');
      await tester.pump();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(selectedFormat(tester), 'URL / Website');
      expect(payload(tester), 'https://x.io');
    });

    testWidgets('restores the session memory of the format it read into', (
      tester,
    ) async {
      await pumpHome(tester, payloads: ['https://example.com']);
      // The URL form remembers a value, then the user leaves it.
      Future<void> pick(String name) async {
        await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
      }

      await pick('URL / Website');
      await tester.enterText(find.byType(TextFormField), 'https://kept.io');
      await tester.pump();
      await pick('Wi-Fi');

      await openImage(tester);
      expect(payload(tester), 'https://example.com');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      await pick('URL / Website');

      expect(payload(tester), 'https://kept.io');
    });

    testWidgets('Clear still undoes', (tester) async {
      await pumpHome(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Network Name (SSID)'),
        'MyNetwork',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Form cleared'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(payload(tester), contains('S:MyNetwork'));
    });
  });

  group('the clipboard', () {
    testWidgets('Paste image reads the clipboard', (tester) async {
      var reads = 0;
      await pumpHome(
        tester,
        payloads: [wifiPayload],
        clipboard: () async {
          reads++;
          return bytes;
        },
      );
      await openMenuItem(tester, 'Paste image');
      expect(reads, 1);
      expect(find.text('Code read into Wi-Fi'), findsOneWidget);
    });

    testWidgets('an empty clipboard says so', (tester) async {
      await pumpHome(tester, clipboard: () async => null);
      await openMenuItem(tester, 'Paste image');
      expect(find.text('The clipboard holds no image.'), findsOneWidget);
    });

    testWidgets('a clipboard failure shows its message', (tester) async {
      await pumpHome(
        tester,
        clipboard: () async =>
            throw const ImageClipboardException('Install it.'),
      );
      await openMenuItem(tester, 'Paste image');
      expect(find.text('Install it.'), findsOneWidget);
    });

    Future<void> ctrlV(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('Ctrl+V reads an image when the clipboard holds only one', (
      tester,
    ) async {
      await pumpHome(
        tester,
        payloads: [wifiPayload],
        onlyImage: () async => true,
      );
      await ctrlV(tester);
      expect(find.text('Code read into Wi-Fi'), findsOneWidget);
    });

    testWidgets('Ctrl+V reads a copied image file when no field has focus', (
      tester,
    ) async {
      await pumpHome(
        tester,
        payloads: [wifiPayload],
        imageFile: () async => true,
      );
      await ctrlV(tester);
      expect(find.text('Code read into Wi-Fi'), findsOneWidget);
    });

    testWidgets('Ctrl+V leaves a copied image file to a focused field', (
      tester,
    ) async {
      await pumpHome(
        tester,
        payloads: [wifiPayload],
        imageFile: () async => true,
      );
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await ctrlV(tester);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Ctrl+V leaves a clipboard with text alone', (tester) async {
      await pumpHome(
        tester,
        payloads: [wifiPayload],
        onlyImage: () async => false,
      );
      await ctrlV(tester);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  testWidgets('Ctrl+O opens the picker', (tester) async {
    var picks = 0;
    await pumpHome(
      tester,
      payloads: [wifiPayload],
      pick: () async {
        picks++;
        return bytes;
      },
    );
    await tester.tap(find.widgetWithText(TextFormField, 'Network Name (SSID)'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(picks, 1);
  });

  group('dropping a file', () {
    const channel = MethodChannel('qrious/drop');
    const overlay = 'Drop an image to read its QR code';

    Future<void> send(
      WidgetTester tester,
      String method, [
      Object? args,
    ]) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
      await tester.pump();
    }

    Future<Uint8List?> pumpAndDrop(
      WidgetTester tester, {
      required bool leaveFirst,
    }) async {
      final dir = Directory.systemTemp.createTempSync('qrious-drop');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/code.png')..writeAsBytesSync([9, 9]);
      Uint8List? got;

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            decodeImage: (b) async {
              got = b;
              return [wifiPayload];
            },
          ),
        ),
      );

      await send(tester, 'enter');
      expect(find.text(overlay), findsOneWidget);
      // GTK emits leave right before the drop.
      if (leaveFirst) {
        await send(tester, 'leave');
        expect(find.text(overlay), findsNothing);
      }
      await tester.runAsync(() async {
        await send(tester, 'drop', [file.path]);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      return got;
    }

    testWidgets('shows the overlay while dragging, hides it on leave', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await send(tester, 'enter');
      expect(find.text(overlay), findsOneWidget);
      await send(tester, 'leave');
      expect(find.text(overlay), findsNothing);
    });

    testWidgets('reads the dropped file', (tester) async {
      final got = await pumpAndDrop(tester, leaveFirst: false);

      expect(got, [9, 9]);
      expect(find.text('Code read into Wi-Fi'), findsOneWidget);
      expect(find.text(overlay), findsNothing);
    });

    testWidgets('reads the file when leave comes right before the drop', (
      tester,
    ) async {
      final got = await pumpAndDrop(tester, leaveFirst: true);

      expect(got, [9, 9]);
      expect(find.text('Code read into Wi-Fi'), findsOneWidget);
    });
  });

  group('the notice fits', () {
    final many = [for (var i = 0; i < 25; i++) 'X-LONG-PROPERTY-NAME-$i:v'];
    final longCard =
        'BEGIN:VCARD\nVERSION:3.0\nN:Doe;Jo;;;\nFN:Jo Doe\n'
        '${many.join('\n')}\nNOTE:hi\nEND:VCARD';

    for (final size in [const Size(390, 844), const Size(1280, 800)]) {
      testWidgets('at ${size.width}x${size.height}', (tester) async {
        await pumpHome(tester, payloads: [longCard], size: size);
        await openImage(tester);

        expect(notice, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
