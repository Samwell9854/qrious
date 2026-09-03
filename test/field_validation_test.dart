import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:qrious/main.dart';
import 'package:qrious/models/qr_format.dart';

/// Opens the format picker and chooses [name].
Future<void> selectFormat(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<QrFormat>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String label, String value) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), value);
  await tester.pump();
}

void main() {
  testWidgets('an invalid URL shows an error and blocks the QR code', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QriousApp());
    await selectFormat(tester, 'URL / Website');

    await type(tester, 'URL', 'example.com');

    expect(find.text('Enter a full URL, including https://'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('fixing the value clears the error and generates the code', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QriousApp());
    await selectFormat(tester, 'URL / Website');

    await type(tester, 'URL', 'example.com');
    await type(tester, 'URL', 'https://example.com');

    expect(find.text('Enter a full URL, including https://'), findsNothing);
    expect(find.byType(QrImageView), findsOneWidget);
    // The URL is its own payload, so match the panel rather than the field.
    expect(
      find.widgetWithText(SelectableText, 'https://example.com'),
      findsOneWidget,
    );
  });

  testWidgets('an empty field is never flagged, only left unfilled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QriousApp());
    await selectFormat(tester, 'Email');

    // Nothing typed: required-ness holds the code back, no error is shown.
    expect(find.textContaining('Enter an address like'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);

    // Typing and then clearing it puts the form back to unflagged.
    await type(tester, 'To', 'nope');
    expect(find.textContaining('Enter an address like'), findsOneWidget);
    await type(tester, 'To', '');
    expect(find.textContaining('Enter an address like'), findsNothing);
  });

  testWidgets('an optional field with a bad value still blocks the code', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QriousApp());
    await selectFormat(tester, 'Contact (vCard)');

    await type(tester, 'First Name', 'Ada');
    expect(find.byType(QrImageView), findsOneWidget);

    // Email is optional here, but a wrong one would still be encoded.
    await type(tester, 'Email Address', 'not-an-address');
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('switching format drops the error with the values', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QriousApp());
    await selectFormat(tester, 'URL / Website');
    await type(tester, 'URL', 'example.com');
    expect(find.text('Enter a full URL, including https://'), findsOneWidget);

    await selectFormat(tester, 'Plain Text');

    expect(find.text('Enter a full URL, including https://'), findsNothing);
  });

  testWidgets('an error message does not overflow the phone layout', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const QriousApp());
    await selectFormat(tester, 'Contact (vCard)');

    // Every validated field wrong at once: the tallest the form can get.
    await type(tester, 'First Name', 'Ada');
    await type(tester, 'Phone Number', 'nope');
    await type(tester, 'Email Address', 'nope');
    await type(tester, 'Website', 'nope');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
