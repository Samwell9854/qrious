import 'package:file_selector/file_selector.dart';

/// Asks where to save a file, returning null when the user cancels.
///
/// A typedef rather than a direct call so the screen can be driven in tests
/// without a real GTK dialog: the dialog is the one part of saving that cannot
/// run headless, and everything after it — rendering and writing — is worth
/// testing for real.
typedef SaveLocationPicker = Future<String?> Function(String suggestedName);

/// The real save dialog.
Future<String?> pickPngSaveLocation(String suggestedName) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PNG image', extensions: ['png']),
    ],
  );
  return location?.path;
}
