import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/models/qr_format.dart';
import 'package:qrious/qr_decoding.dart';
import 'package:qrious/screens/home_screen.dart';
import 'package:qrious/webcam.dart';
import 'package:qrious/widgets/camera_scanner.dart';

const url = 'https://example.com/a';
const otherUrl = 'https://example.org/b';

/// A frame is told apart by its width alone; the stub decoder maps it to payloads.
LumaFrame frameOf(int id) => (width: id, height: 1, luma: Uint8List(id));

class FakeWebcam implements Webcam {
  FakeWebcam({
    this.devices = const [(id: '/dev/video0', name: 'Front camera')],
    this.frames = const [],
    this.listError,
    this.startError,
  });

  final List<WebcamDevice> devices;

  /// Handed out in order; the last one repeats. Null entries mean "no frame yet".
  final List<LumaFrame?> frames;
  final WebcamUnavailableException? listError;
  final WebcamUnavailableException? startError;

  final errorController = StreamController<String>.broadcast();
  final started = <String>[];
  int stops = 0;
  int frameCalls = 0;

  @override
  Stream<String> get errors => errorController.stream;

  @override
  Future<List<WebcamDevice>> list() async {
    if (listError != null) throw listError!;
    return devices;
  }

  @override
  Future<WebcamStream> start(WebcamDevice device) async {
    if (startError != null) throw startError!;
    started.add(device.id);
    return (textureId: 7, width: 640, height: 480);
  }

  @override
  Future<LumaFrame?> frame() async {
    frameCalls++;
    if (frames.isEmpty) return null;
    return frames[(frameCalls - 1).clamp(0, frames.length - 1)];
  }

  @override
  Future<void> stop() async => stops++;
}

/// Frame 1 holds nothing, 2 a URL, 3 two codes.
Future<List<String>> decodeStub(LumaFrame frame) async => switch (frame.width) {
  2 => [url],
  3 => [url, otherUrl],
  _ => [],
};

Future<void> pumpHome(
  WidgetTester tester,
  FakeWebcam webcam, {
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(webcam: webcam, decodeFrame: decodeStub),
    ),
  );
}

Future<void> openScanner(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Read a QR code'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan with camera…'));
  // Not pumpAndSettle: the auto loop keeps timers running.
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> settleFor(WidgetTester tester, [int ms = 500]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> cancel(WidgetTester tester) async {
  await tester.tap(find.text('Cancel'));
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
}

String payload(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byType(SelectableText)).data!;

String selectedFormat(WidgetTester tester) => tester
    .widget<DropdownButtonFormField<QrFormat>>(
      find.byType(DropdownButtonFormField<QrFormat>),
    )
    .initialValue!
    .name;

void main() {
  setUp(() => CameraScanner.readAutomatically = true);

  testWidgets('auto mode reads the first frame with a code and imports it', (
    tester,
  ) async {
    final webcam = FakeWebcam(frames: [frameOf(2)]);
    await pumpHome(tester, webcam);
    await openScanner(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Scan with camera'), findsNothing);
    expect(find.text('Code read into URL / Website'), findsOneWidget);
    expect(selectedFormat(tester), 'URL / Website');
    expect(payload(tester), url);
    expect(webcam.started, ['/dev/video0']);
    expect(webcam.stops, greaterThan(0));
  });

  testWidgets('frames without a code, and missing frames, keep it open', (
    tester,
  ) async {
    final webcam = FakeWebcam(frames: [null, frameOf(1), null, frameOf(1)]);
    await pumpHome(tester, webcam);
    await openScanner(tester);
    await settleFor(tester);

    expect(find.text('Scan with camera'), findsOneWidget);
    expect(webcam.frameCalls, greaterThan(3));
    await cancel(tester);
    expect(find.text('Scan with camera'), findsNothing);
    expect(webcam.stops, greaterThan(0));
  });

  testWidgets('manual mode reads nothing until Capture', (tester) async {
    final webcam = FakeWebcam(frames: [frameOf(1)]);
    await pumpHome(tester, webcam);
    await openScanner(tester);
    await tester.tap(find.byType(Switch));
    await settleFor(tester);
    final calls = webcam.frameCalls;
    await settleFor(tester);
    expect(webcam.frameCalls, calls);

    await tester.tap(find.text('Capture'));
    await tester.pump();
    await tester.pump();
    expect(webcam.frameCalls, calls + 1);
    expect(find.text('No QR code in this frame.'), findsOneWidget);
    expect(find.text('Scan with camera'), findsOneWidget);
    await cancel(tester);
  });

  testWidgets('manual capture of a frame with a code closes and imports', (
    tester,
  ) async {
    final webcam = FakeWebcam(frames: [frameOf(2)]);
    CameraScanner.readAutomatically = false;
    await pumpHome(tester, webcam);
    await openScanner(tester);
    await settleFor(tester);
    expect(webcam.frameCalls, 0);

    await tester.tap(find.text('Capture'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Code read into URL / Website'), findsOneWidget);
    expect(payload(tester), url);
    expect(webcam.stops, greaterThan(0));
  });

  testWidgets('Enter captures in manual mode', (tester) async {
    final webcam = FakeWebcam(frames: [frameOf(2)]);
    CameraScanner.readAutomatically = false;
    await pumpHome(tester, webcam);
    await openScanner(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Code read into URL / Website'), findsOneWidget);
  });

  testWidgets('two codes in one frame go to the chooser', (tester) async {
    final webcam = FakeWebcam(frames: [frameOf(3)]);
    await pumpHome(tester, webcam);
    await openScanner(tester);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Several codes found'), findsOneWidget);
    await tester.tap(find.text(otherUrl));
    await tester.pumpAndSettle();
    expect(payload(tester), otherUrl);
  });

  testWidgets('a camera that cannot be listed shows why', (tester) async {
    final webcam = FakeWebcam(
      listError: const WebcamUnavailableException('Needs GStreamer.'),
    );
    await pumpHome(tester, webcam);
    await openScanner(tester);

    expect(find.text('Needs GStreamer.'), findsOneWidget);
    await cancel(tester);
    expect(find.text('Scan with camera'), findsNothing);
  });

  testWidgets('a busy camera shows why', (tester) async {
    final webcam = FakeWebcam(
      startError: const WebcamUnavailableException('The camera is busy.'),
    );
    await pumpHome(tester, webcam);
    await openScanner(tester);

    expect(find.text('The camera is busy.'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await cancel(tester);
  });

  testWidgets('an error mid-scan replaces the preview with its message', (
    tester,
  ) async {
    final webcam = FakeWebcam(frames: [frameOf(1)]);
    await pumpHome(tester, webcam);
    await openScanner(tester);
    expect(find.byType(Texture), findsOneWidget);

    webcam.errorController.add('The camera was unplugged.');
    await tester.pump();
    await settleFor(tester, 200);

    expect(find.text('The camera was unplugged.'), findsOneWidget);
    expect(find.byType(Texture), findsNothing);
    final calls = webcam.frameCalls;
    await settleFor(tester);
    expect(webcam.frameCalls, calls);
    await cancel(tester);
  });

  testWidgets('no camera at all says so', (tester) async {
    await pumpHome(tester, FakeWebcam(devices: const []));
    await openScanner(tester);

    expect(find.text('No camera found.'), findsOneWidget);
    await cancel(tester);
  });

  testWidgets('several cameras offer a switch that restarts capture', (
    tester,
  ) async {
    final webcam = FakeWebcam(
      devices: const [
        (id: '/dev/video0', name: 'Front camera'),
        (id: '/dev/video2', name: 'Back camera'),
      ],
      frames: [frameOf(1)],
    );
    await pumpHome(tester, webcam);
    await openScanner(tester);

    await tester.tap(find.byType(DropdownButton<WebcamDevice>));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.text('Back camera').last);
    await settleFor(tester);

    expect(webcam.started, ['/dev/video0', '/dev/video2']);
    await cancel(tester);
  });

  testWidgets('Escape closes and releases the camera', (tester) async {
    final webcam = FakeWebcam(frames: [frameOf(1)]);
    await pumpHome(tester, webcam);
    await openScanner(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.text('Scan with camera'), findsNothing);
    expect(webcam.stops, greaterThan(0));
  });

  testWidgets('Cancel imports nothing and stops the camera', (tester) async {
    final webcam = FakeWebcam(frames: [frameOf(1)]);
    await pumpHome(tester, webcam);
    await openScanner(tester);
    final stopsBefore = webcam.stops;
    await cancel(tester);

    expect(webcam.stops, greaterThan(stopsBefore));
    expect(find.textContaining('Code read into'), findsNothing);
    expect(find.text('No QR code found in this image.'), findsNothing);
  });

  for (final size in const [Size(360, 640), Size(1280, 800)]) {
    testWidgets('the scanner fits a ${size.width.toInt()} px window', (
      tester,
    ) async {
      final webcam = FakeWebcam(
        devices: const [
          (id: '/dev/video0', name: 'A rather long camera name for a phone'),
          (id: '/dev/video2', name: 'Back camera'),
        ],
        frames: [frameOf(1)],
      );
      await pumpHome(tester, webcam, size: size);
      await openScanner(tester);
      expect(find.byType(Texture), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(Switch));
      await settleFor(tester, 100);
      expect(find.text('Capture'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cancel(tester);
    });
  }
}
