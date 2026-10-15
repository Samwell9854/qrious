import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';

class TextFormat extends QrFormat {
  /// The one field's id, for the importer to put a payload under.
  static const fieldId = 'text';

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
      id: fieldId,
      label: 'Text',
      type: QrFieldType.multiline,
      required: true,
    ),
  ];

  @override
  String buildQrString(Map<String, String> values) => values['text'] ?? '';

  /// Claims nothing: plain text is what the importer falls back to for a payload
  /// no other format recognises, so it cannot also be a format that recognises.
  @override
  QrParsed? parse(String payload) => null;
}
