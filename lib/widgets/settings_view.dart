import 'package:flutter/material.dart';

import '../qr_encoding.dart';
import '../qr_export.dart';
import '../qr_png.dart';
import '../settings.dart';

/// Below this width settings take the whole screen instead of floating over it. The
/// same breakpoint as the home screen's layouts.
const double _dialogBreakpoint = 700;

/// Shows the settings. Every change is handed to [onChanged] as it is made, as KDE's
/// and GNOME's settings do, so there is nothing to confirm or cancel.
Future<void> showSettings(
  BuildContext context, {
  required Settings settings,
  required ValueChanged<Settings> onChanged,
}) {
  if (MediaQuery.sizeOf(context).width >= _dialogBreakpoint) {
    return showDialog<void>(
      context: context,
      builder: (_) => SettingsView(settings: settings, onChanged: onChanged),
    );
  }
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => SettingsView(
        settings: settings,
        onChanged: onChanged,
        fullScreen: true,
      ),
    ),
  );
}

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.settings,
    required this.onChanged,
    this.fullScreen = false,
  });

  final Settings settings;
  final ValueChanged<Settings> onChanged;

  /// A page of its own rather than a dialog, for a narrow window.
  final bool fullScreen;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late Settings _settings = widget.settings;

  void _change(Settings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  /// Marks the choice the app starts with when nothing was saved, so it can be picked
  /// again on its own without resetting the rest.
  static String _marked(String label, bool isDefault) =>
      isDefault ? '$label (default)' : label;

  static const _defaults = Settings();

  void _reset() => _change(_defaults);

  Widget _buildResetButton() => TextButton(
    onPressed: _settings == _defaults ? null : _reset,
    child: const Text('Reset to defaults'),
  );

  Widget _buildFields() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Every new code starts with these. The choices beside the code still '
          'change it on its own.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        // Each keyed by its value so a reset shows: initialValue is read only when a
        // field is created.
        DropdownButtonFormField<ErrorCorrection>(
          key: ValueKey(_settings.errorCorrection),
          initialValue: _settings.errorCorrection,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Error correction',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final level in ErrorCorrection.values)
              DropdownMenuItem(
                value: level,
                child: Text(
                  _marked(switch (level.recoveryPercent) {
                    null => level.label,
                    final percent => '${level.label} ($percent%)',
                  }, level == _defaults.errorCorrection),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (level) {
            if (level != null) {
              _change(_settings.copyWith(errorCorrection: level));
            }
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<ImageSize>(
          key: ValueKey(_settings.imageSize),
          initialValue: _settings.imageSize,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Image size',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final size in ImageSize.values)
              DropdownMenuItem(
                value: size,
                child: Text(
                  _marked(size.label, size == _defaults.imageSize),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (size) {
            if (size != null) _change(_settings.copyWith(imageSize: size));
          },
        ),
        const SizedBox(height: 16),
        // Null is "Ask each time", a value of its own here, so the dropdown's own
        // null (nothing picked) never arises: onChanged always gets a real choice.
        DropdownButtonFormField<_SaveChoice>(
          key: ValueKey(_SaveChoice(_settings.saveFileType)),
          initialValue: _SaveChoice(_settings.saveFileType),
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Save as',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final type in [null, ...ExportFileType.values])
              DropdownMenuItem(
                value: _SaveChoice(type),
                child: Text(
                  _marked(
                    type == null ? 'Ask each time' : 'Always ${type.label}',
                    type == _defaults.saveFileType,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (choice) {
            if (choice != null) {
              _change(_settings.copyWith(saveFileType: () => choice.type));
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fullScreen) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          actions: [_buildResetButton(), const SizedBox(width: 8)],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildFields(),
          ),
        ),
      );
    }
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(child: _buildFields()),
      ),
      actions: [
        _buildResetButton(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// A save file type, or null for asking each time, as one dropdown value.
class _SaveChoice {
  const _SaveChoice(this.type);

  final ExportFileType? type;

  @override
  bool operator ==(Object other) => other is _SaveChoice && other.type == type;

  @override
  int get hashCode => type.hashCode;
}
