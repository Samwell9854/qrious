import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'address.dart';
import 'validators.dart';

/// The compact contact format from NTT DoCoMo. It carries less than a vCard (no
/// organisation or job title) but spends fewer characters on structure, so the
/// same contact makes a smaller, easier-to-scan code.
class MeCardFormat extends QrFormat {
  @override
  String get id => 'mecard';

  @override
  String get name => 'Contact (MeCard, compact)';

  @override
  QrFormatGroup get group => QrFormatGroup.contact;

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
    ...addressFields,
  ];

  @override
  String buildQrString(Map<String, String> values) {
    final firstName = _escapeComponent(values['first_name'] ?? '');
    final lastName = _escapeComponent(values['last_name'] ?? '');
    // N: is "last,first", the comma being structure; with only one of the two
    // there is nothing to separate.
    final name = [lastName, firstName].where((s) => s.isNotEmpty).join(',');
    final properties = ['N:$name'];

    for (final (tag, id) in const [
      ('TEL', 'phone'),
      ('EMAIL', 'email'),
      ('URL', 'url'),
    ]) {
      final value = (values[id] ?? '').trim();
      if (value.isNotEmpty) properties.add('$tag:${_escape(value)}');
    }

    // ADR: is comma-separated like vCard's: post office box, extended address,
    // then the five the form asks for.
    final address = addressParts(values);
    if (address != null) {
      properties.add('ADR:,,${address.map(_escapeComponent).join(',')}');
    }

    return 'MECARD:${properties.join(';')};;';
  }

  /// Backslash-escapes the one character that is structure in every value: `;`,
  /// which ends a property. MeCard has no escape for a line break, so one becomes
  /// a space. Backslash goes first, so it does not escape the backslashes the
  /// later replacements add.
  ///
  /// The spec also escapes `:` and `,`, but phone readers do not all undo it: the
  /// iPhone camera turned an escaped `https://` into `https\://` in testing. A colon after
  /// the tag is unambiguous anyway, and a comma only matters where it separates
  /// components, which [_escapeComponent] covers.
  String _escape(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(RegExp(r'\r\n|\r|\n'), ' ');

  /// For a value inside `N:` or `ADR:`, where a comma separates components.
  String _escapeComponent(String s) => _escape(s).replaceAll(',', r'\,');
}
