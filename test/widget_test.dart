import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:qrious/formats/registry.dart';
import 'package:qrious/main.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/widgets/app_title.dart';
import 'package:qrious/widgets/version_badge.dart';

void main() {
  testWidgets('starts on the Wi-Fi format with no QR code yet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QriousApp());

    expect(find.text('Network Name (SSID)'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    expect(
      find.text('Fill in the required fields\nto generate a QR code'),
      findsOneWidget,
    );
  });

  testWidgets('keeps the version badge out of the debug ribbon corner', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QriousApp());

    // Flutter paints the debug ribbon across the top right corner, so the badge
    // belongs in the app bar's title, not in its actions.
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.actions ?? const <Widget>[], isEmpty);
    expect(
      find.descendant(
        of: find.byType(AppTitle),
        matching: find.byType(VersionBadge),
      ),
      findsOneWidget,
    );
  });

  testWidgets('filling the required field renders a QR code and its payload', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QriousApp());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Network Name (SSID)'),
      'MyNetwork',
    );
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('WIFI:T:WPA;S:MyNetwork;P:;H:false;;'), findsOneWidget);
  });

  testWidgets('the format picker lists formats under group headings', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const QriousApp());
    await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
    await tester.pumpAndSettle();

    double top(String text) => tester.getTopLeft(find.text(text).last).dy;
    var previous = double.negativeInfinity;
    for (final (group, formats) in qrFormatsByGroup) {
      final heading = top(group.label.toUpperCase());
      expect(heading, greaterThan(previous), reason: group.label);
      for (final format in formats) {
        final row = find.ancestor(
          of: find.text(format.name).last,
          matching: find.byType(Row),
        );
        expect(
          find.descendant(of: row.first, matching: find.byIcon(format.icon)),
          findsOneWidget,
          reason: format.id,
        );
        expect(top(format.name), greaterThan(heading), reason: format.id);
        previous = top(format.name);
      }
    }
  });

  testWidgets('a group heading cannot be chosen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const QriousApp());
    await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
    await tester.pumpAndSettle();

    await tester.tap(find.text('CONTACT'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // Still on Wi-Fi, whether or not the menu stayed open.
    expect(find.text('Network Name (SSID)'), findsOneWidget);
  });

  for (final size in [const Size(1280, 800), const Size(1000, 700)]) {
    testWidgets('Tab reaches the last field before the panel at $size', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const QriousApp());

      // MeCard: enough fields that some sit level with the panel's dropdowns,
      // which is where ordering by position alone zigzags between the sides.
      await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contact (MeCard, compact)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextFormField, 'First Name'));
      await tester.pump();

      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final focused = FocusManager.instance.primaryFocus!.context!;
        final label = focused
            .findAncestorWidgetOfExactType<TextField>()
            ?.decoration
            ?.labelText;
        if (label == 'Country') return;
        final box = focused.findRenderObject()! as RenderBox;
        expect(
          box.localToGlobal(Offset.zero).dx,
          lessThan(24 + 380),
          reason: 'Tab reached the panel before the last field',
        );
      }
      fail('Tab never reached the last field');
    });
  }

  testWidgets('the first field\'s floating label is not clipped', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const QriousApp());

    final field = find.widgetWithText(TextFormField, 'Network Name (SSID)');
    await tester.enterText(field, 'MyNetwork');
    await tester.pumpAndSettle();

    // The fields scroll inside their own viewport, which clips at its top edge.
    final viewport = tester.getRect(
      find.ancestor(of: field, matching: find.byType(Scrollable)).first,
    );
    final label = tester.getRect(
      find.descendant(of: field, matching: find.text('Network Name (SSID)')),
    );
    expect(label.top, greaterThanOrEqualTo(viewport.top));
  });

  testWidgets('switching format rebuilds the form for the new format', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QriousApp());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Network Name (SSID)'),
      'MyNetwork',
    );
    await tester.pump();

    await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Phone Number').last);
    await tester.pumpAndSettle();

    expect(find.text('Network Name (SSID)'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('stacks into one scrolling column on a phone-sized screen', (
    WidgetTester tester,
  ) async {
    // iPhone-ish logical size.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const QriousApp());

    // Both panes are present in the same scrollable, and nothing overflows.
    expect(find.text('Network Name (SSID)'), findsOneWidget);
    expect(find.text('QR Code Data'), findsOneWidget);
    Finder scrollerOf(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byType(SingleChildScrollView),
    );
    expect(scrollerOf('QR Code Data'), findsOneWidget);
    expect(
      tester.widget(scrollerOf('QR Code Data')),
      same(tester.widget(scrollerOf('Network Name (SSID)').last)),
    );
    expect(find.byType(Row).evaluate().isNotEmpty, isTrue);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Network Name (SSID)'),
      'MyNetwork',
    );
    await tester.pump();

    expect(find.byType(QrImageView), findsOneWidget);
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.size, lessThanOrEqualTo(390 - 32 - 32));
  });
}
