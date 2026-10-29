import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/screens/home_screen.dart';
import 'package:qrious/settings.dart';

/// The screen with the given mode, and every image read stubbed to find [payloads].
Future<List<Settings>> pumpHome(
  WidgetTester tester, {
  bool expert = true,
  List<String> payloads = const [],
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final saved = <Settings>[];
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        settings: Settings(expertMode: expert),
        saveSettings: (s) async => saved.add(s),
        pickImageFile: () async => Uint8List.fromList([1]),
        decodeImage: (_) async => payloads,
      ),
    ),
  );
  return saved;
}

Future<void> chooseFormat(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
  await tester.pumpAndSettle();
  final item = find.text(name).hitTestable();
  await tester.scrollUntilVisible(
    item,
    50,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(item.last);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextFormField, label).first;
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

String payload(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byType(SelectableText)).data!;

Future<void> toggleExpert(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Expert mode'));
  await tester.pumpAndSettle();
  final close = find.widgetWithText(TextButton, 'Close');
  await tester.tap(
    close.evaluate().isNotEmpty ? close : find.byType(CloseButton),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a vCard phone takes several types, which beginner reads as one',
    (tester) async {
      await pumpHome(tester);
      await chooseFormat(tester, 'Contact (vCard)');
      await type(tester, 'First Name', 'Jo');
      await tapText(tester, 'Add phone');
      await type(tester, 'Phone · Mobile', '5550000');

      await tester.tap(find.byTooltip('Phone types'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main'));
      await tester.pumpAndSettle();
      // The checklist stays open for the next pick; Escape closes it.
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(find.text('Phone · Mobile, Voice, Main'), findsOneWidget);
      expect(payload(tester), contains('TEL;TYPE=CELL,VOICE,PREF:5550000'));

      await toggleExpert(tester);
      expect(find.text('Phone · Mobile'), findsOneWidget);
      expect(payload(tester), contains('TEL;TYPE=CELL:5550000'));

      await toggleExpert(tester);
      expect(payload(tester), contains('TEL;TYPE=CELL,VOICE,PREF:5550000'));
    },
  );

  testWidgets('sms: shows extra recipients, and beginner mode hides it all', (
    tester,
  ) async {
    await pumpHome(tester);
    await chooseFormat(tester, 'Text Message (SMS)');
    expect(find.text('Add recipient'), findsNothing);

    await tester.tap(find.text('SMSTO:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sms:').last);
    await tester.pumpAndSettle();
    await type(tester, 'Phone Number', '+1 555 000 0000');
    await tapText(tester, 'Add recipient');
    await type(tester, 'Phone Number', '+1 555 000 0000');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone Number').last,
      '5550001',
    );
    await tester.pump();
    expect(payload(tester), 'sms:+15550000000,5550001');

    await toggleExpert(tester);
    expect(find.text('Payload Form'), findsNothing);
    expect(find.text('Add recipient'), findsNothing);
    expect(payload(tester), 'SMSTO:+1 555 000 0000');
  });

  testWidgets('a MeCard birthday is picked from a calendar', (tester) async {
    await pumpHome(tester);
    await chooseFormat(tester, 'Contact (MeCard, compact)');
    await type(tester, 'First Name', 'Jo');
    await type(tester, 'Birthday', '1990-04-12');
    expect(payload(tester), contains('BDAY:19900412;'));

    await tester.ensureVisible(find.byTooltip('Pick a date'));
    await tester.tap(find.byTooltip('Pick a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(payload(tester), contains('BDAY:19900415;'));
  });

  testWidgets('a Location takes altitude and uncertainty only in expert', (
    tester,
  ) async {
    await pumpHome(tester);
    await chooseFormat(tester, 'Location');
    await type(tester, 'Latitude', '45.5');
    await type(tester, 'Longitude', '-73.5');
    await type(tester, 'Altitude (metres)', '30');
    await type(tester, 'Uncertainty (metres)', '5');
    expect(payload(tester), 'geo:45.5,-73.5,30;u=5');
    await toggleExpert(tester);
    expect(find.text('Altitude (metres)'), findsNothing);
    expect(payload(tester), 'geo:45.5,-73.5');
  });

  for (final (name, size) in [
    ('phone', const Size(390, 844)),
    ('desktop', const Size(1280, 800)),
  ]) {
    testWidgets('every expert field fits at $name width', (tester) async {
      await pumpHome(tester, size: size);
      for (final format in [
        'Contact (MeCard, compact)',
        'Contact (vCard)',
        'Text Message (SMS)',
        'Location',
      ]) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
        await chooseFormat(tester, format);
        expect(tester.takeException(), isNull, reason: format);
      }
    });
  }

  group('reading a code that needs expert fields', () {
    const mecard = 'MECARD:N:Jo;NOTE:hi;;';

    testWidgets('opens in its form in expert mode', (tester) async {
      await pumpHome(tester, payloads: [mecard]);
      await tester.tap(find.byTooltip('Read a QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open image…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Recognised as'), findsNothing);
      expect(payload(tester), mecard);
    });

    testWidgets('opens as text in beginner mode, pointing to expert', (
      tester,
    ) async {
      await pumpHome(tester, expert: false, payloads: [mecard]);
      await tester.tap(find.byTooltip('Read a QR code'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open image…'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('cannot hold Note in beginner mode'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Expert mode, in Settings, has fields for them'),
        findsOneWidget,
      );
    });
  });
}
