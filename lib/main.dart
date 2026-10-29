import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'settings.dart';

Future<void> main() async {
  // Read before the first frame, so the screen opens on the saved defaults rather than
  // switching to them a moment later.
  final settings = await loadSettings();
  runApp(QriousApp(settings: settings));
}

class QriousApp extends StatelessWidget {
  const QriousApp({super.key, this.settings = const Settings()});

  final Settings settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Qrious',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(settings: settings),
    );
  }
}
