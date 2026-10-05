import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'address.dart';
import 'validators.dart';

class VCardFormat extends QrFormat {
  @override
  String get id => 'vcard';

  @override
  String get name => 'Contact (vCard)';

  @override
  IconData get icon => Icons.contact_page_outlined;

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
    QrField(
      id: 'phone_type',
      label: 'Phone Type',
      type: QrFieldType.dropdown,
      options: ['Mobile', 'Home', 'Work', 'Other'],
    ),
    QrField(id: 'email', label: 'Email Address', validate: validateEmail),
    QrField(
      id: 'email_type',
      label: 'Email Type',
      type: QrFieldType.dropdown,
      options: ['Home', 'Work', 'Other'],
    ),
    QrField(id: 'url', label: 'Website', validate: validateUrl),
    ...addressFields,
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
      if (value.isEmpty) continue;
      final type = switch ((tag, values['${id}_type'])) {
        ('TEL', 'Mobile') => ';TYPE=CELL',
        ('TEL' || 'EMAIL', 'Home') => ';TYPE=HOME',
        ('TEL' || 'EMAIL', 'Work') => ';TYPE=WORK',
        _ => '',
      };
      // TEL is not escaped: it is a phone number, not text, so a reader takes it
      // as it stands, and validatePhone keeps out everything but digits and
      // dialling marks. Escaping the `,` of a pause would leave a backslash in it.
      lines.add('$tag$type:${tag == 'TEL' ? value.trim() : _escape(value)}');
    }

    // ADR: has seven components: post office box, extended address, then the
    // five the form asks for.
    final address = addressParts(values);
    if (address != null) lines.add('ADR:;;${address.map(_escape).join(';')}');

    lines.add('END:VCARD');
    return lines.join('\n');
  }

  /// Escapes a vCard text value per RFC 2426 section 5: backslash, semicolon and
  /// comma are backslash-escaped, and a line break becomes a literal `\n`.
  ///
  /// The line break matters most here. A pasted value can carry a raw newline, and
  /// a newline is what ends a vCard property — the rest of the value would parse
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
