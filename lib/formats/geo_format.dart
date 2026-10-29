import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'parsing.dart';

class GeoFormat extends QrFormat {
  @override
  String get id => 'geo';

  @override
  String get name => 'Location';

  @override
  QrFormatGroup get group => QrFormatGroup.web;

  @override
  IconData get icon => Icons.place_outlined;

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'latitude',
      label: 'Latitude',
      required: true,
      hint: '48.8584',
      validate: validateLatitude,
    ),
    QrField(
      id: 'longitude',
      label: 'Longitude',
      required: true,
      hint: '2.2945',
      validate: validateLongitude,
    ),
    QrField(
      id: 'altitude',
      label: 'Altitude (metres)',
      hint: '330',
      validate: validateAltitude,
      expert: true,
    ),
    QrField(
      id: 'uncertainty',
      label: 'Uncertainty (metres)',
      hint: '25',
      validate: validateUncertainty,
      expert: true,
    ),
  ];

  /// `geo:<lat>,<lon>[,<alt>][;u=<metres>]` per RFC 5870, in decimal degrees and
  /// metres as typed. Altitude is height above the WGS-84 ellipsoid; the uncertainty
  /// is a radius around the point, which a reader may show as a circle.
  @override
  String buildQrString(Map<String, String> values) {
    final latitude = (values['latitude'] ?? '').trim();
    final longitude = (values['longitude'] ?? '').trim();
    final altitude = (values['altitude'] ?? '').trim();
    final uncertainty = (values['uncertainty'] ?? '').trim();
    return 'geo:$latitude,$longitude'
        '${altitude.isEmpty ? '' : ',$altitude'}'
        '${uncertainty.isEmpty ? '' : ';u=$uncertainty'}';
  }

  /// Decimal degrees with a point, the only form RFC 5870 allows: no comma
  /// decimals, no exponent, no degrees-minutes-seconds.
  static final RegExp _degrees = RegExp(r'^[+-]?\d{1,3}(\.\d+)?$');

  static String? _validateDegrees(String value, double limit, String message) {
    final trimmed = value.trim();
    if (!_degrees.hasMatch(trimmed)) return 'Use decimal degrees, like 48.8584';
    return double.parse(trimmed).abs() > limit ? message : null;
  }

  static String? validateLatitude(String value) =>
      _validateDegrees(value, 90, 'Latitude runs from -90 to 90');

  static String? validateLongitude(String value) =>
      _validateDegrees(value, 180, 'Longitude runs from -180 to 180');

  /// A number as RFC 5870 writes one: digits with an optional point, no `+`.
  static final RegExp _number = RegExp(r'^-?\d+(\.\d+)?$');

  static String? validateAltitude(String value) =>
      _number.hasMatch(value.trim()) ? null : 'Use metres, like 330 or -12.5';

  static String? validateUncertainty(String value) =>
      _number.hasMatch(value.trim()) && !value.trim().startsWith('-')
      ? null
      : 'Use metres, like 25';

  /// `geo:<lat>,<lon>[,<altitude>][;<param>...]`. The form holds the coordinates,
  /// the altitude and one `u=` (uncertainty); other parameters, such as `crs=`, and
  /// a fourth coordinate are reported as unsupported.
  @override
  QrParsed? parse(String payload) {
    if (!hasPrefixIgnoreCase(payload, 'geo:')) return null;
    final rest = payload.substring(4);
    // Some generators append a query (`geo:0,0?q=...`) where the RFC has `;`.
    final end = rest.indexOf(RegExp(r'[;?]'));
    final coordinates = (end < 0 ? rest : rest.substring(0, end)).split(',');
    final unsupported = <String>[];
    if (coordinates.length > 3) unsupported.add('coordinates beyond altitude');
    var uncertainty = '';
    if (end >= 0) {
      for (final param in rest.substring(end + 1).split(RegExp(r'[;&]'))) {
        if (param.isEmpty) continue;
        final equals = param.indexOf('=');
        final name = equals < 0 ? param : param.substring(0, equals);
        if (name == 'u' && equals > 0 && uncertainty.isEmpty) {
          uncertainty = param.substring(equals + 1);
        } else {
          addOnce(unsupported, name);
        }
      }
    }
    String at(int i) => i < coordinates.length ? coordinates[i] : '';
    return QrParsed({
      'latitude': at(0),
      'longitude': at(1),
      'altitude': at(2),
      'uncertainty': uncertainty,
    }, unsupported);
  }
}
