/// The webcam, for scanning a code held up to it.
///
/// Flutter has no camera on Linux, so the runner captures with GStreamer
/// (`linux/runner/camera.cc`) and answers on the `qrious/camera` channel:
///
/// | Method | Argument | Answer |
/// | --- | --- | --- |
/// | `list` | – | `[{id, name}]`, one per V4L2 capture device; `id` is its path |
/// | `start` | `id` | `{textureId, width, height}` once the first frame has arrived |
/// | `frame` | – | `{width, height, luma}` of the latest frame, or null before one |
/// | `stop` | – | nothing; stops capturing and releases the device and the texture |
///
/// Error codes: `missing-plugin` (GStreamer cannot capture from a webcam: the
/// `v4l2src` element, in gst-plugins-good, is not installed), `busy` (another
/// program holds the device), `failed` (anything else, with a message). While
/// streaming, the runner calls `error` on the channel with a message when capture
/// stops by itself, as when the camera is unplugged.
///
/// Frames are pulled, not pushed: the scanner asks for one when the decoder is free,
/// so frames never queue up behind a slow decode. `luma` is one byte per pixel, rows
/// packed, unmirrored; the preview texture shows the same frame in colour.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'qr_decoding.dart';

/// A camera the system offers.
typedef WebcamDevice = ({String id, String name});

/// A started camera: the texture its preview is drawn into, and the frame size.
typedef WebcamStream = ({int textureId, int width, int height});

/// Why the camera cannot be used, in words for the user.
class WebcamUnavailableException implements Exception {
  const WebcamUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'WebcamUnavailableException: $message';
}

/// The camera, behind an interface so the screen can be tested with a stub.
abstract interface class Webcam {
  /// The cameras there are, possibly none. Throws [WebcamUnavailableException]
  /// when the platform cannot capture at all.
  Future<List<WebcamDevice>> list();

  /// Starts [device] and completes once it delivers frames. Only one camera runs
  /// at a time; starting another stops the first. Throws
  /// [WebcamUnavailableException].
  Future<WebcamStream> start(WebcamDevice device);

  /// The latest frame, or null when none has arrived yet.
  Future<LumaFrame?> frame();

  /// Stops capturing. Safe to call when nothing runs.
  Future<void> stop();

  /// A message each time capture stops by itself while running.
  Stream<String> get errors;
}

/// The Linux runner's camera.
class RunnerWebcam implements Webcam {
  RunnerWebcam() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'error') {
        _errors.add(call.arguments as String? ?? 'The camera stopped.');
      }
    });
  }

  static const _channel = MethodChannel('qrious/camera');

  final _errors = StreamController<String>.broadcast();

  @override
  Stream<String> get errors => _errors.stream;

  @override
  Future<List<WebcamDevice>> list() => _guard(() async {
    final devices = await _channel.invokeListMethod<Map>('list') ?? const [];
    return [
      for (final d in devices)
        (id: d['id'] as String, name: d['name'] as String),
    ];
  });

  @override
  Future<WebcamStream> start(WebcamDevice device) => _guard(() async {
    final answer = await _channel.invokeMapMethod<String, Object?>(
      'start',
      device.id,
    );
    if (answer == null) {
      throw const WebcamUnavailableException('The camera did not start.');
    }
    return (
      textureId: answer['textureId'] as int,
      width: answer['width'] as int,
      height: answer['height'] as int,
    );
  });

  @override
  Future<LumaFrame?> frame() => _guard(() async {
    final answer = await _channel.invokeMapMethod<String, Object?>('frame');
    if (answer == null) return null;
    return (
      width: answer['width'] as int,
      height: answer['height'] as int,
      luma: answer['luma'] as Uint8List,
    );
  });

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Nothing to release.
    } on MissingPluginException {
      // No runner camera on this platform.
    }
  }

  /// Turns the channel's failures into the words the scanner shows.
  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on MissingPluginException {
      throw const WebcamUnavailableException(
        'Scanning with a camera is only supported on Linux so far.',
      );
    } on PlatformException catch (error) {
      throw WebcamUnavailableException(switch (error.code) {
        'missing-plugin' =>
          "Scanning with the camera needs GStreamer's good plugins "
              '(gst-plugins-good on Arch, gstreamer1.0-plugins-good on Debian '
              'and Ubuntu).',
        'busy' => 'The camera is in use by another program.',
        _ => 'The camera could not be used: ${error.message}',
      });
    }
  }
}
