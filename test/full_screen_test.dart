import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrious/full_screen.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/pixel_size.dart';
import 'package:qrious/screens/home_screen.dart';
import 'package:qrious/widgets/full_screen_qr.dart';

/// Long enough for a near-largest symbol, whose modules come out under 0.5mm on
/// a typical monitor at either layout's size.
final densePayload = 'A long note. ' * 150;

/// A 24" 1080p monitor.
const desktopPixel = 0.28;

/// A phone's logical pixel, 160 to the inch.
const phonePixel = 25.4 / 160;

Future<List<bool>> pumpHome(
  WidgetTester tester,
  Size size, {
  double? mmPerPixel = desktopPixel,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final calls = <bool>[];
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        setFullScreen: (on) async => calls.add(on),
        readPixelSize: () async => mmPerPixel,
      ),
    ),
  );
  await tester.pump();
  return calls;
}

Future<void> fillSsid(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Network Name (SSID)'),
    'MyNetwork',
  );
  await tester.pump();
}

Future<void> fillDenseText(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Plain Text').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField), densePayload);
  await tester.pump();
}

Finder get preview => find.byTooltip('Show full screen');

Finder get hint => find.textContaining('This code is dense');

void main() {
  testWidgets('tapping the code shows it full screen and back', (tester) async {
    final calls = await pumpHome(tester, const Size(1280, 800));
    await fillSsid(tester);

    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenQr), findsOneWidget);
    expect(calls, [true]);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenQr), findsNothing);
    expect(calls, [true, false]);
  });

  testWidgets('Esc closes the full-screen code', (tester) async {
    final calls = await pumpHome(tester, const Size(1280, 800));
    await fillSsid(tester);
    await tester.tap(preview);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(FullScreenQr), findsNothing);
    expect(calls, [true, false]);
  });

  testWidgets('the full-screen code fills the shorter side', (tester) async {
    await pumpHome(tester, const Size(1280, 800));
    await fillSsid(tester);
    await tester.tap(preview);
    await tester.pumpAndSettle();

    final code = tester.getSize(
      find.descendant(
        of: find.byType(FullScreenQr),
        matching: find.byType(QrImageView),
      ),
    );
    // The close hint below takes a line of the height.
    expect(code.width, greaterThan(700));
    expect(code.width, code.height);
  });

  /// The white box the preview draws the code on.
  Size codeBox(WidgetTester tester) => tester.getSize(
    find.ancestor(of: preview, matching: find.byType(Container)).first,
  );

  for (final size in [const Size(1920, 1080), const Size(1280, 500)]) {
    testWidgets(
      'the preview stays square in a ${size.width}x${size.height} window',
      (tester) async {
        await pumpHome(tester, size);
        await fillSsid(tester);

        final box = codeBox(tester);
        expect(box.width, box.height);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the preview grows with the window', (tester) async {
    await pumpHome(tester, const Size(1920, 1080));
    await fillSsid(tester);
    expect(codeBox(tester).width, greaterThan(500));
  });

  testWidgets('a short code needs no hint', (tester) async {
    await pumpHome(tester, const Size(1280, 800));
    await fillSsid(tester);
    expect(hint, findsNothing);
  });

  for (final (name, size, pixel) in [
    ('phone', const Size(390, 844), phonePixel),
    ('desktop', const Size(1280, 800), desktopPixel),
  ]) {
    testWidgets(
      'a dense code says it can be shown full screen at $name width',
      (tester) async {
        await pumpHome(tester, size, mmPerPixel: pixel);
        await fillDenseText(tester);

        expect(hint, findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the same code on a large-pixel screen needs no hint', (
    tester,
  ) async {
    // A big TV: modules are large in the world even at a pixel or two each.
    await pumpHome(tester, const Size(1280, 800), mmPerPixel: 1.0);
    await fillDenseText(tester);
    expect(hint, findsNothing);
  });

  testWidgets('a phone without a reported size assumes 160 per inch', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpHome(tester, const Size(390, 844), mmPerPixel: null);
    await fillDenseText(tester);
    expect(hint, findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the hint says click on a desktop', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpHome(tester, const Size(1280, 800));
    await fillDenseText(tester);
    expect(find.textContaining('Click it to show it full screen'), findsOne);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the hint says tap on a phone', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpHome(tester, const Size(390, 844), mmPerPixel: phonePixel);
    await fillDenseText(tester);
    expect(find.textContaining('Tap it to show it full screen'), findsOne);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on Linux, asks the runner for full screen', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async => calls.add(call),
    );

    await setFullScreen(true);
    await setFullScreen(false);

    expect(calls.map((c) => (c.method, c.arguments)), [
      ('setFullScreen', true),
      ('setFullScreen', false),
    ]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('on Linux, asks the runner how large a pixel is', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    for (final (answer, expected) in [
      (0.28, 0.28),
      // A monitor that does not report its size.
      (0.0, null),
    ]) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        (call) async => call.method == 'millimetresPerPixel' ? answer : null,
      );
      expect(await readMillimetresPerPixel(), expected);
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a runner without the channel still shows the code', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    // No handler registered: invokeMethod throws MissingPluginException.
    await setFullScreen(true);
    debugDefaultTargetPlatformOverride = null;
  });
}
