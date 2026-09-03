import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';

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
    QrField(
      id: 'phone',
      label: 'Phone Number',
      hint: '+1 555 000 0000',
      validate: validatePhone,
    ),
    QrField(id: 'email', label: 'Email Address', validate: validateEmail),
    QrField(id: 'url', label: 'Website', validate: validateUrl),
    QrField(id: 'address', label: 'Address', type: QrFieldType.multiline),
  ];

  @override
  String buildQrString(Map<String, String> values) {
    final firstName = values['first_name'] ?? '';
    final lastName = values['last_name'] ?? '';
    final fullName = [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
    final lines = [
      'BEGIN:VCARD',
      'VERSION:3.0',
      // The semicolons between the five components of N: are structure, so the
      // components are escaped individually and then joined.
      'N:${_escape(lastName)};${_escape(firstName)};;;',
      'FN:${_escape(fullName)}',
    ];

    for (final (tag, id) in const [
      ('ORG', 'org'),
      ('TITLE', 'title'),
      ('TEL', 'phone'),
      ('EMAIL', 'email'),
      ('URL', 'url'),
    ]) {
      final value = values[id] ?? '';
      if (value.isNotEmpty) lines.add('$tag:${_escape(value)}');
    }

    // ADR: has seven components; the address goes in the third, the street.
    final address = values['address'] ?? '';
    if (address.isNotEmpty) lines.add('ADR:;;${_escape(address)};;;;');

    lines.add('END:VCARD');
    return lines.join('\n');
  }

  /// Escapes a vCard text value per RFC 2426 section 5: backslash, semicolon and
  /// comma are backslash-escaped, and a line break becomes a literal `\n`.
  ///
  /// The line break matters most here. `address` is a multiline field, so a user
  /// pressing Enter would otherwise put a raw newline inside the value, and a
  /// newline is what ends a vCard property — the rest of the address would parse
  /// as a malformed property of its own and the card would be rejected.
  ///
  /// Backslash is replaced first, otherwise it would escape the backslashes the
  /// later replacements introduce.
  String _escape(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\n');
}
