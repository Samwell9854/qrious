import 'qr_field.dart';

abstract class QrFormat {
  String get id;
  String get name;
  List<QrField> get fields;
  String buildQrString(Map<String, String> values);
}
