import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Asks the user for an image to read a QR code from, returning its bytes, or null
/// when they cancel.
///
/// A typedef for the same reason as SaveLocationPicker (lib/save_location.dart): the dialog is the one part
/// of opening that cannot run headless.
typedef ImageFilePicker = Future<Uint8List?> Function();

/// The real open dialog, offering the image types the decoder can read.
Future<Uint8List?> pickImageFile() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images',
        extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg'],
      ),
    ],
  );
  return file?.readAsBytes();
}
