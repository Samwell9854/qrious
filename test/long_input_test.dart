import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/screens/home_screen.dart';

/// Near the most a QR code holds, so the payload box would run to dozens of lines
/// if nothing capped it.
final longText = 'A long note that keeps going. ' * 70;

Future<void> pumpHome(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
}

Future<void> pickFormat(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> fillText(WidgetTester tester, String text) async {
  await pickFormat(tester, 'Plain Text');
  await tester.enterText(find.byType(TextFormField), text);
  await tester.pump();
}

void main() {
  for (final size in [
    const Size(1280, 800),
    const Size(1280, 500),
    const Size(800, 420),
    const Size(390, 844),
  ]) {
    testWidgets(
      'a long payload fits a ${size.width}x${size.height} window without overflow',
      (tester) async {
        await pumpHome(tester, size);
        await fillText(tester, longText);

        expect(tester.takeException(), isNull);
        expect(find.byType(QrImageView), findsOneWidget);
        // The code keeps a readable minimum rather than being squeezed away.
        expect(
          tester.getSize(find.byType(QrImageView)).width,
          greaterThanOrEqualTo(200),
        );
      },
    );
  }

  testWidgets('the payload box stops growing and scrolls instead', (
    tester,
  ) async {
    await pumpHome(tester, const Size(1280, 800));
    await fillText(tester, longText);

    final payload = find.ancestor(
      of: find.byType(SelectableText),
      matching: find.byType(ConstrainedBox),
    );
    expect(tester.getSize(payload.first).height, lessThanOrEqualTo(150));
  });
}
