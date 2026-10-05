import 'package:flutter/widgets.dart' show IconData;

enum QrFieldType { text, password, multiline, dropdown, checkbox, group }

/// Judges one value, returning the message to show under the field or null when
/// the value is acceptable. Only ever called with a non-empty value — see
/// `lib/formats/validators.dart`.
typedef QrFieldValidator = String? Function(String value);

/// A label an entry of a [QrFieldType.group] can carry, such as a phone being
/// a mobile or a work number.
class QrKind {
  /// [value] is what the format reads back, such as `CELL`; [label] and [icon]
  /// are what the user sees.
  const QrKind(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;
}

class QrField {
  final String id;
  final String label;
  final QrFieldType type;
  final List<String>? options;
  final bool required;
  final String? hint;

  /// Optional. Must be a top-level or static function so `fields` stays `const`.
  final QrFieldValidator? validate;

  /// For a group: the fields one entry is made of. A single part is shown as one
  /// line; several are boxed together.
  final List<QrField>? parts;

  /// For a group: the kinds an entry can be, the first being the default for a
  /// new entry. Null when entries carry no kind.
  final List<QrKind>? kinds;

  const QrField({
    required this.id,
    required this.label,
    this.type = QrFieldType.text,
    this.options,
    this.required = false,
    this.hint,
    this.validate,
    this.parts,
    this.kinds,
  });
}

/// How a group's entries live in the flat values map: the group's own key holds
/// how many entries there are, and each entry's parts and kind sit under
/// `<group>.<index>.<part>` and `<group>.<index>.kind`.
abstract final class QrEntries {
  static String part(String group, int index, String part) =>
      '$group.$index.$part';

  static String kind(String group, int index) => '$group.$index.kind';

  static int count(Map<String, String> values, String group) =>
      int.tryParse(values[group] ?? '') ?? 0;

  /// Every entry of [group], each as its parts by id plus `kind`. Missing keys
  /// read as empty, like everywhere else in a format.
  static List<Map<String, String>> read(
    Map<String, String> values,
    QrField group,
  ) => [
    for (var i = 0; i < count(values, group.id); i++)
      {
        for (final p in group.parts!)
          p.id: values[part(group.id, i, p.id)] ?? '',
        'kind': values[kind(group.id, i)] ?? '',
      },
  ];
}
