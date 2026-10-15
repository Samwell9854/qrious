import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';
import 'parsing.dart';

class SmsFormat extends QrFormat {
  @override
  String get id => 'sms';

  @override
  String get name => 'Text Message (SMS)';

  @override
  QrFormatGroup get group => QrFormatGroup.message;

  @override
  IconData get icon => Icons.sms_outlined;

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'phone',
      label: 'Phone Number',
      required: true,
      hint: '+1 555 000 0000',
      validate: validatePhone,
    ),
    QrField(id: 'message', label: 'Message', type: QrFieldType.multiline),
  ];

  /// `SMSTO:<number>:<message>`, the form ZXing introduced and phone cameras read.
  /// Nothing in the message needs escaping: a reader splits at the first colon
  /// after the number, and the number cannot hold one.
  @override
  String buildQrString(Map<String, String> values) {
    final phone = (values['phone'] ?? '').trim();
    final message = values['message'] ?? '';
    return message.isEmpty ? 'SMSTO:$phone' : 'SMSTO:$phone:$message';
  }

  /// The number runs to the first colon, the message is everything after it.
  @override
  QrParsed? parse(String payload) {
    if (!hasPrefixIgnoreCase(payload, 'SMSTO:')) return null;
    final rest = payload.substring(6);
    final colon = rest.indexOf(':');
    return QrParsed({
      'phone': (colon < 0 ? rest : rest.substring(0, colon)).trim(),
      'message': colon < 0 ? '' : rest.substring(colon + 1),
    });
  }
}
