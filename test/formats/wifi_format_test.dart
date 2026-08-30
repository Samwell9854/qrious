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
}
