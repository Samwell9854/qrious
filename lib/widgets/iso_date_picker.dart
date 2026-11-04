import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
