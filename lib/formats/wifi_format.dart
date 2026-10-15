import 'package:flutter/material.dart' show Icons, IconData;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'validators.dart';
import 'parsing.dart';

class WifiFormat extends QrFormat {
  @override
  String get id => 'wifi';

  @override
  String get name => 'Wi-Fi';

  @override
  QrFormatGroup get group => QrFormatGroup.connect;

  @override
  IconData get icon => Icons.wifi;

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

  /// Reads the `T`, `S`, `P` and `H` keys in any order. `T` values the form has no
  /// option for (`SAE`, `WPA2-EAP`) load as the closest option and are reported, as
  /// is any other key (`R`, `E`, ...).
  @override
  QrParsed? parse(String payload) {
    if (!hasPrefixIgnoreCase(payload, 'WIFI:')) return null;
    final props = <String, String>{};
    final unsupported = <String>[];
    for (final piece in splitUnescaped(payload.substring(5), ';')) {
      if (piece.isEmpty) continue;
      final colon = piece.indexOf(':');
      if (colon < 0) {
        addOnce(unsupported, piece);
        continue;
      }
      final key = piece.substring(0, colon);
      final value = unescapeBackslash(piece.substring(colon + 1));
      switch (key.toUpperCase()) {
        case 'T' || 'S' || 'P' || 'H':
          props[key.toUpperCase()] = value;
        default:
          addOnce(unsupported, key);
      }
    }
    final type = props['T'] ?? '';
    final security = switch (type.toUpperCase()) {
      'WPA' => 'WPA/WPA2',
      'WEP' => 'WEP',
      'NOPASS' || '' => 'None',
      _ => 'WPA/WPA2',
    };
    if (security == 'WPA/WPA2' && type.toUpperCase() != 'WPA') {
      addOnce(unsupported, 'T:$type');
    }
    return QrParsed({
      'ssid': props['S'] ?? '',
      'security': security,
      'password': props['P'] ?? '',
      'hidden': (props['H'] ?? '').toLowerCase() == 'true' ? 'true' : 'false',
    }, unsupported);
  }
}
