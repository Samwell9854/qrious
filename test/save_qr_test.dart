import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/qr_export.dart';
import 'package:qrious/screens/home_screen.dart';

/// Drives the screen with a stand-in for the save dialog, since a real GTK
/// dialog cannot open in a test. Everything after the dialog — rendering the
/// file and writing it — runs for real against a temp directory.
Future<void> pumpHome(
  WidgetTester tester,
  Future<String?> Function(String suggestedName, ExportFileType type) pick,
) async {
  await tester.pumpWidget(
    MaterialApp(home: HomeScreen(pickSaveLocation: pick)),
  );
}

Future<void> fillSsid(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Network Name (SSID)'),
    'MyNetwork',
  );
  await tester.pump();
}

/// Opens the Save menu and picks [type].
Future<void> openSave(WidgetTester tester, ExportFileType type) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(type.label));
  await tester.pump();
}

/// Saves as [type] and waits for the write.
Future<void> saveAs(WidgetTester tester, ExportFileType type) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
  // The pick inside runAsync: the handler renders and writes across several
  // real async gaps, which deadlock against the fake async a widget test runs in.
  await tester.runAsync(() async {
    await tester.tap(find.text(type.label));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('qrious-save'));
  tearDown(() => temp.deleteSync(recursive: true));

  testWidgets('the save button is disabled until there is a code', (
    tester,
  ) async {
    await pumpHome(tester, (_, _) async => null);

    FilledButton button() =>
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(button().onPressed, isNull);

    await fillSsid(tester);
    expect(button().onPressed, isNotNull);
  });

  testWidgets('writes a PNG where the dialog said to', (tester) async {
    final path = '${temp.path}/code.png';
    await pumpHome(tester, (_, _) async => path);
    await fillSsid(tester);

    await saveAs(tester, ExportFileType.png);

    final written = File(path);
    expect(written.existsSync(), isTrue);
    expect(Uint8List.fromList(written.readAsBytesSync()).take(8), const [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
    expect(find.textContaining('Saved'), findsOneWidget);
  });

  testWidgets('appends .png when the chosen name has no extension', (
    tester,
  ) async {
    await pumpHome(tester, (_, _) async => '${temp.path}/code');
    await fillSsid(tester);

    await saveAs(tester, ExportFileType.png);

    expect(File('${temp.path}/code.png').existsSync(), isTrue);
  });

  testWidgets('suggests a name carrying the selected format', (tester) async {
    String? suggested;
    ExportFileType? offered;
    await pumpHome(tester, (name, type) async {
      suggested = name;
      offered = type;
      return null;
    });
    await fillSsid(tester);

    await openSave(tester, ExportFileType.svg);
    await tester.pumpAndSettle();

    expect(suggested, startsWith('qrious-wifi-'));
    expect(suggested, endsWith('.svg'));
    expect(offered, ExportFileType.svg);
  });

  testWidgets('writes nothing and says nothing when cancelled', (tester) async {
    await pumpHome(tester, (_, _) async => null);
    await fillSsid(tester);

    await openSave(tester, ExportFileType.png);
    await tester.pumpAndSettle();

    expect(temp.listSync(), isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('reports a failure instead of throwing', (tester) async {
    // A directory that does not exist: the write fails, the app must not.
    await pumpHome(tester, (_, _) async => '${temp.path}/nope/code.png');
    await fillSsid(tester);

    await saveAs(tester, ExportFileType.png);

    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('writes an SVG when SVG is picked', (tester) async {
    final path = '${temp.path}/code.svg';
    await pumpHome(tester, (_, _) async => path);
    await fillSsid(tester);

    await saveAs(tester, ExportFileType.svg);

    expect(File(path).readAsStringSync(), contains('<svg'));
    expect(find.textContaining('Saved'), findsOneWidget);
  });

  testWidgets('does not trust a name carrying the other type\'s extension', (
    tester,
  ) async {
    await pumpHome(tester, (_, _) async => '${temp.path}/code.png');
    await fillSsid(tester);

    await saveAs(tester, ExportFileType.svg);

    expect(File('${temp.path}/code.png.svg').existsSync(), isTrue);
    expect(File('${temp.path}/code.png').existsSync(), isFalse);
  });
}
