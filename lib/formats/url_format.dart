import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';
import 'parsing.dart';

class UrlFormat extends QrFormat {
  @override
  String get id => 'url';

  @override
  String get name => 'URL / Website';

  @override
  QrFormatGroup get group => QrFormatGroup.web;

  @override
  IconData get icon => Icons.link;

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'url',
      label: 'URL',
      required: true,
      hint: 'https://example.com',
      validate: validateUrl,
    ),
  ];

  @override
  String buildQrString(Map<String, String> values) => values['url'] ?? '';

  /// Only a web address: any other scheme (`geo:`, `mailto:`) belongs to a format
  /// of its own or to plain text, and a URL form would mangle it.
  @override
  QrParsed? parse(String payload) =>
      hasPrefixIgnoreCase(payload, 'http://') ||
          hasPrefixIgnoreCase(payload, 'https://')
      ? QrParsed({'url': payload})
      : null;
}
