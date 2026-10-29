import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/qr_encoding.dart';
import 'package:qrious/qr_png.dart';
import 'package:qrious/qr_segments.dart';
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

/// Opens the dropdown labelled [label] and taps [choice] in its menu.
Future<void> pick(WidgetTester tester, String label, String choice) async {
  final dropdown = find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
      )
      .first;
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  // A long menu builds only what it shows. The closed field keeps an offstage copy
  // of every label, so only a tappable one is the menu's.
  final item = find.text(choice).hitTestable();
  await tester.scrollUntilVisible(
    item,
    100,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(item.last);
  await tester.pumpAndSettle();
}

/// Switches to the Plain Text format and types [text] into it.
Future<void> plainText(WidgetTester tester, String text) async {
  await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
  await tester.pumpAndSettle();
  final item = find.text('Plain Text').hitTestable();
  await tester.scrollUntilVisible(
    item,
    50,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(item);
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextFormField, 'Text'), text);
  await tester.pump();
}

/// Whether the menu item reading [text] can be picked. The menu must be open.
bool enabled(WidgetTester tester, String text) => tester
    .widget<DropdownMenuItem<Object>>(
      find
          .ancestor(
            of: find.text(text).last,
            matching: find.byWidgetPredicate((w) => w is DropdownMenuItem),
          )
          .first,
    )
    .enabled;

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

  testWidgets('a forced version and mask draw the code as chosen', (
    tester,
  ) async {
    await pumpExpert(tester);
    await pick(tester, 'Version', '10 (57×57)');
    await pick(tester, 'Mask', '6');
    final drawn = tester.widget<QrSymbol>(find.byType(QrSymbol)).qr;
    expect(drawn.version, 10);
    expect(drawn.mask, 6);
    expect(find.textContaining('version 10 (57×57) · mask 6'), findsOneWidget);
  });

  testWidgets('versions too small for the text cannot be picked', (
    tester,
  ) async {
    await pumpExpert(tester);
    final dropdown = find
        .ancestor(
          of: find.text('Version'),
          matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        )
        .first;
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('1 (21×21) · too small'), findsOneWidget);
    expect(
      find.text('${qr.version} (${qr.moduleCount}×${qr.moduleCount})'),
      findsWidgets,
    );
  });

  testWidgets('modes the text cannot be written in cannot be picked', (
    tester,
  ) async {
    await pumpExpert(tester);
    final dropdown = find
        .ancestor(
          of: find.text('Encoding mode'),
          matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        )
        .first;
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(find.text('Numeric · digits only'), findsOneWidget);
    expect(find.text('Alphanumeric · text has other characters'), findsOne);
    expect(enabled(tester, 'Numeric · digits only'), isFalse);
    expect(enabled(tester, 'Byte'), isTrue);
  });

  testWidgets('a pick the text outgrows gives way, says so and comes back', (
    tester,
  ) async {
    await pumpExpert(tester);
    await pick(tester, 'Version', '${qr.version} ($n×$n)');
    await pick(tester, 'Encoding mode', 'Byte');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'a much longer password that needs a larger symbol than before',
    );
    await tester.pump();
    expect(
      find.textContaining('version ${qr.version} is too small for this text'),
      findsOneWidget,
    );

    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), '');
    await tester.pump();
    expect(find.textContaining('too small'), findsNothing);
    final drawn = tester.widget<QrSymbol>(find.byType(QrSymbol)).qr;
    expect(drawn.version, qr.version);
    expect(drawn.mode, EncodingMode.byte);
  });

  testWidgets('a mode the text outgrows gives way to the split', (
    tester,
  ) async {
    await pumpExpert(tester);
    await plainText(tester, '0123456789');
    await pick(tester, 'Encoding mode', 'Numeric');
    expect(find.textContaining('· numeric ·'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Text'), '01x');
    await tester.pump();
    expect(
      find.textContaining(
        'numeric cannot write this text; using the automatic',
      ),
      findsOneWidget,
    );
  });

  for (final (name, size) in [
    ('phone', const Size(390, 844)),
    ('desktop', const Size(1280, 800)),
  ]) {
    testWidgets('every expert row fits at $name width, longest picks', (
      tester,
    ) async {
      await pumpExpert(tester, size: size);
      await pick(tester, 'Error correction', 'Q – High (25%)');
      await pick(tester, 'Version', '40 (177×177)');
      await pick(tester, 'Mask', '7');
      await pick(tester, 'Encoding mode', 'Byte');
      expect(tester.takeException(), isNull);
      expect(
        find.textContaining('version 40 (177×177) · mask 7 · byte'),
        findsOneWidget,
      );
    });

    testWidgets('expert settings fit at $name width', (tester) async {
      await pumpExpert(tester, size: size);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      for (final label in ['Version', 'Mask', 'Encoding mode']) {
        expect(find.text(label), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('beginner mode greys out levels too short for the text', (
    tester,
  ) async {
    await pumpExpert(tester, settings: const Settings());
    await pick(tester, 'Error correction', 'High (25%)');
    // Version 40 holds 2331 bytes at medium and 2953 at low.
    await plainText(tester, 'x' * 2500);
    expect(
      find.textContaining('High cannot hold this text; using Low'),
      findsOneWidget,
    );

    final dropdown = find.byType(DropdownButtonFormField<ErrorCorrection>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(enabled(tester, 'Medium (15%) · too much data'), isFalse);
    expect(enabled(tester, 'Low (7%)'), isTrue);
  });
}
