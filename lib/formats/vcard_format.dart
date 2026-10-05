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

  // Phones, emails and addresses are groups: none to start with, as many as the
  // user adds, each labelled with a kind that becomes a TYPE= parameter. The
  // kinds are the beginner set from RFC 2426; an empty value means no TYPE.
  static const _phones = QrField(
    id: 'phones',
    label: 'Phone',
    type: QrFieldType.group,
    parts: [
      QrField(
        id: 'number',
        label: 'Phone',
        hint: '+1 555 000 0000',
        validate: validatePhoneWithWait,
      ),
    ],
    kinds: [
      QrKind('CELL', 'Mobile', Icons.smartphone),
      QrKind('HOME', 'Home', Icons.home_outlined),
      QrKind('WORK', 'Work', Icons.work_outline),
      QrKind('FAX', 'Fax', Icons.fax_outlined),
      QrKind('', 'Other', Icons.phone_outlined),
    ],
  );

  static const _emails = QrField(
    id: 'emails',
    label: 'Email',
    type: QrFieldType.group,
    parts: [QrField(id: 'address', label: 'Email', validate: validateEmail)],
    kinds: [
      QrKind('HOME', 'Home', Icons.home_outlined),
      QrKind('WORK', 'Work', Icons.work_outline),
      QrKind('', 'Other', Icons.alternate_email),
    ],
  );

  static const _addresses = QrField(
    id: 'addresses',
    label: 'Address',
    type: QrFieldType.group,
    parts: addressFields,
    kinds: [
      QrKind('HOME', 'Home', Icons.home_outlined),
      QrKind('WORK', 'Work', Icons.work_outline),
    ],
  );

  @override
  List<QrField> get fields => const [
    QrField(id: 'first_name', label: 'First Name', required: true),
    QrField(id: 'last_name', label: 'Last Name'),
    QrField(id: 'org', label: 'Organization'),
    QrField(id: 'title', label: 'Job Title'),
    _phones,
    _emails,
    QrField(id: 'url', label: 'Website', validate: validateUrl),
    _addresses,
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

    for (final (tag, id) in const [('ORG', 'org'), ('TITLE', 'title')]) {
      final value = values[id] ?? '';
      if (value.isNotEmpty) lines.add('$tag:${_escape(value)}');
    }

    // TEL is not escaped: it is a phone number, not text, so a reader takes it as
    // it stands, and the validator keeps out everything but digits and dialling
    // marks. Escaping the `,` of a pause would leave a backslash in it, and a
    // vCard line ends at a line break, so a `;` wait is no separator here.
    for (final phone in QrEntries.read(values, _phones)) {
      final number = phone['number']!.trim();
      if (number.isNotEmpty) lines.add('TEL${_type(phone)}:$number');
    }

    for (final email in QrEntries.read(values, _emails)) {
      final address = email['address']!;
      if (address.isEmpty) continue;
      lines.add('EMAIL${_type(email)}:${_escape(address)}');
    }

    final url = values['url'] ?? '';
    if (url.isNotEmpty) lines.add('URL:${_escape(url)}');

    // ADR: has seven components: post office box, extended address, then the
    // five the form asks for.
    for (final address in QrEntries.read(values, _addresses)) {
      final parts = [for (final f in addressFields) address[f.id]!];
      if (parts.every((p) => p.isEmpty)) continue;
      lines.add('ADR${_type(address)}:;;${parts.map(_escape).join(';')}');
    }

    lines.add('END:VCARD');
    return lines.join('\n');
  }

  /// The entry's kind as a TYPE= parameter, or nothing for a kind of no type.
  static String _type(Map<String, String> entry) =>
      entry['kind']!.isEmpty ? '' : ';TYPE=${entry['kind']}';

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
