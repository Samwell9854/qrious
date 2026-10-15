/// Reading a scanned payload back into the form, for importing a code.
///
/// The rule, decided with the product owner: each format except Text is asked in
/// registry order whether the payload is its own, and the first to claim it decides.
/// The payload lands in that format only when the form reproduces it exactly, which
/// takes all three of:
///
///  - the format rebuilds the identical payload from the values it read,
///  - it reports nothing unsupported, and
///  - no validator rejects a value that was read (a form that loads an error is no
///    use for editing, and the QR code would not render).
///
/// Otherwise the payload lands in Text, which keeps it byte for byte, and the claiming
/// format comes along as an offer: what its form would load, what it would drop, and
/// what it would reject, so the screen can let the user trade exactness for fields.
/// A payload nobody claims lands in Text with no offer.
///
/// Text, not the closest format, is the fallback because it is the only form that
/// cannot change a payload: a scanned code is rarely ours, and quietly rewriting it
/// (reordering Wi-Fi keys, dropping an `ORG`) would be a different code.
library;

import '../models/qr_field.dart';
import '../models/qr_format.dart';
import 'registry.dart';
import 'text_format.dart';

/// Where an imported payload lands.
class QrImportResult {
  const QrImportResult(this.format, this.values, [this.offer]);

  /// The claiming format when it is faithful, else the Text format.
  final QrFormat format;

  /// The values to load into [format]'s form.
  final Map<String, String> values;

  /// Set only when the payload landed in Text although a format claimed it.
  final QrImportOffer? offer;
}

/// A format that recognised a payload but cannot reproduce it exactly.
class QrImportOffer {
  const QrImportOffer(this.format, this.values, this.unsupported, this.invalid);

  final QrFormat format;

  /// What its form would load.
  final Map<String, String> values;

  /// The parts of the payload the form would drop, from [QrParsed.unsupported].
  final List<String> unsupported;

  /// `<field label>: <validator message>` for each value the form would reject.
  final List<String> invalid;
}

/// Decides where [payload] lands among [formats]; see the library comment. [formats]
/// must hold a [TextFormat].
QrImportResult importPayload(String payload, [List<QrFormat>? formats]) {
  // Null rather than `= qrFormats`: the registry is final, not const, and a default
  // value has to be const.
  formats ??= qrFormats;
  final text = formats.whereType<TextFormat>().first;
  final textValues = {TextFormat.fieldId: payload};

  for (final format in formats) {
    if (format is TextFormat) continue;
    final parsed = format.parse(payload);
    if (parsed == null) continue;

    final invalid = _invalid(format, parsed.values);
    final faithful =
        parsed.unsupported.isEmpty &&
        invalid.isEmpty &&
        format.buildQrString(parsed.values) == payload;
    if (faithful) return QrImportResult(format, parsed.values);
    return QrImportResult(
      text,
      textValues,
      QrImportOffer(format, parsed.values, parsed.unsupported, invalid),
    );
  }
  return QrImportResult(text, textValues);
}

/// The validator messages [values] would raise in [format]'s form, each led by the
/// label of the field it is under. Validators never see an empty value.
List<String> _invalid(QrFormat format, Map<String, String> values) {
  final messages = <String>[];
  void check(QrField field, String? value) {
    if (value == null || value.isEmpty) return;
    final message = field.validate?.call(value);
    if (message != null) messages.add('${field.label}: $message');
  }

  for (final field in format.fields) {
    if (field.type != QrFieldType.group) {
      check(field, values[field.id]);
      continue;
    }
    for (var i = 0; i < QrEntries.count(values, field.id); i++) {
      for (final part in field.parts!) {
        check(part, values[QrEntries.part(field.id, i, part.id)]);
      }
    }
  }
  return messages;
}
