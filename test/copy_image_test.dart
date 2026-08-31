import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/image_clipboard.dart';
import 'package:qrious/screens/home_screen.dart';

Future<void> pumpHome(WidgetTester tester, PngClipboardCopier copy) async {
  await tester.pumpWidget(MaterialApp(home: HomeScreen(copyImage: copy)));
}

Future<void> fillSsid(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Network Name (SSID)'),
    'MyNetwork',
  );
  await tester.pump();
}

Finder get copyButton => find.widgetWithText(OutlinedButton, 'Copy image');

Future<void> tapCopy(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(copyButton);
    await tester.pump();
    // Rendering the PNG spans several async gaps.
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('is disabled until there is a code to copy', (tester) async {
    await pumpHome(tester, (_) async {});

    OutlinedButton button() => tester.widget<OutlinedButton>(copyButton);
    expect(button().onPressed, isNull);

    await fillSsid(tester);
    expect(button().onPressed, isNotNull);
  });

  testWidgets('hands the clipboard a real PNG', (tester) async {
    Uint8List? copied;
    await pumpHome(tester, (bytes) async => copied = bytes);
    await fillSsid(tester);
    await tapCopy(tester);

    expect(copied?.take(8), const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
    expect(find.text('QR code copied as an image'), findsOneWidget);
  });

  testWidgets('shows what to install when there is no clipboard helper', (
    tester,
  ) async {
    await pumpHome(
      tester,
      (_) async => throw const ImageClipboardException('no wl-copy here'),
    );
    await fillSsid(tester);
    await tapCopy(tester);

    // The message is the actionable part, so it reaches the user unchanged.
    expect(find.text('no wl-copy here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reports an unexpected failure instead of throwing', (
    tester,
  ) async {
    await pumpHome(tester, (_) async => throw StateError('boom'));
    await fillSsid(tester);
    await tapCopy(tester);

    expect(find.textContaining('Could not copy'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
