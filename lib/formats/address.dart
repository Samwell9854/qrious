/// The postal address fields a contact format offers, shared by vCard and MeCard.
///
/// Separate fields rather than one free-text address, because both formats have
/// a slot for each part. Given one line, a phone reader has to guess where the
/// street ends and the city begins, and guesses wrong on something as ordinary
/// as a hyphenated street name.
library;

import '../models/qr_field.dart';

const addressFields = [
  QrField(id: 'street', label: 'Street Address'),
  QrField(id: 'city', label: 'City'),
  QrField(id: 'region', label: 'Province / State'),
  QrField(id: 'postal_code', label: 'Postal / ZIP Code'),
  QrField(id: 'country', label: 'Country'),
];

/// The address parts from [values], in the order both formats' `ADR` slots
/// take them after the post office box and extended address: street, city,
/// region, postal code, country. Null when every part is empty, so the caller
/// can omit `ADR` entirely.
List<String>? addressParts(Map<String, String> values) {
  final parts = [for (final f in addressFields) values[f.id] ?? ''];
  return parts.every((p) => p.isEmpty) ? null : parts;
}
