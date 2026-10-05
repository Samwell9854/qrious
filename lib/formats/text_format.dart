import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';

class TextFormat extends QrFormat {
  @override
  String get id => 'text';

  @override
  String get name => 'Plain Text';

  @override
  QrFormatGroup get group => QrFormatGroup.text;

  @override
  IconData get icon => Icons.notes;

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'text',
      label: 'Text',
      type: QrFieldType.multiline,
      required: true,
    ),
  ];

  @override
  String buildQrString(Map<String, String> values) => values['text'] ?? '';
}
