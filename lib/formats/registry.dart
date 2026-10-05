import '../models/qr_format.dart';
import 'email_format.dart';
import 'geo_format.dart';
import 'mecard_format.dart';
import 'phone_format.dart';
import 'sms_format.dart';
import 'text_format.dart';
import 'url_format.dart';
import 'vcard_format.dart';
import 'wifi_format.dart';

/// Every format the app offers. The picker lists them under their groups, in
/// [QrFormatGroup] order, and in this order within a group; the first is the
/// format the app opens on.
///
/// Registration lives here rather than on the screen so that adding a format is
/// a change to `lib/formats/` alone. The UI reads this list and knows nothing
/// about what is in it; the format contract tests read the same list, so a
/// format cannot be registered and left untested.
final List<QrFormat> qrFormats = List.unmodifiable([
  WifiFormat(),
  VCardFormat(),
  MeCardFormat(),
  PhoneFormat(),
  SmsFormat(),
  EmailFormat(),
  UrlFormat(),
  GeoFormat(),
  TextFormat(),
]);

/// [qrFormats] by group, in the order the picker shows them, leaving out groups
/// with no format yet.
List<(QrFormatGroup, List<QrFormat>)> get qrFormatsByGroup => [
  for (final group in QrFormatGroup.values)
    if (qrFormats.where((f) => f.group == group).toList() case final formats
        when formats.isNotEmpty)
      (group, formats),
];
