import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/import.dart';
import 'package:qrious/formats/mecard_format.dart';
import 'package:qrious/formats/phone_format.dart';
import 'package:qrious/formats/text_format.dart';
import 'package:qrious/formats/url_format.dart';
import 'package:qrious/formats/vcard_format.dart';
import 'package:qrious/formats/wifi_format.dart';

void main() {
  group('importPayload', () {
    test('lands an exact Qrious Wi-Fi payload in Wi-Fi, with no offer', () {
      final payload = WifiFormat().buildQrString({
        'ssid': 'Home;Net',
        'security': 'WPA/WPA2',
        'password': 'pw:1',
        'hidden': 'false',
      });
      final result = importPayload(payload);
      expect(result.format, isA<WifiFormat>());
      expect(result.values['ssid'], 'Home;Net');
      expect(result.offer, isNull);
    });

    test(
      'keeps a reordered Wi-Fi payload byte-exact in Text, with an offer',
      () {
        const payload = 'WIFI:S:x;T:WPA;P:y;;';
        final result = importPayload(payload);
        expect(result.format, isA<TextFormat>());
        expect(result.values, {TextFormat.fieldId: payload});
        expect(result.offer!.format, isA<WifiFormat>());
        expect(result.offer!.unsupported, isEmpty);
        expect(result.offer!.invalid, isEmpty);
        expect(result.offer!.values['ssid'], 'x');
      },
    );

    test('offers a vCard with an unsupported property, naming it', () {
      const payload =
          'BEGIN:VCARD\nVERSION:3.0\nN:Doe;Jo;;;\nFN:Jo Doe\nNOTE:hi\nEND:VCARD';
      final result = importPayload(payload);
      expect(result.format, isA<TextFormat>());
      expect(result.values[TextFormat.fieldId], payload);
      expect(result.offer!.format, isA<VCardFormat>());
      expect(result.offer!.unsupported, ['NOTE']);
    });

    test('lands a vCard the form reproduces exactly in vCard', () {
      final payload = VCardFormat().buildQrString({
        'first_name': 'Jo',
        'last_name': 'Doe',
        'org': 'Acme',
      });
      final result = importPayload(payload);
      expect(result.format, isA<VCardFormat>());
      expect(result.values['org'], 'Acme');
      expect(result.offer, isNull);
    });

    test('lands a MeCard in MeCard', () {
      final payload = MeCardFormat().buildQrString({
        'first_name': 'Jo',
        'last_name': 'Doe',
      });
      expect(importPayload(payload).format, isA<MeCardFormat>());
    });

    test('lands unclaimed text in Text with no offer', () {
      final result = importPayload('3ENQ0TNG5B');
      expect(result.format, isA<TextFormat>());
      expect(result.values, {TextFormat.fieldId: '3ENQ0TNG5B'});
      expect(result.offer, isNull);
    });

    test('does not let URL claim a geo: payload', () {
      final result = importPayload('geo:48.8584,2.2945');
      expect(result.format.id, 'geo');
      expect(result.offer, isNull);
      expect(UrlFormat().parse('geo:48.8584,2.2945'), isNull);
    });

    test('lands an http URL in URL', () {
      expect(importPayload('https://example.com').format, isA<UrlFormat>());
    });

    test('offers a phone value the validator rejects, with its message', () {
      final result = importPayload('tel:abc');
      expect(result.format, isA<TextFormat>());
      expect(result.offer!.format, isA<PhoneFormat>());
      expect(result.offer!.invalid, isNotEmpty);
      expect(result.offer!.invalid.first, startsWith('Phone Number: '));
    });

    test('checks the parts of a group entry too', () {
      final result = importPayload(
        'BEGIN:VCARD\nVERSION:3.0\nN:;Jo;;;\nFN:Jo\nTEL:x\nEND:VCARD',
      );
      expect(result.offer!.invalid, hasLength(1));
      expect(result.offer!.invalid.first, startsWith('Phone: '));
    });

    test('finds the Text format by type, wherever it is in the list', () {
      final result = importPayload('hello', [TextFormat(), WifiFormat()]);
      expect(result.format, isA<TextFormat>());
      expect(result.values[TextFormat.fieldId], 'hello');
    });
  });
}
