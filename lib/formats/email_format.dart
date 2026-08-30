import '../models/qr_field.dart';
import '../models/qr_format.dart';

class EmailFormat extends QrFormat {
  @override
  String get id => 'email';

  @override
  String get name => 'Email';

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'to',
      label: 'To',
      required: true,
      hint: 'recipient@example.com',
    ),
    QrField(id: 'subject', label: 'Subject'),
    QrField(id: 'body', label: 'Body', type: QrFieldType.multiline),
  ];

  @override
  String buildQrString(Map<String, String> values) {
    final to = Uri.encodeComponent(values['to'] ?? '');
    final params = <String>[];
    if ((values['subject'] ?? '').isNotEmpty) {
      params.add('subject=${Uri.encodeComponent(values['subject']!)}');
    }
    if ((values['body'] ?? '').isNotEmpty) {
      params.add('body=${Uri.encodeComponent(values['body']!)}');
    }
    return 'mailto:$to${params.isEmpty ? '' : '?${params.join('&')}'}';
  }
}
