import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../formats/validators.dart';

/// [showDatePicker], with the date typed in its keyboard mode as `YYYY-MM-DD`, the
/// way a date field holds it, rather than the locale's `MM/DD/YYYY`.
Future<DateTime?> showIsoDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) => showDatePicker(
  context: context,
  initialDate: initialDate,
  firstDate: firstDate,
  lastDate: lastDate,
  builder: (context, child) => Localizations.override(
    context: context,
    delegates: const [_IsoDateLocalizations.delegate],
    child: child,
  ),
);

/// Lets a date field be typed as digits alone: the dashes of `YYYY-MM-DD` are put in
/// as the digits arrive, and whatever else is typed or pasted (`1985/04/12`) is
/// dropped, up to the eight digits a date has.
///
/// A dash goes in only once a digit follows it, so `1985` stays `1985` until the
/// month is begun and a backspace after the year is not undone. The cursor stays after
/// the same digit it was after, so an edit in the middle does not jump to the end.
class IsoDateInputFormatter extends TextInputFormatter {
  const IsoDateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text == oldValue.text) return newValue;
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final kept = digits.length > 8 ? digits.substring(0, 8) : digits;
    final text = format(kept);

    final cursor = newValue.selection.isValid
        ? newValue.selection.extentOffset.clamp(0, newValue.text.length)
        : newValue.text.length;
    final digitsBefore = newValue.text
        .substring(0, cursor)
        .replaceAll(RegExp(r'\D'), '')
        .length
        .clamp(0, kept.length);
    final offset = format(kept.substring(0, digitsBefore)).length;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  /// [digits] with the dashes a date has between its year, month and day.
  static String format(String digits) => switch (digits.length) {
    <= 4 => digits,
    <= 6 => '${digits.substring(0, 4)}-${digits.substring(4)}',
    _ =>
      '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6)}',
  };
}

class _IsoDateLocalizations extends DefaultMaterialLocalizations {
  const _IsoDateLocalizations();

  static const delegate = _IsoDateDelegate();

  @override
  String formatCompactDate(DateTime date) => formatIsoDate(date);

  @override
  DateTime? parseCompactDate(String? inputString) =>
      inputString == null ? null : parseIsoDate(inputString);

  @override
  String get dateHelpText => 'yyyy-mm-dd';
}

class _IsoDateDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const _IsoDateDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture(const _IsoDateLocalizations());

  @override
  bool shouldReload(_IsoDateDelegate old) => false;
}
