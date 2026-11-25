import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/models/qr_field.dart';
import 'package:qrious/formats/vcard_format.dart';

/// Phone entries as the screen stores them: the count, then each entry's number
/// and kind.
Map<String, String> phones(List<(String, String)> entries) => {
  'phones': '${entries.length}',
  for (final (i, (number, kind)) in entries.indexed) ...{
    'phones.$i.number': number,
    'phones.$i.kind': kind,
  },
};

Map<String, String> emails(List<(String, String)> entries) => {
  'emails': '${entries.length}',
  for (final (i, (address, kind)) in entries.indexed) ...{
    'emails.$i.address': address,
    'emails.$i.kind': kind,
  },
};

Map<String, String> addresses(List<(Map<String, String>, String)> entries) => {
  'addresses': '${entries.length}',
  for (final (i, (parts, kind)) in entries.indexed) ...{
    for (final MapEntry(:key, :value) in parts.entries)
      'addresses.$i.$key': value,
    'addresses.$i.kind': kind,
  },
};

void main() {
  final format = VCardFormat();

  group('VCardFormat.buildQrString', () {
    test('tolerates an empty map', () {
      expect(
        format.buildQrString({}),
        'BEGIN:VCARD\nVERSION:3.0\nN:;;;;\nFN:\nEND:VCARD',
      );
    });

    group('name lines', () {
      test('a first name alone fills the given-name slot', () {
        final lines = format.buildQrString({'first_name': 'Ada'}).split('\n');
        expect(lines, containsAllInOrder(['N:;Ada;;;', 'FN:Ada']));
      });

      test('a last name alone fills the family-name slot', () {
        final lines = format
            .buildQrString({'last_name': 'Lovelace'})
            .split('\n');
        expect(lines, containsAllInOrder(['N:Lovelace;;;;', 'FN:Lovelace']));
      });

      test('N: is family-first and FN: is given-first', () {
        final lines = format
            .buildQrString({'first_name': 'Ada', 'last_name': 'Lovelace'})
            .split('\n');
        expect(
          lines,
          containsAllInOrder(['N:Lovelace;Ada;;;', 'FN:Ada Lovelace']),
        );
      });
    });

    group('optional fields', () {
      test('are omitted entirely when absent', () {
        final payload = format.buildQrString({'first_name': 'Ada'});
        for (final tag in [
          'NICKNAME',
          'ORG',
          'TITLE',
          'TEL',
          'EMAIL',
          'URL',
          'ADR',
          'BDAY',
          'NOTE',
        ]) {
          expect(payload, isNot(contains(tag)));
        }
      });

      test('are omitted when present but empty', () {
        final payload = format.buildQrString({
          'first_name': 'Ada',
          'nickname': '',
          'org': '',
          'title': '',
          'url': '',
          'birthday': '',
          'note': '',
          ...phones([('', 'CELL')]),
          ...emails([('', 'HOME')]),
          ...addresses([
            ({'street': '', 'city': ''}, 'HOME'),
          ]),
        });
        expect(
          payload,
          'BEGIN:VCARD\nVERSION:3.0\nN:;Ada;;;\nFN:Ada\nEND:VCARD',
        );
      });

      test('are emitted in declaration order between FN: and END:', () {
        final payload = format.buildQrString({
          'first_name': 'Ada',
          'last_name': 'Lovelace',
          'nickname': 'Countess',
          'org': 'Analytical Engines',
          'title': 'Mathematician',
          ...phones([('+15550000000', 'CELL')]),
          ...emails([('ada@example.com', 'HOME')]),
          'url': 'https://example.com',
          ...addresses([
            (
              {
                'street': '12 Baker St',
                'city': 'London',
                'postal_code': 'NW1 6XE',
                'country': 'UK',
              },
              'HOME',
            ),
          ]),
          'birthday': '1815-12-10',
          'note': 'Wrote the first program\nfor the Engine',
        });
        expect(payload, '''
BEGIN:VCARD
VERSION:3.0
N:Lovelace;Ada;;;
FN:Ada Lovelace
NICKNAME:Countess
ORG:Analytical Engines
TITLE:Mathematician
TEL;TYPE=CELL:+15550000000
EMAIL;TYPE=HOME:ada@example.com
URL:https://example.com
ADR;TYPE=HOME:;;12 Baker St;London;;NW1 6XE;UK
BDAY:1815-12-10
NOTE:Wrote the first program\\nfor the Engine
END:VCARD''');
      });
    });

    group('entries', () {
      test('each phone, email and address becomes its own line', () {
        final payload = format.buildQrString({
          ...phones([
            ('5550001', 'CELL'),
            ('5550002', 'WORK'),
            ('5550003', ''),
          ]),
          ...emails([('a@x.io', 'WORK'), ('b@x.io', 'WORK')]),
          ...addresses([
            ({'city': 'Anjou'}, 'HOME'),
            ({'city': 'Laval'}, 'WORK'),
          ]),
        });
        expect(
          payload.split('\n'),
          containsAllInOrder([
            'TEL;TYPE=CELL:5550001',
            'TEL;TYPE=WORK:5550002',
            'TEL:5550003',
            'EMAIL;TYPE=WORK:a@x.io',
            'EMAIL;TYPE=WORK:b@x.io',
            'ADR;TYPE=HOME:;;;Anjou;;;',
            'ADR;TYPE=WORK:;;;Laval;;;',
          ]),
        );
      });

      test('every phone kind maps to its TYPE=', () {
        for (final (kind, expected) in [
          ('CELL', 'TEL;TYPE=CELL:5550000'),
          ('HOME', 'TEL;TYPE=HOME:5550000'),
          ('WORK', 'TEL;TYPE=WORK:5550000'),
          ('FAX', 'TEL;TYPE=FAX:5550000'),
          ('', 'TEL:5550000'),
        ]) {
          expect(
            format.buildQrString(phones([('5550000', kind)])),
            contains('$expected\n'),
          );
        }
      });

      test('an empty entry between filled ones is skipped', () {
        final lines = format
            .buildQrString(phones([('5550001', ''), ('', ''), ('5550003', '')]))
            .split('\n');
        expect(lines.where((l) => l.startsWith('TEL')), [
          'TEL:5550001',
          'TEL:5550003',
        ]);
      });

      test('each address part fills its own ADR: slot', () {
        expect(
          format.buildQrString(
            addresses([
              (
                {
                  'street': '10011 Renaude-Lapointe',
                  'city': 'Anjou',
                  'region': 'QC',
                  'postal_code': 'H1H 1H1',
                  'country': 'Canada',
                },
                'HOME',
              ),
            ]),
          ),
          contains(
            'ADR;TYPE=HOME:;;10011 Renaude-Lapointe;Anjou;QC;H1H 1H1;Canada',
          ),
        );
      });

      test('a phone keeps its pause and wait unescaped', () {
        expect(
          format.buildQrString(phones([('+15145550000;274,4', 'CELL')])),
          contains('TEL;TYPE=CELL:+15145550000;274,4\n'),
        );
      });

      test('a count beyond the stored entries reads them as empty', () {
        expect(
          format.buildQrString({'phones': '3', 'phones.0.number': '5550000'}),
          contains('TEL:5550000\n'),
        );
      });
    });

    group('escaping', () {
      test('a semicolon in a name does not split the N: components', () {
        final lines = format
            .buildQrString({'first_name': 'Ada', 'last_name': 'Lovelace; Jr'})
            .split('\n');
        expect(lines, contains(r'N:Lovelace\; Jr;Ada;;;'));
        expect(lines, contains(r'FN:Ada Lovelace\; Jr'));
      });

      test('a pasted newline stays inside the ADR: property', () {
        final payload = format.buildQrString(
          addresses([
            ({'street': '12 Baker St\nFlat 2'}, ''),
          ]),
        );
        expect(payload, contains(r'ADR:;;12 Baker St\nFlat 2;;;;'));
        // BEGIN, VERSION, N, FN, ADR, END — a raw newline would add a seventh.
        expect(payload.split('\n'), hasLength(6));
      });

      test('a carriage return or CRLF also becomes a literal \\n', () {
        expect(
          format.buildQrString(
            addresses([
              ({'street': 'a\r\nb\rc'}, ''),
            ]),
          ),
          contains(r'ADR:;;a\nb\nc;;;;'),
        );
      });

      test('a semicolon inside an address part does not split ADR:', () {
        expect(
          format.buildQrString(
            addresses([
              ({'street': 'Unit 4; Rear'}, ''),
            ]),
          ),
          contains(r'ADR:;;Unit 4\; Rear;;;;'),
        );
      });

      test('escapes backslash, semicolon and comma in a text value', () {
        expect(
          format.buildQrString({'org': r'A\B;C,D'}),
          contains(r'ORG:A\\B\;C\,D'),
        );
      });

      test('escapes the backslash before it can escape its own escapes', () {
        // Naive ordering would turn "\" into "\\" and then "\\\\".
        expect(format.buildQrString({'org': r'\'}), contains(r'ORG:\\'));
      });

      test('leaves ordinary punctuation alone', () {
        expect(
          format.buildQrString({'org': "O'Neil & Sons (Ltd.)"}),
          contains("ORG:O'Neil & Sons (Ltd.)"),
        );
      });
    });

    test('always opens with BEGIN and closes with END', () {
      final lines = format.buildQrString({'first_name': 'Ada'}).split('\n');
      expect(lines.first, 'BEGIN:VCARD');
      expect(lines.last, 'END:VCARD');
    });
  });

  group('VCardFormat.parse', () {
    test('reads back what it builds, escapes and kinds included', () {
      final values = {
        'first_name': r'A;n,a',
        'last_name': r'B\b',
        'nickname': 'Ada, the Countess',
        'org': 'Acme; Inc.',
        'title': 'Boss, Chief',
        'url': 'https://example.com/a',
        'phones': '2',
        'phones.0.number': '+1 555 000 0000',
        'phones.0.kind': 'CELL',
        'phones.1.number': '+15550000000,274',
        'phones.1.kind': '',
        'emails': '1',
        'emails.0.address': 'a@example.com',
        'emails.0.kind': 'WORK',
        'addresses': '1',
        'addresses.0.street': 'Line one\nLine two; 1, St',
        'addresses.0.city': 'Town',
        'addresses.0.region': 'QC',
        'addresses.0.postal_code': 'H0H 0H0',
        'addresses.0.country': 'CA',
        'addresses.0.kind': 'HOME',
        'birthday': '1815-12-10',
        'note': 'Line one\nLine two; with, punctuation \\ and a backslash',
      };
      final parsed = format.parse(format.buildQrString(values))!;
      expect(parsed.values, values);
      expect(parsed.unsupported, isEmpty);
    });

    test('ignores the prefix case and reads CRLF and folded lines', () {
      final parsed = format.parse(
        'begin:vcard\r\nVERSION:3.0\r\nN:Doe;Jo;;;\r\nFN:Jo Doe\r\n'
        'EMAIL;type=work:jo@exa\r\n mple.com\r\nEND:VCARD\r\n',
      )!;
      expect(parsed.values['first_name'], 'Jo');
      expect(parsed.values['emails.0.address'], 'jo@example.com');
      expect(parsed.values['emails.0.kind'], 'WORK');
      expect(parsed.unsupported, isEmpty);
    });

    test('keeps every type it knows, which beginner mode reads as one', () {
      final parsed = format.parse(
        'BEGIN:VCARD\nN:Doe;Jo;;;\n'
        'TEL;TYPE=VOICE,WORK:111\nTEL;CELL:222\nTEL;TYPE=VOICE,X-ODD:333\n'
        'TEL:444\nEMAIL;TYPE=INTERNET,PREF:a@example.com\n'
        'END:VCARD',
      )!;
      expect(parsed.values['phones.0.kind'], 'VOICE,WORK');
      expect(parsed.values['phones.1.kind'], 'CELL');
      expect(parsed.values['phones.2.kind'], 'VOICE');
      expect(parsed.values['phones.3.kind'], '');
      expect(parsed.values['emails.0.kind'], 'INTERNET,PREF');

      final beginner = QrForm.applied(
        format.fields,
        parsed.values,
        expert: false,
      );
      expect(beginner['phones.0.kind'], 'WORK');
      expect(beginner['phones.2.kind'], '');
      expect(beginner['emails.0.kind'], '');
    });

    test('writes several types as one TYPE list, in the order picked', () {
      final payload = format.buildQrString({
        'first_name': 'Jo',
        'phones': '1',
        'phones.0.number': '111',
        'phones.0.kind': 'WORK,VOICE,PREF',
        'emails': '1',
        'emails.0.address': 'a@example.com',
        'emails.0.kind': 'INTERNET,PREF',
      });
      expect(payload, contains('\nTEL;TYPE=WORK,VOICE,PREF:111\n'));
      expect(payload, contains('\nEMAIL;TYPE=INTERNET,PREF:a@example.com\n'));
      expect(format.parse(payload)!.unsupported, isEmpty);
    });

    test('lists what the form lacks, once each', () {
      final parsed = format.parse(
        'BEGIN:VCARD\nVERSION:3.0\nN:Doe;Jo;Mid;Dr;Jr\nFN:Jo Doe\n'
        'NOTE:a\nNOTE:b\nBDAY:1990-01-01\nPHOTO;ENCODING=b:AAAA\n'
        'ADR;TYPE=WORK:box;ext;St;City;;;\nORG:Acme;Unit\nURL:u\nURL:v\n'
        'END:VCARD',
      )!;
      expect(parsed.unsupported, [
        'N (additional names)',
        'N (prefix)',
        'N (suffix)',
        'NOTE',
        'PHOTO',
        'ADR (PO box)',
        'ADR (extended address)',
        'ORG (units)',
        'URL',
      ]);
      expect(parsed.values['org'], 'Acme');
      expect(parsed.values['url'], 'u');
      expect(parsed.values['note'], 'a');
      expect(parsed.values['birthday'], '1990-01-01');
    });

    test('reads a basic-form BDAY into the date field, and keeps any other', () {
      String? birthday(String bday) => format
          .parse('BEGIN:VCARD\nN:Doe;Jo;;;\nBDAY:$bday\nEND:VCARD')!
          .values['birthday'];
      expect(birthday('19900412'), '1990-04-12');
      expect(birthday('1990-04-12'), '1990-04-12');
      // A time, or a date with no year, is left for the validator to point at.
      expect(birthday('1990-04-12T10:00:00Z'), '1990-04-12T10:00:00Z');
      expect(birthday('--0412'), '--0412');
    });

    test('falls back to FN when N is empty', () {
      final parsed = format.parse('BEGIN:VCARD\nFN:Jo Doe\nEND:VCARD')!;
      expect(parsed.values['first_name'], 'Jo Doe');
    });

    test('does not throw on malformed input', () {
      for (final payload in [
        'BEGIN:VCARD',
        'BEGIN:VCARD\nEND:VCARD',
        'BEGIN:VCARD\nnonsense\n;;;:\nN\nTEL\nADR:\nEND:VCARD',
        'BEGIN:VCARD\nN:\\\nEND:VCARD',
      ]) {
        expect(() => format.parse(payload), returnsNormally, reason: payload);
      }
    });

    test('returns null for another prefix', () {
      expect(format.parse('MECARD:N:a;;'), isNull);
      expect(format.parse('BEGIN:VCALENDAR'), isNull);
      expect(format.parse('hello'), isNull);
    });
  });

  group('no part of the name is required', () {
    test('a last name alone fills N and FN', () {
      final payload = format.buildQrString({'last_name': 'Lovelace'});
      expect(payload, contains('\nN:Lovelace;;;;\nFN:Lovelace\n'));
      expect(format.parse(payload)!.values['last_name'], 'Lovelace');
      expect(format.parse(payload)!.values['first_name'], '');
    });

    test('an organisation alone is what FN says, and reads back as one', () {
      final payload = format.buildQrString({'org': 'Acme'});
      expect(payload, contains('\nN:;;;;\nFN:Acme\nORG:Acme\n'));
      final parsed = format.parse(payload)!;
      expect(parsed.values['org'], 'Acme');
      expect(parsed.values['first_name'], '');
      expect(format.buildQrString(parsed.values), payload);
    });

    test('with no name or organisation, N and FN are still written', () {
      final payload = format.buildQrString({
        'phones': '1',
        'phones.0.number': '5550000',
        'phones.0.kind': 'CELL',
      });
      expect(payload, startsWith('BEGIN:VCARD\nVERSION:3.0\nN:;;;;\nFN:\n'));
      expect(format.buildQrString(format.parse(payload)!.values), payload);
    });

    test('no field is required', () {
      expect(format.fields.where((f) => f.required), isEmpty);
    });
  });
}
