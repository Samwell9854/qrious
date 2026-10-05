import 'package:flutter/widgets.dart' show IconData;

import 'qr_field.dart';

abstract class QrFormat {
  String get id;
  String get name;

  /// Shown beside [name] in the format picker.
  IconData get icon;
  List<QrField> get fields;
  String buildQrString(Map<String, String> values);
}
