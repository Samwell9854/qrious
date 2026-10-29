import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'address.dart';
import 'validators.dart';
import 'parsing.dart';

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
    QrField(id: 'nickname', label: 'Nickname', expert: true),
    // How the name is read aloud, which Japanese phones file contacts under.
    QrField(id: 'sound', label: 'Name Reading', hint: 'やまだ,たろう', expert: true),
    QrField(
      id: 'phone',
      label: 'Phone Number',
      hint: '+1 555 000 0000',
      validate: validatePhone,
    ),
    QrField(
      id: 'videophone',
      label: 'Video Phone Number',
      hint: '+1 555 000 0000',
      validate: validatePhone,
      expert: true,
    ),
    QrField(id: 'email', label: 'Email Address', validate: validateEmail),
    QrField(id: 'url', label: 'Website', validate: validateUrl),
    ...addressFields,
    QrField(
      id: 'birthday',
      label: 'Birthday',
      type: QrFieldType.date,
      validate: validateDate,
      expert: true,
    ),
    QrField(id: 'note', label: 'Note', expert: true),
  ];

  /// The properties beyond the name, in the order they are written, by tag and
  /// field. The beginner ones keep the order they had before expert mode, so a
  /// beginner's code is unchanged.
  static const _plain = [
    ('SOUND', 'sound'),
    ('NICKNAME', 'nickname'),
    ('TEL', 'phone'),
    ('TEL-AV', 'videophone'),
    ('EMAIL', 'email'),
    ('URL', 'url'),
  ];

  @override
  String buildQrString(Map<String, String> values) {
    final firstName = _escapeComponent(values['first_name'] ?? '');
    final lastName = _escapeComponent(values['last_name'] ?? '');
    // N: is "last,first", the comma being structure; with only one of the two
    // there is nothing to separate.
    final name = [lastName, firstName].where((s) => s.isNotEmpty).join(',');
    final properties = ['N:$name'];

    for (final (tag, id) in _plain) {
      final value = (values[id] ?? '').trim();
      if (value.isNotEmpty) properties.add('$tag:${_escape(value)}');
    }

    // ADR: is comma-separated like vCard's: post office box, extended address,
    // then the five the form asks for.
    final address = addressParts(values);
    if (address != null) {
      properties.add('ADR:,,${address.map(_escapeComponent).join(',')}');
    }

    // BDAY is the date without separators, as in 19850412.
    final birthday = (values['birthday'] ?? '').trim();
    if (birthday.isNotEmpty) {
      properties.add('BDAY:${_escape(birthday.replaceAll('-', ''))}');
    }
    final note = (values['note'] ?? '').trim();
    if (note.isNotEmpty) properties.add('NOTE:${_escape(note)}');

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

  /// Undoes [_escape] and [_escapeComponent]. A property the form holds twice (a
  /// second `TEL`) or not at all (`X-` extensions, a misspelt tag) is reported by its
  /// tag.
  @override
  QrParsed? parse(String payload) {
    if (!hasPrefixIgnoreCase(payload, 'MECARD:')) return null;
    final values = {for (final f in fields) f.id: ''};
    final unsupported = <String>[];
    final seen = <String>{};
    for (final piece in splitUnescaped(payload.substring(7), ';')) {
      if (piece.isEmpty) continue;
      final colon = piece.indexOf(':');
      if (colon < 0) {
        addOnce(unsupported, piece);
        continue;
      }
      final tag = piece.substring(0, colon).toUpperCase();
      final raw = piece.substring(colon + 1);
      // Each tag once: the form has one of each.
      if (_once.contains(tag) && !seen.add(tag)) {
        addOnce(unsupported, tag);
        continue;
      }
      switch (tag) {
        case 'N':
          final names = _components(raw);
          // One name is the first name, which is the one the form requires.
          if (names.length == 1) {
            values['first_name'] = names[0];
          } else {
            values['last_name'] = names[0];
            values['first_name'] = names[1];
          }
          if (names.length > 2) addOnce(unsupported, 'N (extra names)');
        case 'BDAY':
          final digits = unescapeBackslash(raw).trim();
          // Back to the field's own form, so the date picker can open on it. Any
          // other shape is kept as it was, for the validator to point at.
          final date = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(digits);
          values['birthday'] = date == null
              ? digits
              : '${date[1]}-${date[2]}-${date[3]}';
        case 'NOTE':
          values['note'] = unescapeBackslash(raw).trim();
        case _ when _plainIds.containsKey(tag):
          values[_plainIds[tag]!] = unescapeBackslash(raw).trim();
        case 'ADR':
          final adr = _components(raw);
          String at(int i) => i < adr.length ? adr[i] : '';
          if (at(0).isNotEmpty) addOnce(unsupported, 'ADR (PO box)');
          if (at(1).isNotEmpty) addOnce(unsupported, 'ADR (extended address)');
          for (final (i, f) in addressFields.indexed) {
            values[f.id] = at(i + 2);
          }
        default:
          addOnce(unsupported, piece.substring(0, colon));
      }
    }
    return QrParsed(values, unsupported);
  }

  static const _once = {
    'N',
    'SOUND',
    'NICKNAME',
    'TEL',
    'TEL-AV',
    'EMAIL',
    'URL',
    'ADR',
    'BDAY',
    'NOTE',
  };

  static final _plainIds = {for (final (tag, id) in _plain) tag: id};

  /// A value split at its unescaped commas, each component unescaped.
  static List<String> _components(String raw) => [
    for (final c in splitUnescaped(raw, ',')) unescapeBackslash(c),
  ];
}
