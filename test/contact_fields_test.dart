import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/screens/home_screen.dart';
import 'package:qrious/settings.dart';
import 'package:qrious/widgets/iso_date_picker.dart';
import 'package:qrious/widgets/qr_symbol.dart';

Future<void> pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(settings: const Settings(), saveSettings: (_) async {}),
    ),
  );
}

Future<void> chooseFormat(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextFormField, label).first;
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

String payload(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byType(SelectableText)).data!;

/// The field's text as the formatter leaves it after [typed] is entered.
String formatted(String typed) => const IsoDateInputFormatter()
    .formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: typed.length),
      ),
    )
    .text;

void main() {
  group('a required field', () {
    testWidgets('shows its * before it is focused or filled', (tester) async {
      await pumpHome(tester);
      await chooseFormat(tester, 'URL / Website');
      final url = find.widgetWithText(TextFormField, 'URL');
      expect(
        find.descendant(of: url, matching: find.text(' *')),
        findsOneWidget,
      );
    });

    testWidgets('an optional one shows none', (tester) async {
      await pumpHome(tester);
      await chooseFormat(tester, 'Contact (vCard)');
      expect(find.text(' *'), findsNothing);
    });
  });

  for (final (name, prefix, birthday) in [
    ('Contact (vCard)', 'BEGIN:VCARD', '\nBDAY:1815-12-10\n'),
    ('Contact (MeCard, compact)', 'MECARD:', ';BDAY:18151210;'),
  ]) {
    group(name, () {
      testWidgets('an empty form makes no code', (tester) async {
        await pumpHome(tester);
        await chooseFormat(tester, name);
        expect(find.byType(QrSymbol), findsNothing);
        expect(
          find.text('Fill in any field\nto generate a QR code'),
          findsOneWidget,
        );
      });

      testWidgets('a last name alone makes a code', (tester) async {
        await pumpHome(tester);
        await chooseFormat(tester, name);
        await type(tester, 'Last Name', 'Lovelace');
        expect(find.byType(QrSymbol), findsOneWidget);
        expect(payload(tester), startsWith(prefix));
      });

      testWidgets('an entry added and left blank makes no code', (
        tester,
      ) async {
        await pumpHome(tester);
        await chooseFormat(tester, name);
        // vCard adds a phone entry; MeCard has a single phone field, left empty.
        final add = find.text('Add phone');
        if (add.evaluate().isNotEmpty) {
          await tester.ensureVisible(add);
          await tester.tap(add);
          await tester.pump();
        }
        expect(find.byType(QrSymbol), findsNothing);
      });

      testWidgets('a birthday is typed as digits alone', (tester) async {
        await pumpHome(tester);
        await chooseFormat(tester, name);
        await type(tester, 'First Name', 'Ada');
        await type(tester, 'Birthday', '18151210');
        expect(find.text('1815-12-10'), findsOneWidget);
        expect(payload(tester), contains(birthday));
      });
    });
  }

  group('IsoDateInputFormatter', () {
    test('puts the dashes in as the digits arrive', () {
      expect(formatted('1'), '1');
      expect(formatted('1985'), '1985');
      expect(formatted('19850'), '1985-0');
      expect(formatted('198504'), '1985-04');
      expect(formatted('1985041'), '1985-04-1');
      expect(formatted('19850412'), '1985-04-12');
    });

    test('takes dashes typed by hand, and other separators pasted', () {
      expect(formatted('1985-04-12'), '1985-04-12');
      expect(formatted('1985/04/12'), '1985-04-12');
      expect(formatted('1985.04.12'), '1985-04-12');
    });

    test('stops at the eight digits a date has', () {
      expect(formatted('198504123'), '1985-04-12');
    });

    test('lets a backspace after the year stand', () {
      final after = const IsoDateInputFormatter().formatEditUpdate(
        const TextEditingValue(
          text: '1985-0',
          selection: TextSelection.collapsed(offset: 6),
        ),
        const TextEditingValue(
          text: '1985-',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(after.text, '1985');
      expect(after.selection.baseOffset, 4);
    });

    test('keeps the cursor after the same digit on an edit in the middle', () {
      // A digit typed into the month of 1985-04-12, after the 0.
      final after = const IsoDateInputFormatter().formatEditUpdate(
        const TextEditingValue(
          text: '1985-04-12',
          selection: TextSelection.collapsed(offset: 6),
        ),
        const TextEditingValue(
          text: '1985-094-12',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      expect(after.text, '1985-09-41');
      expect(after.selection.baseOffset, 7);
    });
  });

  testWidgets(
    'a MeCard name the iPhone cannot read is cautioned, not refused',
    (tester) async {
      await pumpHome(tester);
      await chooseFormat(tester, 'Contact (MeCard, compact)');
      await type(tester, 'Last Name', 'Smith');
      await type(tester, 'First Name', 'John Paul George');
      expect(find.textContaining('iPhone cannot read'), findsOneWidget);
      expect(find.byType(QrSymbol), findsOneWidget);

      await type(tester, 'First Name', 'John Paul');
      expect(find.textContaining('iPhone cannot read'), findsNothing);
    },
  );
}
