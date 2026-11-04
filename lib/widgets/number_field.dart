import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A whole number from [min] to [max], typed. A keystroke that would leave the range
/// is refused, so the field never holds a value that cannot be used; its range is
/// shown under it so that the refusal is no surprise.
///
/// An emptied field changes nothing, so a number can be retyped from scratch, and it
/// shows [value] again once it loses focus.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  /// Shown under the field after the range, as in `1–177 · default 8`.
  final String? helper;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final _controller = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _show(widget.value);
    });
  }

  /// A value changed from outside, such as a default picked in settings or a reset,
  /// shows here. While the field is typed in, only a change that did not come from
  /// the typing, which always leaves the text and the value agreeing.
  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    final typed = int.tryParse(_controller.text);
    if (!_focus.hasFocus ||
        (widget.value != old.value && typed != widget.value)) {
      _show(widget.value);
    }
  }

  void _show(int value) {
    if (_controller.text != '$value') _controller.text = '$value';
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final range = '${widget.min}–${widget.max}';
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        TextInputFormatter.withFunction((old, next) {
          if (next.text.isEmpty) return next;
          final n = int.tryParse(next.text);
          // Above the range is refused at once. Below it is let through only while
          // more digits could still bring it up, which a leading zero cannot.
          if (n == null || n > widget.max) return old;
          if (n < widget.min && (n == 0 || n * 10 > widget.max)) return old;
          return next;
        }),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: switch (widget.helper) {
          null => range,
          final helper => '$range · $helper',
        },
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
      onChanged: (text) {
        final n = int.tryParse(text);
        if (n != null && n >= widget.min && n <= widget.max) {
          widget.onChanged(n);
        }
      },
    );
  }
}
