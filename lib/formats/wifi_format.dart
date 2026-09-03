import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';

class WifiFormat extends QrFormat {
  @override
  String get id => 'wifi';

  @override
  String get name => 'WiFi';

  @override
  List<QrField> get fields => const [
    QrField(
      id: 'ssid',
      label: 'Network Name (SSID)',
      required: true,
      hint: 'MyNetwork',
      validate: validateSsid,
    ),
    QrField(
      id: 'security',
      label: 'Security Type',
      type: QrFieldType.dropdown,
      options: ['WPA/WPA2', 'WEP', 'None'],
      required: true,
    ),
    QrField(
      id: 'password',
      label: 'Password',
      type: QrFieldType.password,
      hint: 'Leave empty for open networks',
    ),
    QrField(id: 'hidden', label: 'Hidden Network', type: QrFieldType.checkbox),
  ];

  @override
  String buildQrString(Map<String, String> values) {
    final ssid = _escape(values['ssid'] ?? '');
    final password = _escape(values['password'] ?? '');
    final security = switch (values['security']) {
      'WEP' => 'WEP',
      'None' => 'nopass',
      _ => 'WPA',
    };
    final hidden = values['hidden'] == 'true' ? 'true' : 'false';
    return 'WIFI:T:$security;S:$ssid;P:$password;H:$hidden;;';
  }

  String _escape(String s) =>
      s.replaceAllMapped(RegExp(r'([\\;,":])'), (m) => '\\${m[0]}');
}
