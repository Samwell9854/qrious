import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/screens/home_screen.dart';

Future<void> pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 800);
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

Future<void> type(WidgetTester tester, String label, String value) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), value);
  await tester.pump();
}

Future<void> choose(WidgetTester tester, String current, String option) async {
  await tester.tap(find.text(current));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

String payload(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byType(SelectableText)).data!;

Finder get clearButton => find.widgetWithText(TextButton, 'Clear');

const wifi = 'WIFI:T:WEP;S:MyNetwork;P:secret;H:true;;';

/// A Wi-Fi form with every kind of field changed from its default.
Future<void> fillWifi(WidgetTester tester) async {
  await type(tester, 'Network Name (SSID)', 'MyNetwork');
  await choose(tester, 'WPA/WPA2', 'WEP');
  await type(tester, 'Password', 'secret');
  await tester.tap(find.text('Hidden Network'));
  await tester.pump();
  expect(payload(tester), wifi);
}

void main() {
  testWidgets('switching away and back restores what was typed', (
    tester,
  ) async {
    await pumpHome(tester);
    await fillWifi(tester);

    await pickFormat(tester, 'Phone Number');
    expect(find.text('Network Name (SSID)'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);

    await pickFormat(tester, 'Wi-Fi');
    expect(payload(tester), wifi);
    expect(find.text('WEP'), findsOneWidget);
  });

  testWidgets('each format keeps its own values', (tester) async {
    await pumpHome(tester);
    await type(tester, 'Network Name (SSID)', 'MyNetwork');
    await pickFormat(tester, 'Phone Number');
    await type(tester, 'Phone Number', '5550000');
    await pickFormat(tester, 'Wi-Fi');
    await pickFormat(tester, 'Phone Number');
    expect(payload(tester), 'tel:5550000');
  });

  testWidgets('vCard entries come back with their kinds', (tester) async {
    await pumpHome(tester);
    await pickFormat(tester, 'Contact (vCard)');
    await type(tester, 'First Name', 'Ada');
    for (final _ in [1, 2]) {
      await tester.tap(find.text('Add phone'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Phone type').at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    await type(tester, 'Phone · Mobile', '5550001');
    await type(tester, 'Phone · Work', '5550002');
    final before = payload(tester);

    await pickFormat(tester, 'Wi-Fi');
    await pickFormat(tester, 'Contact (vCard)');
    expect(payload(tester), before);
    expect(find.widgetWithText(TextFormField, 'Phone · Work'), findsOneWidget);
  });

  testWidgets('Clear is off until something is filled in', (tester) async {
    await pumpHome(tester);
    TextButton button() => tester.widget<TextButton>(clearButton);
    expect(button().onPressed, isNull);
    await type(tester, 'Network Name (SSID)', 'x');
    expect(button().onPressed, isNotNull);
  });

  testWidgets('Clear empties every kind of field, and Undo restores them', (
    tester,
  ) async {
    await pumpHome(tester);
    await fillWifi(tester);

    await tester.tap(clearButton);
    await tester.pumpAndSettle();
    expect(payload(tester), '—');
    // The dropdown shows its default again, not the stale choice.
    expect(find.text('WPA/WPA2'), findsOneWidget);
    expect(find.text('WEP'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(payload(tester), wifi);
    expect(find.text('WEP'), findsOneWidget);
  });

  testWidgets('Clear leaves the other formats alone', (tester) async {
    await pumpHome(tester);
    await type(tester, 'Network Name (SSID)', 'MyNetwork');
    await pickFormat(tester, 'Phone Number');
    await type(tester, 'Phone Number', '5550000');
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    await pickFormat(tester, 'Wi-Fi');
    expect(payload(tester), contains('S:MyNetwork;'));
  });

  testWidgets('the Form cleared message goes away on its own', (tester) async {
    await pumpHome(tester);
    await type(tester, 'Network Name (SSID)', 'MyNetwork');
    await tester.tap(clearButton);
    await tester.pumpAndSettle();
    expect(find.text('Form cleared'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Form cleared'), findsNothing);
  });

  testWidgets('Ctrl+Z undoes a Clear, even after the message is gone', (
    tester,
  ) async {
    await pumpHome(tester);
    await fillWifi(tester);
    // As with a mouse: the field that had focus goes away with the Clear, and
    // a click on a button or on empty space focuses nothing.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.tap(clearButton);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(payload(tester), wifi);
  });

  testWidgets('Undo does not overwrite what was typed after a Clear', (
    tester,
  ) async {
    await pumpHome(tester);
    await fillWifi(tester);
    await tester.tap(clearButton);
    await tester.pumpAndSettle();
    await type(tester, 'Network Name (SSID)', 'Other');

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(payload(tester), contains('S:Other;'));
  });
}
