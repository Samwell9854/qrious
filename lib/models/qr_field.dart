enum QrFieldType { text, password, multiline, dropdown, checkbox }

class QrField {
  final String id;
  final String label;
  final QrFieldType type;
  final List<String>? options;
  final bool required;
  final String? hint;

  const QrField({
    required this.id,
    required this.label,
    this.type = QrFieldType.text,
    this.options,
    this.required = false,
    this.hint,
  });
}
