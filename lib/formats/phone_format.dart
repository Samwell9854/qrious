import '../models/qr_field.dart';
import '../models/qr_format.dart';

class PhoneFormat extends QrFormat {
  @override
  String get id => 'phone';

  @override
  String get name => 'Phone Number';

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'phone',
      label: 'Phone Number',
      required: true,
      hint: '+1 555 000 0000',
    ),
  ];

  @override
  String buildQrString(Map<String, String> values) =>
      'tel:${values['phone'] ?? ''}';
}
