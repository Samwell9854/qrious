import '../models/qr_field.dart';
import '../models/qr_format.dart';

class VCardFormat extends QrFormat {
  @override
  String get id => 'vcard';

  @override
  String get name => 'Contact (vCard)';

  @override
  List<QrField> get fields => const [
    QrField(id: 'first_name', label: 'First Name', required: true),
    QrField(id: 'last_name', label: 'Last Name'),
    QrField(id: 'org', label: 'Organization'),
    QrField(id: 'title', label: 'Job Title'),
    QrField(id: 'phone', label: 'Phone Number', hint: '+1 555 000 0000'),
    QrField(id: 'email', label: 'Email Address'),
    QrField(id: 'url', label: 'Website'),
    QrField(id: 'address', label: 'Address', type: QrFieldType.multiline),
  ];

  @override
  String buildQrString(Map<String, String> values) {
    final firstName = values['first_name'] ?? '';
    final lastName = values['last_name'] ?? '';
    final lines = [
      'BEGIN:VCARD',
      'VERSION:3.0',
      'N:$lastName;$firstName;;;',
      'FN:${[firstName, lastName].where((s) => s.isNotEmpty).join(' ')}',
    ];
    if ((values['org'] ?? '').isNotEmpty) {
      lines.add('ORG:${values['org']}');
    }
    if ((values['title'] ?? '').isNotEmpty) {
      lines.add('TITLE:${values['title']}');
    }
    if ((values['phone'] ?? '').isNotEmpty) {
      lines.add('TEL:${values['phone']}');
    }
    if ((values['email'] ?? '').isNotEmpty) {
      lines.add('EMAIL:${values['email']}');
    }
    if ((values['url'] ?? '').isNotEmpty) {
      lines.add('URL:${values['url']}');
    }
    if ((values['address'] ?? '').isNotEmpty) {
      lines.add('ADR:;;${values['address']};;;;');
    }
    lines.add('END:VCARD');
    return lines.join('\n');
  }
}
