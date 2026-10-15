# The format system

## Contract

[lib/models/qr_format.dart](../lib/models/qr_format.dart):

```dart
abstract class QrFormat {
  String get id;                 // stable slug, e.g. 'wifi'
  String get name;               // label shown in the format dropdown
  IconData get icon;             // shown beside the name in the dropdown
  QrFormatGroup get group;       // the heading it is listed under
  List<QrField> get fields;      // declarative form description
  String buildQrString(Map<String, String> values);
}
```

[lib/models/qr_field.dart](../lib/models/qr_field.dart):

```dart
enum QrFieldType { text, password, multiline, dropdown, checkbox, group }

typedef QrFieldValidator = String? Function(String value);

class QrField {
  final String id;             // key into the values map
  final String label;
  final QrFieldType type;      // default: text
  final List<String>? options; // required when type == dropdown
  final bool required;         // gates QR rendering
  final String? hint;
  final QrFieldValidator? validate; // optional; also gates QR rendering
  final List<QrField>? parts;  // group only: the fields one entry is made of
  final List<QrKind>? kinds;   // group only: what an entry can be labelled as
}

class QrKind {
  final String value;          // what the format reads back, e.g. 'CELL'
  final String label;          // what the user sees, e.g. 'Mobile'
  final IconData icon;
}
```

A **group** is a field the user can repeat: none at first, an *Add* button for another, and a remove button on each. A vCard's phones, emails and addresses are groups, so a contact can have none or several of each, two work emails included. A group with one part shows each entry as one line, with the kind as an icon menu inside the field and named again in its label (`Phone · Mobile`); a group with several parts boxes each entry, with the kind in a notch of the box's top edge. There is no cap on entries: the QR code's own capacity is the limit, and says so.

`fields` should be a `const` list — it is read on every rebuild. That is why `validate` has to be a top-level or static function rather than a closure: only those are constant expressions.

## Groups

The picker lists formats under headings for what scanning the code does, because that is how people choose: "I want them to join my Wi-Fi", not "I want a `WIFI:` payload". `QrFormatGroup` holds the headings in order: *Connect*, *Contact*, *Call or message*, *Web & maps*, *Show text*. A heading with no format is not shown, so a new group can be added before its first format lands. The planned ones are *Add to calendar* for events and *Pay* for cryptocurrency.

A code type other than QR (Data Matrix, Aztec, PDF417) would be an output option, not a group: it changes how the content is drawn, not what it is. 1D product barcodes, which carry only a number, would be a group of their own. See [#17](https://github.com/Samwell9854/qrious/issues/17).

## Value encoding

Every value is a `String`, regardless of field type:

| Type | Stored as | Initial value |
| --- | --- | --- |
| `text` / `password` / `multiline` | the controller's text | `''` |
| `dropdown` | the selected option string | `options.first` |
| `checkbox` | `'true'` / `'false'` | `'false'` |
| `group` | the number of entries, with each entry's parts under `<group>.<i>.<part>` and its kind under `<group>.<i>.kind` | `'0'` |

Read a group back with `QrEntries.read(values, group)`, which returns each entry as its parts by id plus `kind`, empty where a key is missing. Skip an entry whose parts are all empty: an *Add* pressed and left blank should not put an empty line in the payload.

`buildQrString` is invoked on every keystroke and *before* required fields are satisfied, so read defensively: `values['x'] ?? ''`.

## Validation

A validator returns the message to show under the field, or null when the value is acceptable. Two rules govern when it runs:

- **It is never called with an empty string.** An empty field means "not filled in yet" — that is what `required` expresses. A form that flags every field the moment it opens is worse than one that waits until there is something to judge. `buildQrString` still has to tolerate empty values; nothing changed there.
- **Any error blocks the QR code**, including on an optional field. An optional field that is filled in *wrongly* would otherwise be encoded into the payload, which is exactly the case validation exists to catch.

The shared rules live in [lib/formats/validators.dart](../lib/formats/validators.dart) — `validateEmail`, `validateUrl`, `validatePhone`, `validateSsid` — because a vCard carries an email, a URL and a phone number, and they are the same things the dedicated formats encode. A rule that only one format could want belongs in that format as a `static` method instead.

They are deliberately loose. A validator's job is to reject what a scanner cannot use, not to enforce a spec: `validateEmail` accepts anything with an `@` and a dotted domain, since stricter patterns start refusing addresses that work. `validateUrl` is the one real judgement call — it insists on a scheme, because a bare `example.com` encodes as a scheme-less string and readers disagree about what to do with it. `validatePhone` lets through the dialling marks as well as the separators: `,` (a pause) for an extension like `+15145550000,274`, and `*` and `#` for service codes. It refuses `;` (a wait), which is the property separator in MeCard and starts a parameter in a `tel:` URI; generators drop it and everything after it.

Both contact formats take the address as separate parts, from the shared `addressFields` in [lib/formats/address.dart](../lib/formats/address.dart): street, city, province or state, postal code, country. Each fills its own slot of `ADR`. A single free-text address put the whole thing in the street slot and left the phone to guess where the city began, which the iPhone camera got wrong on a hyphenated street name.

## Testing against real readers

The unit tests check payloads against the specs; what a phone does with them is a separate question, and readers differ. Scan results recorded in these docs and in code comments come from the **iPhone camera app**, the reader most people will try first. It reads vCard faithfully, `ADR` components included; it does not undo MeCard's backslash escapes; and it guesses at the parts of a one-line address. Where a reader and a spec disagree, follow the spec unless the reader's behaviour breaks something the user can see, and record which reader it was.

## Supported formats

| id | Class | Payload |
| --- | --- | --- |
| `wifi` | [WifiFormat](../lib/formats/wifi_format.dart) | `WIFI:T:<WPA\|WEP\|nopass>;S:<ssid>;P:<pass>;H:<bool>;;` |
| `vcard` | [VCardFormat](../lib/formats/vcard_format.dart) | vCard 3.0, newline-joined, optional lines omitted when empty |
| `mecard` | [MeCardFormat](../lib/formats/mecard_format.dart) | `MECARD:N:<last>,<first>;TEL:…;EMAIL:…;URL:…;ADR:,,<street>,<city>,<region>,<postal code>,<country>;;`, optional properties omitted when empty |
| `url` | [UrlFormat](../lib/formats/url_format.dart) | the raw URL |
| `email` | [EmailFormat](../lib/formats/email_format.dart) | `mailto:` with URI-encoded `subject`/`body`, `@` and `+` left literal in the address |
| `phone` | [PhoneFormat](../lib/formats/phone_format.dart) | `tel:<number>` |
| `sms` | [SmsFormat](../lib/formats/sms_format.dart) | `SMSTO:<number>:<message>`, or `SMSTO:<number>` with no message |
| `geo` | [GeoFormat](../lib/formats/geo_format.dart) | `geo:<lat>,<lon>` in decimal degrees (RFC 5870) |
| `text` | [TextFormat](../lib/formats/text_format.dart) | the text verbatim |

Escaping rules differ per spec and belong inside the format class:
- Wi-Fi escapes `\ ; , " :` with a backslash (`WifiFormat._escape`).
- Email uses `Uri.encodeComponent` on the address and each query param, then restores `@` and `+` in the address — RFC 6068 allows both there, and `%2B` breaks plus-addressing in some clients. The query params keep the full encoding, where `+` can be read as a space.
- MeCard backslash-escapes `\` and `;` in every value, `,` only inside `N:` and `ADR:` where it separates components, and turns line breaks into spaces, since it has no escape for one. The spec escapes `:` and every `,` too, but the iPhone camera does not undo it, and turned `https://` into `https\://` in testing, and neither is ambiguous where it is left alone. MeCard carries no organisation or job title, which is the price of its smaller code.
- SMS escapes nothing: a reader splits at the first colon after the number, which cannot hold one.
- Location validates instead of escaping: decimal degrees with a point, within ±90 and ±180, which is all `geo:` accepts.
- vCard emits `N:` and `FN:` lines; the rest are conditional. Every text value is escaped per RFC 2426 (`\ ; ,` and line breaks), which is what keeps a pasted line break from ending its own property. `TEL` is not text and is left as typed, so a pause's `,` does not arrive with a backslash in front of it. Each phone, email and address is its own line, and its kind becomes a `TYPE=` parameter (`TEL;TYPE=CELL:…`, `EMAIL;TYPE=WORK:…`, `ADR;TYPE=HOME:…`); *Other* leaves it off. The kinds are a beginner set from RFC 2426: phone Mobile, Home, Work, Fax, Other; email Home, Work, Other; address Home, Work. MeCard has no types, so it keeps a single phone, email and address. A vCard phone also takes `;` (a wait), through `validatePhoneWithWait`: a vCard property ends at a line break, so the `;` is no separator there, and the iPhone camera keeps it.

## Adding a format

1. Create `lib/formats/<name>_format.dart` with a class extending `QrFormat`.
2. Declare `id`, `name`, `icon` (a Material `Icons` constant), `group`, a `const` `fields` list, and `buildQrString`.
3. Register it in `qrFormats` in [lib/formats/registry.dart](../lib/formats/registry.dart), beside the other formats of its group: the picker lists groups in `QrFormatGroup` order, and formats in registry order within each.
4. Add `test/formats/<name>_format_test.dart` covering the empty map, optional fields omitted when empty, and whatever escaping the spec calls for.

The contract tests read `qrFormats` directly, so step 3 enrols the format in them; there is no second list to keep in step.

No UI changes are needed — the screen imports the registry, not the formats. If a format genuinely needs a widget the six `QrFieldType` values cannot express, add the enum case *and* its branch in `_buildField`, plus its initial value in `_loadForm` and its default in `_hasInput`; otherwise leave them alone.
