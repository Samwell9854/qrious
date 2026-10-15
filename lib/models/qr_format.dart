import 'package:flutter/widgets.dart' show IconData;

import 'qr_field.dart';

/// What scanning a code does, which is how the format picker groups formats:
/// people think "I want them to join my Wi-Fi", not "I want a WIFI: payload".
/// The picker lists groups in this order and shows only those with a format.
enum QrFormatGroup {
  connect('Connect'),
  contact('Contact'),
  message('Call or message'),
  web('Web & maps'),
  text('Show text');

  const QrFormatGroup(this.label);

  final String label;
}

abstract class QrFormat {
  String get id;
  String get name;

  /// Shown beside [name] in the format picker.
  IconData get icon;

  /// The heading the format is listed under in the picker.
  QrFormatGroup get group;

  List<QrField> get fields;
  String buildQrString(Map<String, String> values);

  /// Reads a payload back into this format's values, for importing a scanned
  /// code. Null when [payload] is not this format; the fallback for those is
  /// plain text, so a format claims only what is unmistakably its own.
  ///
  /// A claim does not promise a faithful form: [QrParsed.unsupported] lists what
  /// the form cannot hold, and the importer also compares the rebuilt payload with
  /// [payload] before trusting it (see `lib/formats/import.dart`).
  QrParsed? parse(String payload);
}

/// A payload read back by [QrFormat.parse].
class QrParsed {
  const QrParsed(this.values, [this.unsupported = const []]);

  /// The values map the form would load, in the same shape `buildQrString` reads.
  final Map<String, String> values;

  /// The parts of the payload the form has nowhere to put, named the way the
  /// payload names them (`ORG`, `TITLE`, a Wi-Fi `R:` key), for the user to read.
  /// Empty when everything found a field.
  final List<String> unsupported;
}
