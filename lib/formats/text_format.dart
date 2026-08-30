import '../models/qr_field.dart';
import '../models/qr_format.dart';

class TextFormat extends QrFormat {
  @override
  String get id => 'text';

  @override
  String get name => 'Plain Text';

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
