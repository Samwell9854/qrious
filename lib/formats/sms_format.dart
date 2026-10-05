import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';

class SmsFormat extends QrFormat {
  @override
  String get id => 'sms';

  @override
  String get name => 'Text Message (SMS)';

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
}
