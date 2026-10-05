import 'package:flutter_test/flutter_test.dart';
import 'package:qrious/formats/geo_format.dart';

void main() {
  final format = GeoFormat();

  group('GeoFormat.buildQrString', () {
    test('tolerates an empty map', () {
      expect(format.buildQrString({}), 'geo:,');
    });

    test('joins latitude and longitude after the geo: scheme', () {
      expect(
        format.buildQrString({'latitude': '45.5017', 'longitude': '-73.5673'}),
        'geo:45.5017,-73.5673',
      );
    });

    test('trims stray spaces from a pasted coordinate', () {
      expect(
        format.buildQrString({'latitude': ' 45.5 ', 'longitude': ' -73.5'}),
        'geo:45.5,-73.5',
      );
    });
  });

  group('coordinate validators', () {
    test('accept decimal degrees within range', () {
      for (final value in ['0', '45', '-45.5017', '+89.999', '90']) {
        expect(GeoFormat.validateLatitude(value), isNull, reason: value);
      }
      for (final value in ['-180', '179.99', '-73.5673']) {
        expect(GeoFormat.validateLongitude(value), isNull, reason: value);
      }
    });

    test('reject values out of range', () {
      expect(GeoFormat.validateLatitude('90.1'), isNotNull);
      expect(GeoFormat.validateLatitude('-91'), isNotNull);
      expect(GeoFormat.validateLongitude('180.5'), isNotNull);
    });

    test('reject what geo: cannot carry', () {
      for (final value in ['45,5', '1e2', '45°30\'', 'north', '.5', '45.']) {
        expect(GeoFormat.validateLatitude(value), isNotNull, reason: value);
      }
    });
  });
}
