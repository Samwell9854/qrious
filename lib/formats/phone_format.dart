import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';

class PhoneFormat extends QrFormat {
  @override
  String get id => 'phone';

  @override
  String get name => 'Phone Number';

  @override
  QrFormatGroup get group => QrFormatGroup.message;

  @override
  IconData get icon => Icons.phone_outlined;

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'phone',
      label: 'Phone Number',
      required: true,
      hint: '+1 555 000 0000',
      validate: validatePhone,
    ),
  ];

  @override
  String buildQrString(Map<String, String> values) =>
      'tel:${values['phone'] ?? ''}';
}
