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
  ];

  /// `geo:<lat>,<lon>` per RFC 5870, in decimal degrees as typed.
  @override
  String buildQrString(Map<String, String> values) {
    final latitude = (values['latitude'] ?? '').trim();
    final longitude = (values['longitude'] ?? '').trim();
    return 'geo:$latitude,$longitude';
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

  /// `geo:<lat>,<lon>[,<altitude>][;<param>...]`. The form holds the two
  /// coordinates; altitude and parameters such as `u=` (uncertainty) or `crs=` are
  /// reported as unsupported.
  @override
  QrParsed? parse(String payload) {
    if (!hasPrefixIgnoreCase(payload, 'geo:')) return null;
    final rest = payload.substring(4);
    // Some generators append a query (`geo:0,0?q=...`) where the RFC has `;`.
    final end = rest.indexOf(RegExp(r'[;?]'));
    final coordinates = (end < 0 ? rest : rest.substring(0, end)).split(',');
    final unsupported = <String>[];
    if (coordinates.length > 2) unsupported.add('altitude');
    if (end >= 0) {
      for (final param in rest.substring(end + 1).split(RegExp(r'[;&]'))) {
        if (param.isEmpty) continue;
        final equals = param.indexOf('=');
        addOnce(unsupported, equals < 0 ? param : param.substring(0, equals));
      }
    }
    return QrParsed({
      'latitude': coordinates[0],
      'longitude': coordinates.length > 1 ? coordinates[1] : '',
    }, unsupported);
  }
}
