import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/version.dart';
import 'package:qrious/widgets/version_badge.dart';

Future<void> pumpBadge(WidgetTester tester, Future<AppVersion> future) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: VersionBadge(future: future)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the version once the bundle is read', (tester) async {
    await pumpBadge(
      tester,
      Future.value(
        const AppVersion(version: '2026.8.0-alpha.1', buildNumber: '1'),
      ),
    );

    expect(find.text('2026.8.0-alpha.1'), findsOneWidget);
  });

  testWidgets('styles a prerelease apart from a stable release', (
    tester,
  ) async {
    Color backgroundOf(WidgetTester tester) =>
        (tester.widget<Container>(find.byType(Container)).decoration!
                as BoxDecoration)
            .color!;

    await pumpBadge(
      tester,
      Future.value(
        const AppVersion(version: '2026.8.0-alpha.1', buildNumber: '1'),
      ),
    );
    final prerelease = backgroundOf(tester);

    await pumpBadge(
      tester,
      Future.value(const AppVersion(version: '2026.8.0', buildNumber: '2')),
    );
    final stable = backgroundOf(tester);

    await pumpBadge(
      tester,
      Future.value(const AppVersion(version: 'garbage', buildNumber: '3')),
    );
    final broken = backgroundOf(tester);

    expect(prerelease, isNot(stable));
    expect(broken, isNot(stable));
    expect(broken, isNot(prerelease));
  });

  testWidgets('renders nothing rather than throwing when the read fails', (
    tester,
  ) async {
    // Delayed rather than Future.error: the builder must be listening before the
    // error lands, or the test zone reports it as unhandled instead.
    await pumpBadge(
      tester,
      Future<AppVersion>.delayed(
        Duration.zero,
        () => throw StateError('no bundle'),
      ),
    );

    expect(find.byType(Container), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
