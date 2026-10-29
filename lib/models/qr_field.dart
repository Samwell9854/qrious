import 'package:flutter/widgets.dart' show IconData;

enum QrFieldType { text, password, multiline, dropdown, checkbox, group, date }

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

  /// For a group: the kinds expert mode offers beyond [kinds].
  final List<QrKind> expertKinds;

  /// For a group: whether expert mode lets an entry be several kinds at once, stored
  /// comma-joined (`WORK,VOICE`). A kind whose value is empty means "none of them".
  final bool multipleKinds;

  /// Shown, and written into the payload, only in expert mode. In beginner mode its
  /// value is kept but not applied, so it is there again when expert mode is.
  final bool expert;

  /// Shown, and written into the payload, only while another field holds a value,
  /// such as the extra recipients of an SMS only in the form that can carry them.
  final ({String field, String value})? showWhen;

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
    this.expertKinds = const [],
    this.multipleKinds = false,
    this.expert = false,
    this.showWhen,
  });

  /// Every kind an entry can be in expert mode or beginner mode.
  List<QrKind> kindsFor({required bool expert}) =>
      expert ? [...?kinds, ...expertKinds] : [...?kinds];
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

/// What a form shows and writes in each mode. Formats declare their expert fields and
/// kinds and never ask which mode is on: the screen and the importer pass their values
/// through [applied] first.
abstract final class QrForm {
  /// The fields shown, and written, in this mode with [values], in order.
  ///
  /// A field shown only when another holds a value looks at that value as the mode
  /// writes it, so a choice expert mode made does not show its fields in beginner
  /// mode. That field must therefore come earlier in [fields].
  static List<QrField> shown(
    List<QrField> fields,
    Map<String, String> values, {
    required bool expert,
  }) {
    final hidden = <String>{};
    final result = <QrField>[];
    for (final field in fields) {
      final visible =
          (expert || !field.expert) &&
          switch (field.showWhen) {
            null => true,
            final condition =>
              !hidden.contains(condition.field) &&
                  values[condition.field] == condition.value,
          };
      if (visible) {
        result.add(field);
      } else {
        hidden.add(field.id);
      }
    }
    return result;
  }

  /// [values] as this mode writes them: what is not shown is left out, and in
  /// beginner mode each group entry's kind is brought to a beginner one, the first
  /// of its kinds that is one, else the group's no-type kind.
  static Map<String, String> applied(
    List<QrField> fields,
    Map<String, String> values, {
    required bool expert,
  }) {
    final result = Map.of(values);
    final visible = shown(fields, values, expert: expert);
    for (final field in fields) {
      if (!visible.contains(field)) {
        result.removeWhere((key, _) => _belongsTo(key, field));
        continue;
      }
      if (expert || field.kinds == null) continue;
      for (var i = 0; i < QrEntries.count(values, field.id); i++) {
        final key = QrEntries.kind(field.id, i);
        result[key] = beginnerKind(field, values[key] ?? '');
      }
    }
    return result;
  }

  /// [kind], one or several comma-joined, as the beginner kind it reads as.
  static String beginnerKind(QrField group, String kind) {
    final offered = [for (final k in group.kinds!) k.value];
    if (offered.contains(kind)) return kind;
    for (final part in kind.split(',')) {
      if (part.isNotEmpty && offered.contains(part)) return part;
    }
    return offered.contains('') ? '' : offered.first;
  }

  /// What [values] hold that beginner mode does not write, named for the user: the
  /// label of each field whose value it would leave out, or `<label> type` for a
  /// group whose entries only lose a kind. Empty when beginner mode writes it all.
  static List<String> expertOnly(
    List<QrField> fields,
    Map<String, String> values,
  ) {
    final beginner = applied(fields, values, expert: false);
    final expert = applied(fields, values, expert: true);
    // A key beginner mode leaves out stands for its empty value: 0 for a group's
    // count, nothing for anything else.
    String lost(String key, QrField field) =>
        beginner[key] ??
        (key == field.id && field.type == QrFieldType.group ? '0' : '');
    return [
      for (final field in fields)
        if ([
              for (final MapEntry(:key, :value) in expert.entries)
                if (_belongsTo(key, field) && value != lost(key, field)) key,
            ]
            case final keys when keys.isNotEmpty)
          keys.every((key) => key.endsWith('.kind'))
              ? '${field.label} type'
              : field.label,
    ];
  }

  /// Whether [key] holds [field]'s value or, for a group, one of its entries'.
  static bool _belongsTo(String key, QrField field) =>
      key == field.id || key.startsWith('${field.id}.');
}
