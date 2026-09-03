import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';

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
      validate: validateEmail,
    ),
    QrField(id: 'subject', label: 'Subject'),
    QrField(id: 'body', label: 'Body', type: QrFieldType.multiline),
  ];

  @override
  String buildQrString(Map<String, String> values) {
    // Uri.encodeComponent escapes everything a *query value* could need escaped,
    // which is right for subject and body but too much for the address. RFC 6068
    // allows @ and + literally in the addr-spec, and enough mail clients mishandle
    // %40 or %2B there to make it worth restoring them — plus-addressing is common.
    // The query parameters keep their full encoding, where + really can be read
    // as a space.
    final to = Uri.encodeComponent(
      values['to'] ?? '',
    ).replaceAll('%40', '@').replaceAll('%2B', '+');
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
