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
}
