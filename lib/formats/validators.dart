/// Shared field validators.
///
/// A validator judges one value in isolation and returns the message to show
/// under the field, or null when the value is fine. It is never called with an
/// empty string: an empty field means "not filled in yet", which is what
/// `QrField.required` is for, and flagging a field nobody has typed in yet
/// would put an error on the form the moment it opens.
///
/// These live here rather than in one format because several formats want the
/// same rule — a vCard has an email, a URL and a phone number in it, and they
/// are the same things the dedicated formats encode.
library;

import 'dart:convert';

// Deliberately loose: the only shapes worth rejecting are the ones no mail
// server would accept. Anything stricter starts refusing addresses that work.
final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

final RegExp _phone = RegExp(r'^\+?[\d ().-]+$');

final RegExp _digit = RegExp(r'\d');

String? validateEmail(String value) => _email.hasMatch(value.trim())
    ? null
    : 'Enter an address like name@example.com';

/// Requires a scheme. A bare `example.com` scans as a scheme-less string, and
/// what a reader does with that is anyone's guess — most treat it as text.
String? validateUrl(String value) {
  const message = 'Enter a full URL, including https://';
  final trimmed = value.trim();
  if (trimmed.contains(RegExp(r'\s'))) return message;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return message;
  return null;
}

String? validatePhone(String value) {
  final trimmed = value.trim();
  if (!_phone.hasMatch(trimmed)) return 'Use digits, spaces and + ( ) - only';
  if (_digit.allMatches(trimmed).length < 3) return 'That is too short';
  return null;
}

/// 802.11 caps the SSID at 32 bytes, not 32 characters, so a name in a
/// non-Latin script runs out sooner than it looks like it should.
String? validateSsid(String value) =>
    utf8.encode(value).length > 32 ? 'At most 32 bytes long' : null;
