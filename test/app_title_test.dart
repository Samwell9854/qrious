import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/version.dart';
import 'package:qrious/widgets/app_title.dart';
import 'package:qrious/widgets/version_badge.dart';

Future<void> pumpTitle(WidgetTester tester, Future<AppVersion> version) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: AppTitle(versionFuture: version),
          centerTitle: false,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the app name with the version beside it', (tester) async {
    await pumpTitle(
      tester,
      Future.value(
        const AppVersion(version: '2026.8.0-alpha.1', buildNumber: '1'),
      ),
    );

    expect(find.text('Qrious'), findsOneWidget);
    expect(find.text('2026.8.0-alpha.1'), findsOneWidget);
  });

  testWidgets('fits at phone width, even with the longest plausible version', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpTitle(
      tester,
      Future.value(
        // Longer than anything the calendar scheme can actually produce.
        const AppVersion(version: '2026.12.10-preview.99', buildNumber: '999'),
      ),
    );

    // A RenderFlex overflow fails here rather than only printing to the console.
    expect(tester.takeException(), isNull);
    expect(find.byType(VersionBadge), findsOneWidget);
  });

  testWidgets('keeps the app name when the version cannot be read', (
    tester,
  ) async {
    // Delayed rather than Future.error: the builder must be listening before the
    // error lands, or the test zone reports it as unhandled instead.
    await pumpTitle(
      tester,
      Future<AppVersion>.delayed(
        Duration.zero,
        () => throw StateError('no bundle'),
      ),
    );

    expect(find.text('Qrious'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
