import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/screens/home_screen.dart';

Future<void> pumpVCard(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Contact (vCard)').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'First Name'),
    'Ada',
  );
  await tester.pump();
}

Future<void> add(WidgetTester tester, String what) async {
  await tester.ensureVisible(find.text('Add $what'));
  await tester.tap(find.text('Add $what'));
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

String payload(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byType(SelectableText)).data!;

void main() {
  const desktop = Size(1280, 800);

  testWidgets('a vCard starts with no phone, email or address fields', (
    tester,
  ) async {
    await pumpVCard(tester, desktop);
    expect(find.textContaining('Phone ·'), findsNothing);
    expect(find.textContaining('Email ·'), findsNothing);
    expect(find.text('Street Address'), findsNothing);
    expect(find.text('Add phone'), findsOneWidget);
    expect(find.text('Add email'), findsOneWidget);
    expect(find.text('Add address'), findsOneWidget);
  });

  testWidgets('an added phone is a mobile until its kind is changed', (
    tester,
  ) async {
    await pumpVCard(tester, desktop);
    await add(tester, 'phone');
    await type(tester, 'Phone · Mobile', '+15145550000,274');
    expect(payload(tester), contains('TEL;TYPE=CELL:+15145550000,274'));

    await tester.tap(find.byTooltip('Phone type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Phone · Work'), findsOneWidget);
    expect(payload(tester), contains('TEL;TYPE=WORK:+15145550000,274'));
  });

  testWidgets('a vCard phone takes a wait; a MeCard phone would not', (
    tester,
  ) async {
    await pumpVCard(tester, desktop);
    await add(tester, 'phone');
    await type(tester, 'Phone · Mobile', '+15145551234;274,4');
    expect(find.textContaining('Use digits'), findsNothing);
    expect(payload(tester), contains('TEL;TYPE=CELL:+15145551234;274,4'));
  });

  testWidgets('several of each, including two work emails', (tester) async {
    await pumpVCard(tester, desktop);
    await add(tester, 'email');
    await add(tester, 'email');
    final menus = find.byTooltip('Email type');
    for (final i in [0, 1]) {
      await tester.tap(menus.at(i));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work').last);
      await tester.pumpAndSettle();
    }
    final fields = find.widgetWithText(TextFormField, 'Email · Work');
    await tester.enterText(fields.at(0), 'a@x.io');
    await tester.enterText(fields.at(1), 'b@x.io');
    await tester.pump();

    expect(
      payload(tester),
      allOf(
        contains('EMAIL;TYPE=WORK:a@x.io'),
        contains('EMAIL;TYPE=WORK:b@x.io'),
      ),
    );
  });

  testWidgets('removing an entry keeps the others, in order', (tester) async {
    await pumpVCard(tester, desktop);
    for (final _ in [1, 2, 3]) {
      await add(tester, 'phone');
    }
    final fields = find.widgetWithText(TextFormField, 'Phone · Mobile');
    for (final (i, number) in ['5550001', '5550002', '5550003'].indexed) {
      await tester.enterText(fields.at(i), number);
    }
    await tester.pump();

    await tester.tap(find.byTooltip('Remove phone').at(1));
    await tester.pumpAndSettle();

    expect(fields, findsNWidgets(2));
    final lines = payload(tester).split('\n');
    expect(lines.where((l) => l.startsWith('TEL')), [
      'TEL;TYPE=CELL:5550001',
      'TEL;TYPE=CELL:5550003',
    ]);
  });

  testWidgets('an address is boxed, and its kind is chosen from the box', (
    tester,
  ) async {
    await pumpVCard(tester, desktop);
    await add(tester, 'address');
    await type(tester, 'City', 'Anjou');
    expect(payload(tester), contains('ADR;TYPE=HOME:;;;Anjou;;;'));

    await tester.tap(find.byTooltip('Address type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    expect(payload(tester), contains('ADR;TYPE=WORK:;;;Anjou;;;'));

    await tester.tap(find.text('Remove address'));
    await tester.pumpAndSettle();
    expect(payload(tester), isNot(contains('ADR')));
  });

  testWidgets('a bad number in an entry holds the code back', (tester) async {
    await pumpVCard(tester, desktop);
    await add(tester, 'phone');
    await type(tester, 'Phone · Mobile', 'nope');
    expect(find.textContaining('Use digits'), findsOneWidget);
    expect(payload(tester), '—');
  });

  for (final (name, size) in [
    ('phone', const Size(390, 844)),
    ('desktop', desktop),
  ]) {
    testWidgets('many entries fit at $name width', (tester) async {
      await pumpVCard(tester, size);
      for (final what in ['phone', 'phone', 'phone', 'email', 'email']) {
        await add(tester, what);
      }
      await add(tester, 'address');
      await add(tester, 'address');
      expect(tester.takeException(), isNull);
      expect(find.text('Street Address'), findsNWidgets(2));
    });
  }
}
