import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/wifi_format.dart';

void main() {
  final format = WifiFormat();

  group('WifiFormat.buildQrString', () {
    test('tolerates an empty map', () {
      expect(format.buildQrString({}), 'WIFI:T:WPA;S:;P:;H:false;;');
    });

    test('emits an SSID and password', () {
      expect(
        format.buildQrString({'ssid': 'MyNetwork', 'password': 'hunter2'}),
        'WIFI:T:WPA;S:MyNetwork;P:hunter2;H:false;;',
      );
    });

    group('security type', () {
      test('WPA/WPA2 maps to WPA', () {
        expect(
          format.buildQrString({'security': 'WPA/WPA2'}),
          contains('T:WPA;'),
        );
      });

      test('WEP maps to WEP', () {
        expect(format.buildQrString({'security': 'WEP'}), contains('T:WEP;'));
      });

      test('None maps to nopass', () {
        expect(
          format.buildQrString({'security': 'None'}),
          contains('T:nopass;'),
        );
      });

      test('an unrecognised value falls back to WPA', () {
        expect(format.buildQrString({'security': 'WPA3'}), contains('T:WPA;'));
      });
    });

    group('hidden flag', () {
      test("'true' emits H:true", () {
        expect(format.buildQrString({'hidden': 'true'}), contains('H:true;'));
      });

      test("'false' emits H:false", () {
        expect(format.buildQrString({'hidden': 'false'}), contains('H:false;'));
      });

      test('anything else emits H:false', () {
        expect(format.buildQrString({'hidden': 'yes'}), contains('H:false;'));
      });
    });

    group('escaping', () {
      test(r'escapes \ ; , " and : in the SSID', () {
        expect(
          format.buildQrString({'ssid': r'a\b;c,d"e:f'}),
          r'WIFI:T:WPA;S:a\\b\;c\,d\"e\:f;P:;H:false;;',
        );
      });

      test('escapes the same characters in the password', () {
        expect(
          format.buildQrString({'ssid': 'net', 'password': r'p;a\ss'}),
          r'WIFI:T:WPA;S:net;P:p\;a\\ss;H:false;;',
        );
      });

      test('leaves ordinary characters alone', () {
        expect(
          format.buildQrString({'ssid': "Café 5GHz-2 (guest)!"}),
          'WIFI:T:WPA;S:Café 5GHz-2 (guest)!;P:;H:false;;',
        );
      });
    });
  });

  group('WifiFormat.parse', () {
    test('reads back what it builds, escapes included', () {
      final values = {
        'ssid': r'a;b,c:d\e"f',
        'security': 'WEP',
        'password': r'p;w:"\,',
        'hidden': 'true',
      };
      final parsed = format.parse(format.buildQrString(values))!;
      expect(parsed.values, values);
      expect(parsed.unsupported, isEmpty);
    });

    test('maps every security type the form offers', () {
      expect(format.parse('WIFI:T:WPA;S:x;;')!.values['security'], 'WPA/WPA2');
      expect(format.parse('WIFI:T:WEP;S:x;;')!.values['security'], 'WEP');
      expect(format.parse('WIFI:T:nopass;S:x;;')!.values['security'], 'None');
      expect(format.parse('WIFI:S:x;;')!.values['security'], 'None');
    });

    test('takes the keys in any order and ignores the prefix case', () {
      final parsed = format.parse('wifi:S:x;T:WPA;P:y;H:TRUE;;')!;
      expect(parsed.values, {
        'ssid': 'x',
        'security': 'WPA/WPA2',
        'password': 'y',
        'hidden': 'true',
      });
      expect(parsed.unsupported, isEmpty);
    });

    test('lists keys and security types the form lacks', () {
      final parsed = format.parse('WIFI:T:SAE;S:x;R:1;E:PEAP;R:2;;')!;
      expect(parsed.unsupported, ['R', 'E', 'T:SAE']);
      expect(parsed.values['security'], 'WPA/WPA2');
    });

    test('does not throw on malformed input', () {
      for (final payload in [
        'WIFI:',
        'WIFI:;;;',
        r'WIFI:S:x\',
        'WIFI:junk;:;',
      ]) {
        expect(() => format.parse(payload), returnsNormally);
      }
    });

    test('returns null for another prefix', () {
      expect(format.parse('MECARD:N:a;;'), isNull);
      expect(format.parse('hello'), isNull);
    });
  });
}
