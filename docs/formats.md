# The format system

## Contract

[lib/models/qr_format.dart](../lib/models/qr_format.dart):

```dart
abstract class QrFormat {
  String get id;                 // stable slug, e.g. 'wifi'
  String get name;               // label shown in the format dropdown
  List<QrField> get fields;      // declarative form description
  String buildQrString(Map<String, String> values);
}
```

[lib/models/qr_field.dart](../lib/models/qr_field.dart):

```dart
enum QrFieldType { text, password, multiline, dropdown, checkbox }

class QrField {
  final String id;           // key into the values map
  final String label;
  final QrFieldType type;    // default: text
  final List<String>? options; // required when type == dropdown
  final bool required;       // gates QR rendering
  final String? hint;
}
```

`fields` should be a `const` list — it is read on every rebuild.

## Value encoding

Every value is a `String`, regardless of field type:

| Type | Stored as | Initial value |
| --- | --- | --- |
| `text` / `password` / `multiline` | the controller's text | `''` |
| `dropdown` | the selected option string | `options.first` |
| `checkbox` | `'true'` / `'false'` | `'false'` |

`buildQrString` is invoked on every keystroke and *before* required fields are satisfied, so read defensively: `values['x'] ?? ''`.

## Supported formats

| id | Class | Payload |
| --- | --- | --- |
| `wifi` | [WifiFormat](../lib/formats/wifi_format.dart) | `WIFI:T:<WPA\|WEP\|nopass>;S:<ssid>;P:<pass>;H:<bool>;;` |
| `vcard` | [VCardFormat](../lib/formats/vcard_format.dart) | vCard 3.0, newline-joined, optional lines omitted when empty |
| `url` | [UrlFormat](../lib/formats/url_format.dart) | the raw URL |
| `email` | [EmailFormat](../lib/formats/email_format.dart) | `mailto:` with URI-encoded `subject`/`body` |
| `phone` | [PhoneFormat](../lib/formats/phone_format.dart) | `tel:<number>` |
| `text` | [TextFormat](../lib/formats/text_format.dart) | the text verbatim |

Escaping rules differ per spec and belong inside the format class:
- WiFi escapes `\ ; , " :` with a backslash (`WifiFormat._escape`).
- Email uses `Uri.encodeComponent` on the address and each query param.
- vCard emits `N:` and `FN:` lines; the rest are conditional.

## Adding a format

1. Create `lib/formats/<name>_format.dart` with a class extending `QrFormat`.
2. Declare `id`, `name`, a `const` `fields` list, and `buildQrString`.
3. Register it in `_formats` in [lib/screens/home_screen.dart](../lib/screens/home_screen.dart) — the list order is the dropdown order.
4. Add `test/formats/<name>_format_test.dart` covering the empty map, optional fields omitted when empty, and whatever escaping the spec calls for.
5. Add it to `formats` in [test/formats/format_contract_test.dart](../test/formats/format_contract_test.dart) so the shared contract checks cover it too.

No UI changes are needed. If a format genuinely needs a widget the five `QrFieldType` values cannot express, add the enum case *and* its branch in `_buildField`, plus its initial value in `_initControllers`; otherwise leave both alone.
