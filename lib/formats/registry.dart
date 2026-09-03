import '../models/qr_format.dart';
import 'email_format.dart';
import 'phone_format.dart';
import 'text_format.dart';
import 'url_format.dart';
import 'vcard_format.dart';
import 'wifi_format.dart';

/// Every format the app offers, in the order the picker lists them.
///
/// Registration lives here rather than on the screen so that adding a format is
/// a change to `lib/formats/` alone. The UI reads this list and knows nothing
/// about what is in it; the format contract tests read the same list, so a
/// format cannot be registered and left untested.
final List<QrFormat> qrFormats = List.unmodifiable([
  WifiFormat(),
  VCardFormat(),
  UrlFormat(),
  EmailFormat(),
  PhoneFormat(),
  TextFormat(),
]);
