import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';
import 'parsing.dart';

class EmailFormat extends QrFormat {
  @override
  String get id => 'email';

  @override
  String get name => 'Email';

  @override
  QrFormatGroup get group => QrFormatGroup.message;

  @override
  IconData get icon => Icons.email_outlined;

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'to',
      label: 'To',
      required: true,
      hint: 'recipient@example.com',
      validate: validateEmail,
    ),
    QrField(id: 'subject', label: 'Subject'),
    QrField(id: 'body', label: 'Body', type: QrFieldType.multiline),
  ];

  @override
  String buildQrString(Map<String, String> values) {
    // Uri.encodeComponent escapes everything a *query value* could need escaped,
    // which is right for subject and body but too much for the address. RFC 6068
    // allows @ and + literally in the addr-spec, and enough mail clients mishandle
    // %40 or %2B there to make it worth restoring them — plus-addressing is common.
    // The query parameters keep their full encoding, where + really can be read
    // as a space.
    final to = Uri.encodeComponent(
      values['to'] ?? '',
    ).replaceAll('%40', '@').replaceAll('%2B', '+');
    final params = <String>[];
    if ((values['subject'] ?? '').isNotEmpty) {
      params.add('subject=${Uri.encodeComponent(values['subject']!)}');
    }
    if ((values['body'] ?? '').isNotEmpty) {
      params.add('body=${Uri.encodeComponent(values['body']!)}');
    }
    return 'mailto:$to${params.isEmpty ? '' : '?${params.join('&')}'}';
  }

  @override
  QrParsed? parse(String payload) {
    if (!hasPrefixIgnoreCase(payload, 'mailto:')) return null;
    final rest = payload.substring(7);
    final query = rest.indexOf('?');
    final values = {
      'to': _decode(query < 0 ? rest : rest.substring(0, query)),
      'subject': '',
      'body': '',
    };
    final unsupported = <String>[];
    if (query >= 0) {
      for (final param in rest.substring(query + 1).split('&')) {
        if (param.isEmpty) continue;
        final equals = param.indexOf('=');
        final key = equals < 0 ? param : param.substring(0, equals);
        final value = equals < 0 ? '' : _decode(param.substring(equals + 1));
        // Other mailto headers (cc, bcc, ...) have no field.
        if (values.containsKey(key.toLowerCase()) &&
            key.toLowerCase() != 'to') {
          values[key.toLowerCase()] = value;
        } else {
          addOnce(unsupported, key);
        }
      }
    }
    return QrParsed(values, unsupported);
  }

  /// Undoes `Uri.encodeComponent`, keeping the text as it stands when it is not valid
  /// percent-encoding (which the decoder reports as an ArgumentError): a scanned code
  /// is whatever someone put in it.
  static String _decode(String s) {
    try {
      return Uri.decodeComponent(s);
    } on ArgumentError {
      return s;
    }
  }
}
