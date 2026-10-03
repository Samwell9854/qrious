import 'package:file_selector/file_selector.dart';

import 'qr_export.dart';

/// Asks where to save a file, returning null when the user cancels.
///
/// A typedef rather than a direct call so the screen can be driven in tests
/// without a real GTK dialog: the dialog is the one part of saving that cannot
/// run headless, and everything after it — rendering and writing — is worth
/// testing for real.
typedef SaveLocationPicker =
    Future<String?> Function(String suggestedName, ExportFileType type);

/// The real save dialog, offering only [type]: the app asks which type before
/// opening it, because the Linux dialog cannot report which filter was picked.
Future<String?> pickSaveLocation(
  String suggestedName,
  ExportFileType type,
) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [
      XTypeGroup(label: type.label, extensions: [type.extension]),
    ],
  );
  return location?.path;
}
