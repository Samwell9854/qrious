import 'package:flutter/material.dart';

/// A dropdown of [values] with Auto, which is null, in front of them.
///
/// A value the current code cannot take is shown but cannot be picked, with
/// [unavailable]'s reason after it, so that nothing impossible is offered and nobody
/// has to guess why.
class AutoDropdown<T extends Object> extends StatelessWidget {
  const AutoDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
    this.autoLabel = 'Auto',
    this.unavailable,
  });

  final String label;
  final T? value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T?> onChanged;

  /// How Auto reads, such as `Auto (default)` in settings.
  final String autoLabel;

  /// Why [value] cannot be picked now, or null when it can.
  final String? Function(T value)? unavailable;

  @override
  Widget build(BuildContext context) {
    // Auto is a value of its own here, so the dropdown's own null (nothing picked)
    // never arises: onChanged always gets a real choice.
    return DropdownButtonFormField<_Pick<T>>(
      // Keyed by the value so a default changed in settings shows here too:
      // initialValue is read only when the field is created.
      key: ValueKey(_Pick(value)),
      initialValue: _Pick(value),
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(
          value: _Pick<T>(null),
          child: Text(autoLabel, overflow: TextOverflow.ellipsis),
        ),
        for (final v in values)
          switch (unavailable?.call(v)) {
            null => DropdownMenuItem(
              value: _Pick(v),
              child: Text(labelOf(v), overflow: TextOverflow.ellipsis),
            ),
            final reason => DropdownMenuItem(
              value: _Pick(v),
              enabled: false,
              child: Text(
                '${labelOf(v)} · $reason',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).disabledColor),
              ),
            ),
          },
      ],
      // The menu lists every reason in full, but the closed field shows the plain
      // label: a pick that has since become impossible is said so in the caption.
      selectedItemBuilder: (context) => [
        Text(autoLabel, overflow: TextOverflow.ellipsis),
        for (final v in values)
          Text(labelOf(v), overflow: TextOverflow.ellipsis),
      ],
      onChanged: (pick) {
        if (pick != null) onChanged(pick.value);
      },
    );
  }
}

class _Pick<T> {
  const _Pick(this.value);

  final T? value;

  @override
  bool operator ==(Object other) => other is _Pick<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
