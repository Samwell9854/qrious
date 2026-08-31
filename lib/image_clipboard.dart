/// Putting an image on the clipboard, which Flutter cannot do on its own.
///
/// `Clipboard.setData` carries text and nothing else — the platform channel
/// behind it only knows about `text/plain` — so an image has to go around it.
/// On Linux that means handing the bytes to whichever clipboard helper the
/// session provides.
///
/// This is deliberately a Linux-only stopgap. iOS has an image clipboard in the
/// system API but Flutter does not expose it, so an iOS build will need either a
/// platform channel of its own or a package like `super_clipboard` — which works
/// everywhere but requires a Rust toolchain to build, a cost worth paying only
/// once there is a second platform to pay it for. Keeping the whole thing behind
/// [copyPngToClipboard] is what makes that swap cheap later.
library;

import 'dart:io';
import 'dart:typed_data';

/// A clipboard helper: the executable to run and the arguments that make it read
/// a PNG from stdin.
typedef ClipboardHelper = ({String executable, List<String> arguments});

const _wlCopy = (executable: 'wl-copy', arguments: ['--type', 'image/png']);

const _xclip = (
  executable: 'xclip',
  arguments: ['-selection', 'clipboard', '-t', 'image/png', '-i'],
);

/// Copies a PNG to the clipboard. A typedef so the screen can be tested without
/// touching the real one.
typedef PngClipboardCopier = Future<void> Function(Uint8List bytes);

/// Thrown when the image cannot be put on the clipboard, carrying something the
/// user can act on rather than a stack trace.
class ImageClipboardException implements Exception {
  const ImageClipboardException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The helper to use for a session described by [environment], given [available]
/// to say which executables are on the PATH. Null when there is none.
///
/// Wayland first when `wl-copy` is actually installed, then X11 — including
/// XWayland, which is why a Wayland session without `wl-copy` still falls
/// through to `xclip` rather than giving up. `xsel` is not a candidate: it has no
/// notion of MIME types, so it cannot carry an image.
ClipboardHelper? chooseClipboardHelper(
  Map<String, String> environment,
  bool Function(String executable) available,
) {
  final wayland = (environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;
  final x11 = (environment['DISPLAY'] ?? '').isNotEmpty;

  if (wayland && available(_wlCopy.executable)) return _wlCopy;
  if (x11 && available(_xclip.executable)) return _xclip;
  return null;
}

/// Whether this platform has an image clipboard at all — see the note above.
bool get imageClipboardSupported => Platform.isLinux;

/// Whether [executable] can be found on the PATH.
bool _onPath(String executable) =>
    Process.runSync('which', [executable]).exitCode == 0;

/// Copies [bytes] to the system clipboard as a PNG.
///
/// Throws [ImageClipboardException] with a message naming what to install when
/// the session has no helper.
Future<void> copyPngToClipboard(Uint8List bytes) async {
  if (!imageClipboardSupported) {
    throw const ImageClipboardException(
      'Copying an image to the clipboard is only supported on Linux so far.',
    );
  }

  final helper = chooseClipboardHelper(Platform.environment, _onPath);
  if (helper == null) {
    throw const ImageClipboardException(
      'Copying an image needs wl-copy (from wl-clipboard) on Wayland or xclip '
      'on X11, and neither is installed.',
    );
  }

  final Process process;
  try {
    process = await Process.start(helper.executable, helper.arguments);
  } on ProcessException catch (error) {
    throw ImageClipboardException(
      'Could not run ${helper.executable}: ${error.message}',
    );
  }

  // Both helpers fork a child that holds the selection and then exit, so the
  // exit code arrives immediately rather than when the clipboard is replaced.
  process.stdin.add(bytes);
  await process.stdin.flush();
  await process.stdin.close();

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ImageClipboardException(
      '${helper.executable} failed with exit code $exitCode.',
    );
  }
}
