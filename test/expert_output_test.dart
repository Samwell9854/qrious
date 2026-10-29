import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/qr_encoding.dart';
import 'package:qrious/qr_png.dart';
import 'package:qrious/screens/home_screen.dart';
import 'package:qrious/settings.dart';
import 'package:qrious/widgets/qr_symbol.dart';

const payload = 'WIFI:T:WPA;S:MyNetwork;P:;H:false;;';

Future<void> pumpExpert(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  Settings settings = const Settings(expertMode: true),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(settings: settings, saveSettings: (_) async {}),
    ),
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Network Name (SSID)'),
    'MyNetwork',
  );
  await tester.pump();
}

Finder field(String label) => find.widgetWithText(TextField, label);

Future<void> type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), text);
  await tester.pump();
}

String textOf(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label)).controller!.text;

void main() {
  final qr = encodeQr(payload, ErrorCorrection.auto);
  final n = qr.moduleCount;

  testWidgets('the caption gives the spec details', (tester) async {
    await pumpExpert(tester);
    final modes = {
      for (final s in qr.segments) s.mode.label.toLowerCase(),
    }.join(' + ');
    final side = (n + 8) * 8;
    expect(
      find.text(
        'Auto: ${qr.errorCorrection.choiceLabel(expert: true)} · '
        'version ${qr.version} ($n×$n) · mask ${qr.mask} · $modes · '
        '$side × $side px',
      ),
      findsOneWidget,
    );
  });

  for (final (name, size) in [
    ('phone', const Size(390, 844)),
    ('desktop', const Size(1280, 800)),
  ]) {
    testWidgets('the expert rows fit at $name width', (tester) async {
      await pumpExpert(tester, size: size);
      await type(tester, 'Pixels per module', '100');
      await type(tester, 'Quiet zone (modules)', '40');
      expect(tester.takeException(), isNull);
      expect(find.textContaining('${(n + 80) * 100} px'), findsOneWidget);
    });
  }

  testWidgets('a size above what the code can take is refused', (tester) async {
    await pumpExpert(tester);
    final max = maxImageSide ~/ (n + 8);
    expect(find.text('1–$max'), findsOneWidget);
    await type(tester, 'Pixels per module', '$max');
    await type(tester, 'Pixels per module', '${max + 1}');
    expect(textOf(tester, 'Pixels per module'), '$max');
    // Nor can a zero be started, which no further digit could make valid.
    await type(tester, 'Pixels per module', '0');
    expect(textOf(tester, 'Pixels per module'), '$max');
  });

  testWidgets('no quiet zone draws the code edge to edge', (tester) async {
    await pumpExpert(tester);
    await type(tester, 'Quiet zone (modules)', '0');
    expect(tester.widget<QrSymbol>(find.byType(QrSymbol)).quietZone, 0);
    expect(find.textContaining('${n * 8} × ${n * 8} px'), findsOneWidget);
  });

  testWidgets('a code that outgrows a size gets the nearest and says so', (
    tester,
  ) async {
    await pumpExpert(tester);
    final max = maxImageSide ~/ (n + 8);
    await type(tester, 'Pixels per module', '$max');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'a much longer password that needs a larger symbol than before',
    );
    await tester.pump();
    expect(
      find.textContaining('$max px per module is too large for this code'),
      findsOneWidget,
    );
    // The pick is kept, and applies again once the code is small enough.
    expect(textOf(tester, 'Pixels per module'), '$max');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), '');
    await tester.pump();
    expect(find.textContaining('too large'), findsNothing);
    expect(find.textContaining('${(n + 8) * max} px'), findsOneWidget);
  });

  testWidgets('beginner mode ignores expert choices and keeps them', (
    tester,
  ) async {
    await pumpExpert(
      tester,
      settings: const Settings(
        expertMode: true,
        pixelsPerModule: 3,
        quietZone: 1,
      ),
    );
    expect(find.textContaining('${(n + 2) * 3} px'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expert mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(field('Pixels per module'), findsNothing);
    expect(find.textContaining('${(n + 8) * 8} × ${(n + 8) * 8} px'), findsOne);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expert mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();
    expect(textOf(tester, 'Pixels per module'), '3');
    expect(find.textContaining('${(n + 2) * 3} px'), findsOneWidget);
  });
}
