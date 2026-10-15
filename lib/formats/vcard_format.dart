import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'address.dart';
import 'parsing.dart';
import 'validators.dart';

class VCardFormat extends QrFormat {
  @override
  String get id => 'vcard';

  @override
  String get name => 'Contact (vCard)';

  @override
  QrFormatGroup get group => QrFormatGroup.contact;

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

  /// Reads a vCard back: lines are unfolded (RFC 2426 section 4), `TYPE=` becomes the
  /// entry's kind, and text values are unescaped. A property the form has no field
  /// for (`NOTE`, `BDAY`, `PHOTO`, the extra components of `N:`) is reported by name.
  @override
  QrParsed? parse(String payload) {
    final lines = payload
        .replaceAll(RegExp(r'(\r\n|\n|\r)[ \t]'), '')
        .split(RegExp(r'\r\n|\n|\r'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty || lines.first.trim().toUpperCase() != 'BEGIN:VCARD') {
      return null;
    }

    final values = {
      'first_name': '',
      'last_name': '',
      'org': '',
      'title': '',
      'url': '',
    };
    final phones = <Map<String, String>>[];
    final emails = <Map<String, String>>[];
    final addresses = <Map<String, String>>[];
    final unsupported = <String>[];
    final seen = <String>{};
    var fullName = '';

    for (final line in lines.skip(1)) {
      final colon = _valueStart(line);
      if (colon < 0) {
        addOnce(unsupported, line.trim());
        continue;
      }
      final head = line.substring(0, colon).split(';');
      final value = line.substring(colon + 1);
      // A group prefix (`item1.TEL`) only ties properties together.
      final name = head.first.split('.').last.toUpperCase();
      final types = _types(head.skip(1));

      // Each of these once: the form has one name, organisation, title and site.
      if (const {'N', 'ORG', 'TITLE', 'URL'}.contains(name) &&
          !seen.add(name)) {
        addOnce(unsupported, name);
        continue;
      }
      switch (name) {
        case 'BEGIN' || 'VERSION':
          break;
        case 'FN':
          fullName = _unescape(value);
        case 'END':
          if (value.trim().toUpperCase() == 'VCARD') {
            return _finish(
              values,
              phones,
              emails,
              addresses,
              fullName,
              unsupported,
            );
          }
        case 'N':
          final n = [for (final c in splitUnescaped(value, ';')) _unescape(c)];
          String at(int i) => i < n.length ? n[i] : '';
          values['last_name'] = at(0);
          values['first_name'] = at(1);
          if (at(2).isNotEmpty) addOnce(unsupported, 'N (additional names)');
          if (at(3).isNotEmpty) addOnce(unsupported, 'N (prefix)');
          if (at(4).isNotEmpty) addOnce(unsupported, 'N (suffix)');
        case 'ORG':
          // The first component is the organisation, any after it a unit.
          final org = splitUnescaped(value, ';');
          values['org'] = _unescape(org.first);
          if (org.skip(1).any((c) => c.isNotEmpty)) {
            addOnce(unsupported, 'ORG (units)');
          }
        case 'TITLE':
          values['title'] = _unescape(value);
        case 'URL':
          values['url'] = _unescape(value);
        case 'TEL':
          if (value.trim().isNotEmpty) {
            phones.add({'number': value.trim(), 'kind': _kind(_phones, types)});
          }
        case 'EMAIL':
          if (value.isNotEmpty) {
            emails.add({
              'address': _unescape(value),
              'kind': _kind(_emails, types),
            });
          }
        case 'ADR':
          final adr = [
            for (final c in splitUnescaped(value, ';')) _unescape(c),
          ];
          String at(int i) => i < adr.length ? adr[i] : '';
          if (at(0).isNotEmpty) addOnce(unsupported, 'ADR (PO box)');
          if (at(1).isNotEmpty) addOnce(unsupported, 'ADR (extended address)');
          final entry = {
            for (final (i, f) in addressFields.indexed) f.id: at(i + 2),
            'kind': _kind(_addresses, types),
          };
          if (addressFields.any((f) => entry[f.id]!.isNotEmpty)) {
            addresses.add(entry);
          }
        default:
          addOnce(unsupported, name);
      }
    }
    // No END:VCARD: a truncated card is still read as far as it goes.
    return _finish(values, phones, emails, addresses, fullName, unsupported);
  }

  static QrParsed _finish(
    Map<String, String> values,
    List<Map<String, String>> phones,
    List<Map<String, String>> emails,
    List<Map<String, String>> addresses,
    String fullName,
    List<String> unsupported,
  ) {
    // A card with no usable N: still has its formatted name; the whole of it goes
    // in the one field the form requires, as there is no telling where it splits.
    if (values['first_name']!.isEmpty &&
        values['last_name']!.isEmpty &&
        fullName.isNotEmpty) {
      values['first_name'] = fullName;
    }
    putEntries(values, 'phones', phones);
    putEntries(values, 'emails', emails);
    putEntries(values, 'addresses', addresses);
    return QrParsed(values, unsupported);
  }

  /// Where a content line's value starts: its first colon outside a quoted
  /// parameter value, or -1.
  static int _valueStart(String line) {
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '"') quoted = !quoted;
      if (line[i] == ':' && !quoted) return i;
    }
    return -1;
  }

  /// The type names in a property's parameters, upper-cased: `TYPE=WORK,VOICE`, and
  /// the bare `WORK` that vCard 2.1 writes.
  static List<String> _types(Iterable<String> params) {
    final types = <String>[];
    for (final p in params) {
      final equals = p.indexOf('=');
      if (equals < 0) {
        types.add(p.toUpperCase());
      } else if (p.substring(0, equals).toUpperCase() == 'TYPE') {
        for (final t in p.substring(equals + 1).split(',')) {
          types.add(t.replaceAll('"', '').toUpperCase());
        }
      }
    }
    return types;
  }

  /// The first of [types] that [group] offers as a kind. A property with none of
  /// them is the group's no-type kind, or its first when it has no such kind.
  static String _kind(QrField group, List<String> types) {
    final offered = [for (final k in group.kinds!) k.value];
    for (final t in types) {
      if (t.isNotEmpty && offered.contains(t)) return t;
    }
    return offered.contains('') ? '' : offered.first;
  }

  /// Undoes [_escape]; `\n` and `\N` are the line break.
  static String _unescape(String s) => s.replaceAllMapped(
    RegExp(r'\\(.)', dotAll: true),
    (m) => m[1] == 'n' || m[1] == 'N' ? '\n' : m[1]!,
  );
}
