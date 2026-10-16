import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../qr_decoding.dart';
import '../webcam.dart';

/// Below this width the scanner takes the whole screen instead of floating over it.
/// The same breakpoint as the home screen's layouts.
const double _dialogBreakpoint = 700;

/// Shows the camera scanner and returns the payloads of the codes it read, or null
/// when the user cancelled.
///
/// [decode] reads the codes in a frame; the default runs the real decoder off the UI
/// thread. It is a seam so tests need not run zxing.
Future<List<String>?> showCameraScanner(
  BuildContext context, {
  required Webcam webcam,
  Future<List<String>> Function(LumaFrame frame)? decode,
}) {
  if (MediaQuery.sizeOf(context).width >= _dialogBreakpoint) {
    return showDialog<List<String>>(
      context: context,
      builder: (_) => CameraScanner(webcam: webcam, decode: decode),
    );
  }
  return Navigator.of(context).push(
    MaterialPageRoute<List<String>>(
      fullscreenDialog: true,
      builder: (_) =>
          CameraScanner(webcam: webcam, decode: decode, fullScreen: true),
    ),
  );
}

/// A live camera preview that reads QR codes held up to it, either continuously or
/// when the user presses Capture. Pops with the payloads it found.
class CameraScanner extends StatefulWidget {
  const CameraScanner({
    super.key,
    required this.webcam,
    this.decode,
    this.fullScreen = false,
  });

  final Webcam webcam;

  /// Reads the codes in a frame; the real decoder, off the UI thread, when null.
  final Future<List<String>> Function(LumaFrame frame)? decode;

  /// A page of its own rather than a dialog, for a narrow window.
  final bool fullScreen;

  /// Whether the scanner reads on its own. Kept here, not in the state, so a choice
  /// made once holds for the next scan of the session; a restart forgets it.
  static bool readAutomatically = true;

  @override
  State<CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<CameraScanner> {
  List<WebcamDevice> _devices = const [];
  WebcamDevice? _device;
  WebcamStream? _stream;

  /// Set once the scanner cannot go on: shown in place of the preview.
  String? _error;

  /// Whether the list of cameras came back empty.
  bool _noCamera = false;

  /// Counts camera starts, so a read begun on a camera we have since left is dropped.
  int _session = 0;

  /// Whether the auto loop is running, so there is never a second one: only one
  /// decode is ever in flight.
  bool _looping = false;

  /// Whether a manual capture is being decoded.
  bool _capturing = false;

  /// Shown after a capture that found nothing.
  bool _emptyCapture = false;

  bool _done = false;
  StreamSubscription<String>? _errors;
  final FocusNode _focus = FocusNode(debugLabel: 'CameraScanner');

  static const _idleWait = Duration(milliseconds: 100);

  /// The pause after a frame without a code. Not zero: a zero-length timer that
  /// re-arms itself never lets a fake clock advance in tests.
  static const _turn = Duration(milliseconds: 10);

  Future<List<String>> _decode(LumaFrame frame) =>
      (widget.decode ?? (f) => compute(decodeQrCodesFromLuma, f))(frame);

  @override
  void initState() {
    super.initState();
    _errors = widget.webcam.errors.listen(_fail);
    _open();
  }

  @override
  void dispose() {
    _done = true;
    _errors?.cancel();
    _focus.dispose();
    _stopCamera();
    super.dispose();
  }

  /// Releases the camera. The runner treats a stop with nothing running as a no-op,
  /// so calling it on every exit path is safe.
  void _stopCamera() {
    unawaited(widget.webcam.stop().catchError((Object _) {}));
  }

  Future<void> _open() async {
    try {
      final devices = await widget.webcam.list();
      if (!mounted) return;
      if (devices.isEmpty) {
        setState(() => _noCamera = true);
        return;
      }
      _devices = devices;
      await _startDevice(devices.first);
    } on WebcamUnavailableException catch (error) {
      _fail(error.message);
    }
  }

  Future<void> _startDevice(WebcamDevice device) async {
    final session = ++_session;
    setState(() {
      _device = device;
      _stream = null;
    });
    try {
      await widget.webcam.stop();
      final stream = await widget.webcam.start(device);
      if (!mounted || session != _session) return;
      setState(() => _stream = stream);
      _maybeLoop();
    } on WebcamUnavailableException catch (error) {
      if (session == _session) _fail(error.message);
    }
  }

  void _switchTo(WebcamDevice? device) {
    if (device == null || device == _device) return;
    _startDevice(device);
  }

  /// Stops reading and shows [message] where the preview was.
  void _fail(String message) {
    if (!mounted || _done) return;
    _session++;
    setState(() {
      _error = message;
      _stream = null;
    });
    _stopCamera();
  }

  void _finish(List<String>? payloads) {
    if (_done) return;
    _done = true;
    _stopCamera();
    Navigator.of(context).pop(payloads);
  }

  bool get _live => mounted && !_done && _stream != null && _error == null;

  void _maybeLoop() {
    if (_looping || !CameraScanner.readAutomatically || !_live) return;
    _loop();
  }

  /// Pulls a frame, decodes it, and repeats until a code turns up. The next frame is
  /// asked for only once the decode is done, so frames never queue behind it.
  Future<void> _loop() async {
    _looping = true;
    final session = _session;
    try {
      while (_live && CameraScanner.readAutomatically && session == _session) {
        final frame = await widget.webcam.frame();
        if (!_live || session != _session) break;
        if (frame == null) {
          await Future<void>.delayed(_idleWait);
          continue;
        }
        final payloads = await _decode(frame);
        if (!_live || session != _session) break;
        if (payloads.isNotEmpty) {
          _finish(payloads);
          return;
        }
        // Gives the UI a turn even when frames and decodes come back at once.
        await Future<void>.delayed(_turn);
      }
    } on WebcamUnavailableException catch (error) {
      if (session == _session) _fail(error.message);
    } catch (error) {
      if (session == _session) _fail('Could not read the camera image: $error');
    } finally {
      _looping = false;
      // Switched back on, or the camera changed, while this loop was winding down.
      if (!_done) _maybeLoop();
    }
  }

  Future<void> _capture() async {
    if (_capturing || !_live || CameraScanner.readAutomatically) return;
    final session = _session;
    setState(() {
      _capturing = true;
      _emptyCapture = false;
    });
    try {
      final frame = await widget.webcam.frame();
      final payloads = frame == null ? const <String>[] : await _decode(frame);
      if (!_live || session != _session) return;
      if (payloads.isNotEmpty) {
        _finish(payloads);
      } else {
        setState(() => _emptyCapture = true);
      }
    } on WebcamUnavailableException catch (error) {
      if (session == _session) _fail(error.message);
    } catch (error) {
      if (session == _session) _fail('Could not read the camera image: $error');
    } finally {
      if (mounted && !_done) setState(() => _capturing = false);
    }
  }

  /// Space and Enter capture only while no control inside the scanner has the focus:
  /// on a focused Cancel button or switch they keep their own meaning.
  void _captureFromKey() {
    if (_focus.hasPrimaryFocus) _capture();
  }

  void _setAutomatic(bool value) {
    setState(() {
      CameraScanner.readAutomatically = value;
      _emptyCapture = false;
    });
    if (value) _maybeLoop();
  }

  @override
  Widget build(BuildContext context) {
    final body = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null),
        const SingleActivator(LogicalKeyboardKey.space): _captureFromKey,
        const SingleActivator(LogicalKeyboardKey.enter): _captureFromKey,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _buildContent(context),
        ),
      ),
    );
    if (widget.fullScreen) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan with camera')),
        body: SafeArea(child: body),
      );
    }
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: body,
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final automatic = CameraScanner.readAutomatically;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.fullScreen) ...[
          Text('Scan with camera', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
        ],
        if (_devices.length > 1 && _error == null) ...[
          DropdownButton<WebcamDevice>(
            value: _device,
            isExpanded: true,
            items: [
              for (final device in _devices)
                DropdownMenuItem(
                  value: device,
                  child: Text(device.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _switchTo,
          ),
          const SizedBox(height: 8),
        ],
        _buildPreview(theme),
        if (_error == null && !_noCamera) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Read automatically'),
            value: automatic,
            onChanged: _setAutomatic,
          ),
          if (_emptyCapture && !automatic)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'No QR code in this frame.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          children: [
            TextButton(
              onPressed: () => _finish(null),
              child: const Text('Cancel'),
            ),
            if (!automatic && _error == null && !_noCamera)
              FilledButton(
                onPressed: _capturing || _stream == null ? null : _capture,
                child: const Text('Capture'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview(ThemeData theme) {
    Widget message(String text, {bool error = false}) => Container(
      constraints: const BoxConstraints(minHeight: 160),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: error ? TextStyle(color: theme.colorScheme.error) : null,
      ),
    );

    if (_error case final error?) return message(error, error: true);
    if (_noCamera) return message('No camera found.');
    final stream = _stream;
    if (stream == null) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: stream.width / stream.height,
        // Mirrored because people hold a code up to a front-facing camera and expect
        // to see themselves as in a mirror. Only the preview is flipped: the frames
        // handed to the decoder are not, so a code still reads the right way round.
        child: Transform.flip(
          flipX: true,
          child: Texture(textureId: stream.textureId),
        ),
      ),
    );
  }
}
