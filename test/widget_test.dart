import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:qrious/main.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/widgets/app_title.dart';
import 'package:qrious/widgets/version_badge.dart';

void main() {
  testWidgets('starts on the WiFi format with no QR code yet', (
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

  testWidgets('switching format rebuilds the form and clears values', (
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
    expect(find.byType(SingleChildScrollView), findsOneWidget);
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
