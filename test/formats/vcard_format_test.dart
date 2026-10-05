import 'package:flutter_test/flutter_test.dart';
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
        for (final tag in ['ORG', 'TITLE', 'TEL', 'EMAIL', 'URL', 'ADR']) {
          expect(payload, isNot(contains(tag)));
        }
      });

      test('are omitted when present but empty', () {
        final payload = format.buildQrString({
          'first_name': 'Ada',
          'org': '',
          'title': '',
          'url': '',
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
        });
        expect(payload, '''
BEGIN:VCARD
VERSION:3.0
N:Lovelace;Ada;;;
FN:Ada Lovelace
ORG:Analytical Engines
TITLE:Mathematician
TEL;TYPE=CELL:+15550000000
EMAIL;TYPE=HOME:ada@example.com
URL:https://example.com
ADR;TYPE=HOME:;;12 Baker St;London;;NW1 6XE;UK
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
}
