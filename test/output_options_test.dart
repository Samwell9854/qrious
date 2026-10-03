import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:qrious/main.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/qr_encoding.dart';
import 'package:qrious/qr_png.dart';

const payload = 'WIFI:T:WPA;S:MyNetwork;P:;H:false;;';

Future<void> pumpWithCode(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const QriousApp());
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Network Name (SSID)'),
    'MyNetwork',
  );
  await tester.pump();
}

/// Picks [label] from the dropdown of type [T], scrolling it into view first.
Future<void> choose<T>(WidgetTester tester, String label) async {
  final dropdown = find.byType(DropdownButtonFormField<T>);
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size) in [
    ('phone', const Size(390, 844)),
    ('desktop', const Size(1280, 800)),
  ]) {
    testWidgets('fit beside each other at $name width, longest label chosen', (
      tester,
    ) async {
      await pumpWithCode(tester, size);
      await choose<ErrorCorrection>(tester, 'Highest (30%)');
      await choose<ImageSize>(tester, 'Extra large');

      // A RenderFlex overflow would surface here as an exception.
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('Highest error correction, survives 30% damage'),
        findsOneWidget,
      );
    });
  }

  testWidgets('the caption says what auto chose and the image size', (
    tester,
  ) async {
    await pumpWithCode(tester, const Size(1280, 800));

    final qr = encodeQr(payload, ErrorCorrection.auto);
    final side = ImageSize.medium.pixelsFor(qr);
    expect(
      find.text(
        'Auto: ${qr.errorCorrection.label} error correction, survives '
        '${qr.errorCorrection.recoveryPercent}% damage · $side × $side px',
      ),
      findsOneWidget,
    );
  });

  testWidgets('changing the image size updates the caption', (tester) async {
    await pumpWithCode(tester, const Size(1280, 800));
    await choose<ImageSize>(tester, 'Large');

    final side = ImageSize.large.pixelsFor(
      encodeQr(payload, ErrorCorrection.auto),
    );
    expect(find.textContaining('$side × $side px'), findsOneWidget);
  });

  testWidgets('a chosen level replaces auto', (tester) async {
    await pumpWithCode(tester, const Size(1280, 800));
    await choose<ErrorCorrection>(tester, 'Low (7%)');

    // The caption and the preview are built from the same encoded symbol.
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.textContaining('Low error correction, survives 7% damage'),
      findsOneWidget,
    );
    expect(find.textContaining('Auto:'), findsNothing);
  });

  testWidgets('says so when the payload is too long, and disables saving', (
    tester,
  ) async {
    await tester.pumpWidget(const QriousApp());
    await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plain Text').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Text'),
      'x' * 3000,
    );
    await tester.pump();

    expect(find.byType(QrImageView), findsNothing);
    expect(
      find.text('Too much data for a QR code\nat this error correction'),
      findsOneWidget,
    );
    final save = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Save PNG'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(save.onPressed, isNull);
  });
}
