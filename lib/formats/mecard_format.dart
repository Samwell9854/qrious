import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';

/// The compact contact format from NTT DoCoMo. It carries less than a vCard (no
/// organisation or job title) but spends fewer characters on structure, so the
/// same contact makes a smaller, easier-to-scan code.
class MeCardFormat extends QrFormat {
  @override
  String get id => 'mecard';

  @override
  String get name => 'Contact (MeCard)';

  @override
  IconData get icon => Icons.badge_outlined;

  @override
  List<QrField> get fields => const [
    QrField(id: 'first_name', label: 'First Name', required: true),
    QrField(id: 'last_name', label: 'Last Name'),
    QrField(
      id: 'phone',
      label: 'Phone Number',
      hint: '+1 555 000 0000',
      validate: validatePhone,
    ),
    QrField(id: 'email', label: 'Email Address', validate: validateEmail),
    QrField(id: 'url', label: 'Website', validate: validateUrl),
    QrField(id: 'address', label: 'Address'),
  ];

  @override
  String buildQrString(Map<String, String> values) {
    final firstName = _escape(values['first_name'] ?? '');
    final lastName = _escape(values['last_name'] ?? '');
    // N: is "last,first", the comma being structure; with only one of the two
    // there is nothing to separate.
    final name = [lastName, firstName].where((s) => s.isNotEmpty).join(',');
    final properties = ['N:$name'];

    for (final (tag, id) in const [
      ('TEL', 'phone'),
      ('EMAIL', 'email'),
      ('URL', 'url'),
      ('ADR', 'address'),
    ]) {
      final value = values[id] ?? '';
      if (value.isNotEmpty) properties.add('$tag:${_escape(value)}');
    }

    return 'MECARD:${properties.join(';')};;';
  }

  /// Backslash-escapes what MeCard treats as structure: `;` ends a property, `:`
  /// separates a tag from its value, and `,` splits the name. MeCard has no escape
  /// for a line break, so one becomes a space. Backslash goes first, so it does not
  /// escape the backslashes the later replacements add.
  String _escape(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(':', r'\:')
      .replaceAll(',', r'\,')
      .replaceAll(RegExp(r'\r\n|\r|\n'), ' ');
}
