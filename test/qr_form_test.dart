import 'package:flutter/material.dart' show Icons, IconData;
import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/import.dart';
import 'package:qrious/formats/text_format.dart';
import 'package:qrious/formats/validators.dart';
import 'package:qrious/models/qr_field.dart';
import 'package:qrious/models/qr_format.dart';

const phones = QrField(
  id: 'phone',
  label: 'Phone',
  type: QrFieldType.group,
  parts: [QrField(id: 'number', label: 'Number')],
  kinds: [
    QrKind('CELL', 'Mobile', Icons.smartphone),
    QrKind('WORK', 'Work', Icons.work_outline),
    QrKind('', 'Other', Icons.phone),
  ],
  expertKinds: [
    QrKind('VOICE', 'Voice', Icons.phone),
    QrKind('PREF', 'Main', Icons.star),
  ],
  multipleKinds: true,
);

/// A format with one field of each kind of expert-ness, written `name;note;form;to;
/// phone:kind=number,...`.
class Sample extends QrFormat {
  @override
  String get id => 'sample';
  @override
  String get name => 'Sample';
  @override
  IconData get icon => Icons.abc;
  @override
  QrFormatGroup get group => QrFormatGroup.text;

  @override
  List<QrField> get fields => const [
    QrField(id: 'name', label: 'Name'),
    QrField(id: 'note', label: 'Note', expert: true),
    QrField(
      id: 'form',
      label: 'Form',
      type: QrFieldType.dropdown,
      options: ['short', 'long'],
      expert: true,
    ),
    QrField(
      id: 'to',
      label: 'Also to',
      showWhen: (field: 'form', value: 'long'),
    ),
    phones,
  ];

  @override
  String buildQrString(Map<String, String> v) => [
    'S:${v['name'] ?? ''}',
    v['note'] ?? '',
    // A dropdown beginner mode does not write reads as its default.
    v['form'] ?? 'short',
    v['to'] ?? '',
    for (final e in QrEntries.read(v, phones)) '${e['kind']}=${e['number']}',
  ].join(';');

  @override
  QrParsed? parse(String payload) {
    if (!payload.startsWith('S:')) return null;
    final parts = payload.substring(2).split(';');
    final entries = parts.skip(4).toList();
    return QrParsed({
      'name': parts[0],
      'note': parts[1],
      'form': parts[2],
      'to': parts[3],
      'phone': '${entries.length}',
      for (final (i, e) in entries.indexed) ...{
        QrEntries.kind('phone', i): e.split('=')[0],
        QrEntries.part('phone', i, 'number'): e.split('=')[1],
      },
    });
  }
}

void main() {
  final fields = Sample().fields;
  final values = {
    'name': 'Ann',
    'note': 'hi',
    'form': 'long',
    'to': 'Bob',
    'phone': '2',
    'phone.0.kind': 'WORK,VOICE,PREF',
    'phone.0.number': '1',
    'phone.1.kind': 'PREF',
    'phone.1.number': '2',
  };

  group('QrForm', () {
    test('beginner mode leaves out expert fields and what they show', () {
      final applied = QrForm.applied(fields, values, expert: false);
      expect(applied.containsKey('note'), isFalse);
      expect(applied.containsKey('form'), isFalse);
      // Shown only with the long form, which beginner mode does not apply.
      expect(applied.containsKey('to'), isFalse);
      expect(applied['name'], 'Ann');
    });

    test('expert mode writes everything shown', () {
      expect(QrForm.applied(fields, values, expert: true), values);
      final short = {...values, 'form': 'short'};
      expect(
        QrForm.applied(fields, short, expert: true).containsKey('to'),
        isFalse,
      );
    });

    test('a combined kind reads as its first beginner kind, else none', () {
      final applied = QrForm.applied(fields, values, expert: false);
      expect(applied['phone.0.kind'], 'WORK');
      expect(applied['phone.1.kind'], '');
      expect(QrForm.beginnerKind(phones, 'CELL'), 'CELL');
    });

    test('names what beginner mode would not write', () {
      expect(QrForm.expertOnly(fields, values), [
        'Note',
        'Form',
        'Also to',
        'Phone type',
      ]);
      expect(
        QrForm.expertOnly(fields, {
          'name': 'Ann',
          'phone': '1',
          'phone.0.kind': 'CELL',
          'phone.0.number': '1',
        }),
        isEmpty,
      );
    });

    test('kinds in expert mode add the expert ones', () {
      expect(phones.kindsFor(expert: false).length, 3);
      expect(phones.kindsFor(expert: true).map((k) => k.value), [
        'CELL',
        'WORK',
        '',
        'VOICE',
        'PREF',
      ]);
    });
  });

  group('importing by mode', () {
    final formats = [Sample(), TextFormat()];
    final payload = Sample().buildQrString(values);

    test('expert mode reads expert content into the form', () {
      final result = importPayload(payload, formats: formats, expert: true);
      expect(result.format, isA<Sample>());
      expect(result.offer, isNull);
    });

    test('beginner mode keeps it as text and names what expert mode adds', () {
      final result = importPayload(payload, formats: formats);
      expect(result.format, isA<TextFormat>());
      expect(result.offer!.expertOnly, contains('Note'));
      expect(result.offer!.unsupported, isEmpty);
    });

    test('a payload beginner mode can write opens in either mode', () {
      final plain = Sample().buildQrString({
        'name': 'Ann',
        'phone': '1',
        'phone.0.kind': 'CELL',
        'phone.0.number': '5',
      });
      for (final expert in [false, true]) {
        expect(
          importPayload(plain, formats: formats, expert: expert).format,
          isA<Sample>(),
        );
      }
    });
  });

  group('dates', () {
    test('a real YYYY-MM-DD date is read, anything else is not', () {
      expect(parseIsoDate('1985-04-12'), DateTime(1985, 4, 12));
      expect(parseIsoDate('2023-02-29'), isNull);
      expect(parseIsoDate('1985-4-12'), isNull);
      expect(parseIsoDate('19850412'), isNull);
      expect(validateDate('2024-02-29'), isNull);
      expect(validateDate('2024-13-01'), isNotNull);
    });

    test('formats with leading zeros', () {
      expect(formatIsoDate(DateTime(812, 3, 4)), '0812-03-04');
    });
  });
}
