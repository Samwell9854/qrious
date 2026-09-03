enum QrFieldType { text, password, multiline, dropdown, checkbox }

/// Judges one value, returning the message to show under the field or null when
/// the value is acceptable. Only ever called with a non-empty value — see
/// `lib/formats/validators.dart`.
typedef QrFieldValidator = String? Function(String value);

class QrField {
  final String id;
  final String label;
  final QrFieldType type;
  final List<String>? options;
  final bool required;
  final String? hint;

  /// Optional. Must be a top-level or static function so `fields` stays `const`.
  final QrFieldValidator? validate;

  const QrField({
    required this.id,
    required this.label,
    this.type = QrFieldType.text,
    this.options,
    this.required = false,
    this.hint,
    this.validate,
  });
}
