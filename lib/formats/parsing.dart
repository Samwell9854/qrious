/// Helpers for reading a payload back into a format's values, the inverse of the
/// escaping each `buildQrString` does. Shared by the formats that have a backslash
/// escape: Wi-Fi, vCard and MeCard.
library;

import '../models/qr_field.dart';

/// Whether [s] starts with [prefix], ignoring case. Schemes and tags are case
/// insensitive, so `wifi:` and `Mailto:` are as good as the canonical spelling.
bool hasPrefixIgnoreCase(String s, String prefix) =>
    s.length >= prefix.length &&
    s.substring(0, prefix.length).toLowerCase() == prefix.toLowerCase();

/// Splits [s] at each [separator] (one character) that is not escaped by a
/// backslash. The pieces keep their escapes, so a caller can split on a second
/// separator before unescaping.
List<String> splitUnescaped(String s, String separator) {
  final pieces = <String>[];
  final current = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      current
        ..write(c)
        ..write(s[++i]);
    } else if (c == separator) {
      pieces.add(current.toString());
      current.clear();
    } else {
      current.write(c);
    }
  }
  pieces.add(current.toString());
  return pieces;
}

/// Drops the backslash from each escaped character. A trailing lone backslash has
/// nothing to escape and stays.
String unescapeBackslash(String s) =>
    s.replaceAllMapped(RegExp(r'\\(.)', dotAll: true), (m) => m[1]!);

/// Adds [item] unless it is there already, so a part repeated in a payload is
/// named once in the notice.
void addOnce(List<String> list, String item) {
  if (!list.contains(item)) list.add(item);
}

/// Writes [entries] into [values] as the group [group] holds them: the count under
/// the group's own key, and each entry's parts and `kind` under `<group>.<i>.<part>`.
void putEntries(
  Map<String, String> values,
  String group,
  List<Map<String, String>> entries,
) {
  values[group] = '${entries.length}';
  for (var i = 0; i < entries.length; i++) {
    for (final e in entries[i].entries) {
      values[QrEntries.part(group, i, e.key)] = e.value;
    }
  }
}
