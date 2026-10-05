import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';

class GeoFormat extends QrFormat {
  @override
  String get id => 'geo';

  @override
  String get name => 'Location';

  @override
  IconData get icon => Icons.place_outlined;

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'latitude',
      label: 'Latitude',
      required: true,
      hint: '45.5017',
      validate: validateLatitude,
    ),
    QrField(
      id: 'longitude',
      label: 'Longitude',
      required: true,
      hint: '-73.5673',
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
    if (!_degrees.hasMatch(trimmed)) return 'Use decimal degrees, like 45.5017';
    return double.parse(trimmed).abs() > limit ? message : null;
  }

  static String? validateLatitude(String value) =>
      _validateDegrees(value, 90, 'Latitude runs from -90 to 90');

  static String? validateLongitude(String value) =>
      _validateDegrees(value, 180, 'Longitude runs from -180 to 180');
}
