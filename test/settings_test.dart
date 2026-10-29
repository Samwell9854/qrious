import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/qr_encoding.dart';
import 'package:qrious/qr_export.dart';
import 'package:qrious/qr_png.dart';
import 'package:qrious/screens/home_screen.dart';
import 'package:qrious/settings.dart';

const custom = Settings(
  errorCorrection: ErrorCorrection.high,
  imageSize: ImageSize.large,
  saveFileType: ExportFileType.svg,
);

/// The screen at [size], launched with [settings]. Saving settings is always stubbed
/// so a test can never write to the real config folder.
Future<List<Settings>> pumpHome(
  WidgetTester tester, {
  Settings settings = const Settings(),
  Size size = const Size(1280, 800),
  SettingsSaver? save,
  List<ExportFileType>? picked,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final saved = <Settings>[];
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        settings: settings,
        saveSettings: save ?? (s) async => saved.add(s),
        pickSaveLocation: (_, type) async {
          picked?.add(type);
          return null;
        },
      ),
    ),
  );
  return saved;
}

Future<void> fillSsid(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Network Name (SSID)'),
    'MyNetwork',
  );
  await tester.pump();
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

/// The settings view's dropdown labelled [field], set to [choice]. The view is on top,
/// so its label is the last of that text, the preview's own dropdown being under it.
Future<void> chooseSetting(
  WidgetTester tester,
  String field,
  String choice,
) async {
  await tester.tap(
    find
        .ancestor(
          of: find.text(field).last,
          matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(choice).last);
  await tester.pumpAndSettle();
}

Future<void> closeSettings(WidgetTester tester) async {
  final close = find.widgetWithText(TextButton, 'Close');
  await tester.tap(
    close.evaluate().isNotEmpty ? close : find.byType(CloseButton),
  );
  await tester.pumpAndSettle();
}

/// What the preview's dropdown of type [T] shows.
T panelValue<T>(WidgetTester tester) =>
    tester.widget<DropdownButton<T>>(find.byType(DropdownButton<T>).first).value
        as T;

void main() {
  group('the settings file', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('qrious-settings'));
    tearDown(() => temp.deleteSync(recursive: true));

    test('lives under XDG_CONFIG_HOME, else ~/.config', () {
      expect(
        settingsFile({'XDG_CONFIG_HOME': '/x/conf', 'HOME': '/home/u'})!.path,
        '/x/conf/qrious/settings.json',
      );
      expect(
        settingsFile({'HOME': '/home/u'})!.path,
        '/home/u/.config/qrious/settings.json',
      );
    });

    test('a relative XDG_CONFIG_HOME is ignored, as the spec says', () {
      expect(
        settingsFile({'XDG_CONFIG_HOME': 'conf', 'HOME': '/home/u'})!.path,
        '/home/u/.config/qrious/settings.json',
      );
    });

    test('has no location without a home or config folder', () {
      expect(settingsFile({}), isNull);
    });

    test('round-trips, creating its folder', () async {
      final file = File('${temp.path}/qrious/settings.json');
      await saveSettings(custom, file);
      expect(await loadSettings(file), custom);
      expect(jsonDecode(file.readAsStringSync()), {
        'errorCorrection': 'high',
        'imageSize': 'large',
        'saveFileType': 'svg',
      });
    });

    test('asking each time is written as such, not left out', () async {
      final file = File('${temp.path}/settings.json');
      await saveSettings(const Settings(), file);
      expect(jsonDecode(file.readAsStringSync())['saveFileType'], 'ask');
      expect(await loadSettings(file), const Settings());
    });

    test('a missing file gives the defaults', () async {
      expect(
        await loadSettings(File('${temp.path}/none.json')),
        const Settings(),
      );
    });

    test('a broken file gives the defaults', () async {
      final file = File('${temp.path}/settings.json')
        ..writeAsStringSync('{"errorCorrection": ');
      expect(await loadSettings(file), const Settings());
    });

    test('an unknown value costs that setting only', () async {
      final file = File('${temp.path}/settings.json')
        ..writeAsStringSync(
          '{"errorCorrection": "extreme", "imageSize": "large", '
          '"saveFileType": "svg"}',
        );
      expect(
        await loadSettings(file),
        const Settings(
          imageSize: ImageSize.large,
          saveFileType: ExportFileType.svg,
        ),
      );
    });
  });

  group('the screen', () {
    testWidgets('starts from the launch settings', (tester) async {
      await pumpHome(tester, settings: custom);
      expect(panelValue<ErrorCorrection>(tester), ErrorCorrection.high);
      expect(panelValue<ImageSize>(tester), ImageSize.large);
    });

    testWidgets('with a save file type, Save goes straight to the dialog', (
      tester,
    ) async {
      final picked = <ExportFileType>[];
      await pumpHome(tester, settings: custom, picked: picked);
      await fillSsid(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Save SVG'));
      await tester.pumpAndSettle();
      expect(picked, [ExportFileType.svg]);
      expect(find.text(ExportFileType.png.label), findsNothing);
    });

    testWidgets('asking each time keeps the menu', (tester) async {
      await pumpHome(tester);
      await fillSsid(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text(ExportFileType.png.label), findsOneWidget);
      expect(find.text(ExportFileType.svg.label), findsOneWidget);
    });

    testWidgets('a failed write says so', (tester) async {
      await pumpHome(
        tester,
        save: (_) async => throw const FileSystemException('read-only'),
      );
      await openSettings(tester);
      await chooseSetting(tester, 'Image size', 'Large');
      expect(find.textContaining('Could not save settings'), findsOneWidget);
    });
  });

  for (final (name, size, dialog) in [
    ('phone', const Size(390, 844), false),
    ('desktop', const Size(1280, 800), true),
  ]) {
    group('settings on a $name', () {
      testWidgets('open as a ${dialog ? 'dialog' : 'page'}', (tester) async {
        await pumpHome(tester, size: size);
        await openSettings(tester);
        expect(
          find.byType(AlertDialog),
          dialog ? findsOneWidget : findsNothing,
        );
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Ask each time (default)'), findsOneWidget);
      });

      testWidgets('mark the default of each setting', (tester) async {
        await pumpHome(tester, size: size, settings: custom);
        await openSettings(tester);
        await tester.tap(find.text('High (25%)').last);
        await tester.pumpAndSettle();
        expect(find.text('Auto (default)'), findsOneWidget);
        expect(find.text('Highest (30%)'), findsWidgets);
        await tester.tap(find.text('Auto (default)'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Large').last);
        await tester.pumpAndSettle();
        expect(find.text('Medium (default)'), findsOneWidget);
        await tester.tap(find.text('Medium (default)'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Always SVG image'));
        await tester.pumpAndSettle();
        expect(find.text('Ask each time (default)'), findsOneWidget);
      });

      testWidgets('reset to the defaults, current code included', (
        tester,
      ) async {
        final saved = await pumpHome(tester, size: size, settings: custom);
        await fillSsid(tester);
        await openSettings(tester);

        final reset = find.widgetWithText(TextButton, 'Reset to defaults');
        await tester.tap(reset);
        await tester.pumpAndSettle();
        expect(saved, const [Settings()]);
        expect(find.text('Auto (default)'), findsOneWidget);
        expect(find.text('Medium (default)'), findsOneWidget);
        expect(find.text('Ask each time (default)'), findsOneWidget);
        expect(tester.widget<TextButton>(reset).onPressed, isNull);

        await closeSettings(tester);
        expect(panelValue<ErrorCorrection>(tester), ErrorCorrection.auto);
        expect(panelValue<ImageSize>(tester), ImageSize.medium);
        expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      });

      testWidgets('save each change as it is made', (tester) async {
        final saved = await pumpHome(tester, size: size);
        await openSettings(tester);
        await chooseSetting(tester, 'Error correction', 'Highest (30%)');
        await chooseSetting(tester, 'Save as', 'Always PNG image');
        expect(saved, const [
          Settings(errorCorrection: ErrorCorrection.highest),
          Settings(
            errorCorrection: ErrorCorrection.highest,
            saveFileType: ExportFileType.png,
          ),
        ]);
      });

      testWidgets('a changed default shows on the current code', (
        tester,
      ) async {
        await pumpHome(tester, size: size);
        await fillSsid(tester);
        await openSettings(tester);
        await chooseSetting(tester, 'Image size', 'Extra large');
        await closeSettings(tester);

        expect(panelValue<ImageSize>(tester), ImageSize.extraLarge);
        expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      });
    });
  }
}
