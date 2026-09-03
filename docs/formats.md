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

typedef QrFieldValidator = String? Function(String value);

class QrField {
  final String id;             // key into the values map
  final String label;
  final QrFieldType type;      // default: text
  final List<String>? options; // required when type == dropdown
  final bool required;         // gates QR rendering
  final String? hint;
  final QrFieldValidator? validate; // optional; also gates QR rendering
}
```

`fields` should be a `const` list — it is read on every rebuild. That is why `validate` has to be a top-level or static function rather than a closure: only those are constant expressions.

## Value encoding

Every value is a `String`, regardless of field type:

| Type | Stored as | Initial value |
| --- | --- | --- |
| `text` / `password` / `multiline` | the controller's text | `''` |
| `dropdown` | the selected option string | `options.first` |
| `checkbox` | `'true'` / `'false'` | `'false'` |

`buildQrString` is invoked on every keystroke and *before* required fields are satisfied, so read defensively: `values['x'] ?? ''`.

## Validation

A validator returns the message to show under the field, or null when the value is acceptable. Two rules govern when it runs:

- **It is never called with an empty string.** An empty field means "not filled in yet" — that is what `required` expresses. A form that flags every field the moment it opens is worse than one that waits until there is something to judge. `buildQrString` still has to tolerate empty values; nothing changed there.
- **Any error blocks the QR code**, including on an optional field. An optional field that is filled in *wrongly* would otherwise be encoded into the payload, which is exactly the case validation exists to catch.

The shared rules live in [lib/formats/validators.dart](../lib/formats/validators.dart) — `validateEmail`, `validateUrl`, `validatePhone`, `validateSsid` — because a vCard carries an email, a URL and a phone number, and they are the same things the dedicated formats encode. A rule that only one format could want belongs in that format as a `static` method instead.

They are deliberately loose. A validator's job is to reject what a scanner cannot use, not to enforce a spec: `validateEmail` accepts anything with an `@` and a dotted domain, since stricter patterns start refusing addresses that work. `validateUrl` is the one real judgement call — it insists on a scheme, because a bare `example.com` encodes as a scheme-less string and readers disagree about what to do with it.

## Supported formats

| id | Class | Payload |
| --- | --- | --- |
| `wifi` | [WifiFormat](../lib/formats/wifi_format.dart) | `WIFI:T:<WPA\|WEP\|nopass>;S:<ssid>;P:<pass>;H:<bool>;;` |
| `vcard` | [VCardFormat](../lib/formats/vcard_format.dart) | vCard 3.0, newline-joined, optional lines omitted when empty |
| `url` | [UrlFormat](../lib/formats/url_format.dart) | the raw URL |
| `email` | [EmailFormat](../lib/formats/email_format.dart) | `mailto:` with URI-encoded `subject`/`body`, `@` and `+` left literal in the address |
| `phone` | [PhoneFormat](../lib/formats/phone_format.dart) | `tel:<number>` |
| `text` | [TextFormat](../lib/formats/text_format.dart) | the text verbatim |

Escaping rules differ per spec and belong inside the format class:
- WiFi escapes `\ ; , " :` with a backslash (`WifiFormat._escape`).
- Email uses `Uri.encodeComponent` on the address and each query param, then restores `@` and `+` in the address — RFC 6068 allows both there, and `%2B` breaks plus-addressing in some clients. The query params keep the full encoding, where `+` can be read as a space.
- vCard emits `N:` and `FN:` lines; the rest are conditional. Every value is escaped per RFC 2426 (`\ ; ,` and line breaks), which is what keeps a multiline address from ending its own property.

## Adding a format

1. Create `lib/formats/<name>_format.dart` with a class extending `QrFormat`.
2. Declare `id`, `name`, a `const` `fields` list, and `buildQrString`.
3. Register it in `qrFormats` in [lib/formats/registry.dart](../lib/formats/registry.dart) — the list order is the dropdown order.
4. Add `test/formats/<name>_format_test.dart` covering the empty map, optional fields omitted when empty, and whatever escaping the spec calls for.

The contract tests read `qrFormats` directly, so step 3 enrols the format in them; there is no second list to keep in step.

No UI changes are needed — the screen imports the registry, not the formats. If a format genuinely needs a widget the five `QrFieldType` values cannot express, add the enum case *and* its branch in `_buildField`, plus its initial value in `_initControllers`; otherwise leave both alone.
