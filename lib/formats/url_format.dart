import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';

class UrlFormat extends QrFormat {
  @override
  String get id => 'url';

  @override
  String get name => 'URL / Website';

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'url',
      label: 'URL',
      required: true,
      hint: 'https://example.com',
      validate: validateUrl,
    ),
  ];

  @override
  String buildQrString(Map<String, String> values) => values['url'] ?? '';
}
