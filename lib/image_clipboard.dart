/// Moving images to and from the clipboard, which Flutter cannot do on its own.
///
/// `Clipboard.setData` carries text and nothing else — the platform channel
/// behind it only knows about `text/plain` — so an image has to go around it.
/// On Linux that means handing the bytes to whichever clipboard helper the
/// session provides. The same goes for reading: the file covers copying a PNG
/// onto the clipboard and reading an image back off it, for Ctrl+V.
///
/// This is deliberately a Linux-only stopgap. iOS has an image clipboard in the
/// system API but Flutter does not expose it, so an iOS build will need either a
/// platform channel of its own or a package like `super_clipboard` — which works
/// everywhere but requires a Rust toolchain to build, a cost worth paying only
/// once there is a second platform to pay it for. Keeping the whole thing behind
/// [copyPngToClipboard] is what makes that swap cheap later.
library;

import 'dart:convert';
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

/// A clipboard helper that reads: the executable, the arguments that list the
/// types currently offered (one per line on stdout), and a function giving the
/// arguments that write one type's raw bytes to stdout.
typedef ClipboardReader = ({
  String executable,
  List<String> listArguments,
  List<String> Function(String type) readArguments,
});

final _wlPaste = (
  executable: 'wl-paste',
  listArguments: const ['--list-types'],
  readArguments: (String type) => ['--no-newline', '--type', type],
);

final _xclipPaste = (
  executable: 'xclip',
  listArguments: const ['-selection', 'clipboard', '-t', 'TARGETS', '-o'],
  readArguments: (String type) => ['-selection', 'clipboard', '-t', type, '-o'],
);

/// Reads an image from the clipboard. A typedef so the screen can be tested
/// without touching the real one.
typedef ClipboardImageReader = Future<Uint8List?> Function();

/// The helper to read the clipboard with, for a session described by
/// [environment]. The same choice as [chooseClipboardHelper]: `wl-paste` on
/// Wayland, then `xclip` on X11 including XWayland. Null when there is none.
ClipboardReader? chooseClipboardReader(
  Map<String, String> environment,
  bool Function(String executable) available,
) {
  final wayland = (environment['WAYLAND_DISPLAY'] ?? '').isNotEmpty;
  final x11 = (environment['DISPLAY'] ?? '').isNotEmpty;

  if (wayland && available(_wlPaste.executable)) return _wlPaste;
  if (x11 && available(_xclipPaste.executable)) return _xclipPaste;
  return null;
}

/// The reader for this session, or an [ImageClipboardException] naming what to
/// install when there is none.
ClipboardReader _requireReader() {
  if (!imageClipboardSupported) {
    throw const ImageClipboardException(
      'Reading an image from the clipboard is only supported on Linux so far.',
    );
  }

  final helper = chooseClipboardReader(Platform.environment, _onPath);
  if (helper == null) {
    throw const ImageClipboardException(
      'Reading an image from the clipboard needs wl-paste (from wl-clipboard) '
      'on Wayland or xclip on X11, and neither is installed.',
    );
  }
  return helper;
}

/// Runs [helper] with [arguments] and returns its stdout as raw bytes.
Future<ProcessResult> _runReader(
  ClipboardReader helper,
  List<String> arguments,
) async {
  try {
    return await Process.run(
      helper.executable,
      arguments,
      stdoutEncoding: null,
    );
  } on ProcessException catch (error) {
    throw ImageClipboardException(
      'Could not run ${helper.executable}: ${error.message}',
    );
  }
}

/// The types [helper] lists as offered. A non-zero exit means the clipboard is
/// empty, which is not an error, so it comes back as nothing offered.
Future<List<String>> _listTypes(ClipboardReader helper) async {
  final result = await _runReader(helper, helper.listArguments);
  if (result.exitCode != 0) return const [];

  // Type names are ASCII; latin1 cannot fail on whatever else a helper prints.
  final text = latin1.decode(result.stdout as List<int>);
  return [
    for (final line in const LineSplitter().convert(text))
      if (line.trim().isNotEmpty) line.trim(),
  ];
}

/// The MIME or X11 target types currently offered on the clipboard, in the
/// order the helper lists them. Empty when the clipboard is empty.
///
/// Throws [ImageClipboardException] naming what to install when there is no
/// helper for this session.
Future<List<String>> clipboardTypes() async => _listTypes(_requireReader());

/// The type to read when an image is wanted from [types]: `image/png` when
/// offered, else the first `image/` type, else null.
String? pickImageType(List<String> types) {
  if (types.contains('image/png')) return 'image/png';
  for (final type in types) {
    if (type.startsWith('image/')) return type;
  }
  return null;
}

/// Whether [types] offer an image and no text at all.
///
/// This decides whether Ctrl+V imports an image. It only does so when a text
/// field's own paste would have nothing to paste, so a text paste is never
/// taken over.
bool offersOnlyImage(List<String> types) {
  if (pickImageType(types) == null) return false;
  return !types.any(_isTextType);
}

const _textTargets = {'UTF8_STRING', 'STRING', 'TEXT', 'COMPOUND_TEXT'};

bool _isTextType(String type) =>
    type.startsWith('text/plain') || _textTargets.contains(type);

/// Reads the image on the clipboard as raw PNG, JPEG or whatever type it is
/// offered as, or null when the clipboard offers no image.
///
/// Throws [ImageClipboardException] when there is no helper or the read fails.
Future<Uint8List?> readImageFromClipboard() async {
  final helper = _requireReader();
  final type = pickImageType(await _listTypes(helper));
  if (type == null) return null;

  final result = await _runReader(helper, helper.readArguments(type));
  if (result.exitCode != 0) {
    throw ImageClipboardException(
      '${helper.executable} could not read $type from the clipboard '
      '(exit code ${result.exitCode}).',
    );
  }
  return Uint8List.fromList(result.stdout as List<int>);
}

/// Whether the clipboard holds an image and no text, as [offersOnlyImage] says.
///
/// Never throws: when there is no helper the answer is false, since Ctrl+V must
/// not surface an error for a feature the session cannot provide.
Future<bool> clipboardOffersOnlyImage() async {
  try {
    return offersOnlyImage(await clipboardTypes());
  } on ImageClipboardException {
    return false;
  }
}
