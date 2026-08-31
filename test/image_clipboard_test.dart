import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/image_clipboard.dart';
import 'package:qrious/qr_png.dart';

/// Stands in for "is this on the PATH", so the choice can be tested without
/// depending on what happens to be installed.
bool Function(String) installed(List<String> executables) =>
    (executable) => executables.contains(executable);

void main() {
  group('chooseClipboardHelper', () {
    test('prefers wl-copy in a Wayland session', () {
      final helper = chooseClipboardHelper({
        'WAYLAND_DISPLAY': 'wayland-0',
        'DISPLAY': ':0',
      }, installed(['wl-copy', 'xclip']));
      expect(helper?.executable, 'wl-copy');
    });

    test('falls back to xclip under XWayland when wl-copy is missing', () {
      // Exactly the common Wayland-session-with-XWayland case: WAYLAND_DISPLAY
      // is set but wl-clipboard is not installed, and xclip still works.
      final helper = chooseClipboardHelper({
        'WAYLAND_DISPLAY': 'wayland-0',
        'DISPLAY': ':0',
      }, installed(['xclip']));
      expect(helper?.executable, 'xclip');
    });

    test('uses xclip on plain X11', () {
      final helper = chooseClipboardHelper({
        'DISPLAY': ':0',
      }, installed(['xclip']));
      expect(helper?.executable, 'xclip');
    });

    test('asks for the image on stdin as a PNG', () {
      final helper = chooseClipboardHelper({
        'DISPLAY': ':0',
      }, installed(['xclip']));
      expect(helper?.arguments, contains('image/png'));
    });

    test('gives up when nothing usable is installed', () {
      expect(
        chooseClipboardHelper({
          'WAYLAND_DISPLAY': 'wayland-0',
          'DISPLAY': ':0',
        }, installed(['xsel'])),
        isNull,
      );
    });

    test('gives up when there is no display at all', () {
      // A headless session — CI, or an ssh shell.
      expect(
        chooseClipboardHelper({}, installed(['wl-copy', 'xclip'])),
        isNull,
      );
    });

    test('treats an empty display variable as unset', () {
      expect(
        chooseClipboardHelper({
          'WAYLAND_DISPLAY': '',
          'DISPLAY': '',
        }, installed(['wl-copy', 'xclip'])),
        isNull,
      );
    });
  });

  group('copyPngToClipboard', () {
    // Only meaningful with a real display and a real helper, so it is skipped
    // wherever there is not one rather than failing the suite in CI.
    final helper = chooseClipboardHelper(
      Platform.environment,
      (executable) => Process.runSync('which', [executable]).exitCode == 0,
    );

    testWidgets(
      'round-trips a PNG through the system clipboard',
      (tester) async {
        await tester.runAsync(() async {
          final bytes = await renderQrPng('https://example.com', size: 128);
          await copyPngToClipboard(bytes);

          // Read it back out with the same helper family.
          final read = Process.runSync('xclip', [
            '-selection',
            'clipboard',
            '-t',
            'image/png',
            '-o',
          ], stdoutEncoding: null);
          expect(read.exitCode, 0);
          expect((read.stdout as List<int>).length, bytes.length);
        });
      },
      skip: helper?.executable != 'xclip',
    );
  });
}
