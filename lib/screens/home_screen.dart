import 'package:flutter/material.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../formats/registry.dart';
import '../models/qr_field.dart';
import '../models/qr_format.dart';
import '../image_clipboard.dart';
import '../qr_encoding.dart';
import '../qr_png.dart';
import '../save_location.dart';
import '../widgets/app_title.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.pickSaveLocation, this.copyImage});

  /// Injectable for tests; the real save dialog when null.
  final SaveLocationPicker? pickSaveLocation;

  /// Injectable for tests; the real clipboard when null.
  final PngClipboardCopier? copyImage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late QrFormat _selectedFormat;
  final Map<String, String> _values = {};
  final Map<String, TextEditingController> _controllers = {};

  // Not reset on a format switch: they describe the output, not the content.
  ErrorCorrection _errorCorrection = ErrorCorrection.auto;
  ImageSize _imageSize = ImageSize.medium;

  @override
  void initState() {
    super.initState();
    _selectedFormat = qrFormats.first;
    _initControllers();
  }

  void _initControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _values.clear();

    for (final field in _selectedFormat.fields) {
      switch (field.type) {
        case QrFieldType.dropdown:
          _values[field.id] = field.options!.first;
        case QrFieldType.checkbox:
          _values[field.id] = 'false';
        default:
          _values[field.id] = '';
          final controller = TextEditingController();
          controller.addListener(() {
            setState(() => _values[field.id] = controller.text);
          });
          _controllers[field.id] = controller;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String get _qrString => _selectedFormat.buildQrString(_values);

  /// The message to show under [field], or null when there is nothing to say.
  ///
  /// An empty value is never an error here: `required` already covers "you have
  /// not filled this in", and a form that opens with every field flagged red is
  /// worse than one that waits until there is something to judge.
  String? _errorFor(QrField field) {
    final value = _values[field.id] ?? '';
    if (value.isEmpty) return null;
    return field.validate?.call(value);
  }

  /// [qrString] encoded at the chosen error correction, or null when it is too
  /// long for the largest symbol at that level.
  EncodedQr? _encode(String qrString) {
    try {
      return encodeQr(qrString, _errorCorrection);
    } on InputTooLongException {
      return null;
    }
  }

  bool get _isReady {
    for (final field in _selectedFormat.fields) {
      if (field.required && (_values[field.id] ?? '').isEmpty) return false;
      if (_errorFor(field) != null) return false;
    }
    return true;
  }

  /// Below this width the two-column layout stacks into one scrolling column.
  static const double _wideLayoutBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(), centerTitle: false),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _wideLayoutBreakpoint;
            final padding = EdgeInsets.all(wide ? 24 : 16);
            return Padding(
              padding: padding,
              child: wide
                  ? _buildWideLayout()
                  : _buildNarrowLayout(
                      constraints.maxWidth - padding.horizontal,
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFormatPicker(),
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: _selectedFormat.fields.map(_buildField).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(child: _buildQrPanel(qrSize: 260, expandPreview: true)),
      ],
    );
  }

  Widget _buildNarrowLayout(double availableWidth) {
    // The QR image sits inside a 16px-padded white container; keep it square
    // and within the viewport on phone-sized screens.
    final qrSize = (availableWidth - 32).clamp(120.0, 260.0);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFormatPicker(),
          const SizedBox(height: 20),
          ..._selectedFormat.fields.map(_buildField),
          const SizedBox(height: 8),
          _buildQrPanel(qrSize: qrSize, expandPreview: false),
        ],
      ),
    );
  }

  Widget _buildFormatPicker() {
    return DropdownButtonFormField<QrFormat>(
      initialValue: _selectedFormat,
      decoration: const InputDecoration(
        labelText: 'Format',
        border: OutlineInputBorder(),
      ),
      items: qrFormats
          .map((f) => DropdownMenuItem(value: f, child: Text(f.name)))
          .toList(),
      onChanged: (format) {
        if (format == null) return;
        setState(() {
          _selectedFormat = format;
          _initControllers();
        });
      },
    );
  }

  Widget _buildField(QrField field) {
    final error = _errorFor(field);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: switch (field.type) {
        QrFieldType.dropdown => DropdownButtonFormField<String>(
          initialValue: _values[field.id],
          decoration: InputDecoration(
            labelText: field.label,
            border: const OutlineInputBorder(),
          ),
          items: field.options!
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _values[field.id] = value);
          },
        ),
        QrFieldType.checkbox => CheckboxListTile(
          title: Text(field.label),
          value: _values[field.id] == 'true',
          onChanged: (value) {
            setState(
              () => _values[field.id] = value == true ? 'true' : 'false',
            );
          },
          contentPadding: EdgeInsets.zero,
        ),
        QrFieldType.multiline => TextFormField(
          controller: _controllers[field.id],
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.hint,
            border: const OutlineInputBorder(),
            errorText: error,
          ),
          maxLines: 4,
        ),
        QrFieldType.password => TextFormField(
          controller: _controllers[field.id],
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.hint,
            border: const OutlineInputBorder(),
            errorText: error,
          ),
          obscureText: true,
        ),
        _ => TextFormField(
          controller: _controllers[field.id],
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.hint,
            border: const OutlineInputBorder(),
            suffixText: field.required ? '*' : null,
            errorText: error,
          ),
        ),
      },
    );
  }

  Future<void> _saveQrPng() async {
    final qr = _encode(_qrString);
    if (qr == null) return;

    // Captured before the first await: the messenger must not be looked up from
    // a context that may be gone by the time the dialog closes.
    final messenger = ScaffoldMessenger.of(context);
    final pick = widget.pickSaveLocation ?? pickPngSaveLocation;

    try {
      var path = await pick(qrFileName(_selectedFormat.id, DateTime.now()));
      if (path == null) return; // Cancelled, which is not a failure.

      // The GTK dialog does not append the extension when the user removes it.
      if (!path.toLowerCase().endsWith('.png')) path = '$path.png';

      await File(path).writeAsBytes(await renderQrPng(qr, size: _imageSize));
      messenger.showSnackBar(SnackBar(content: Text('Saved $path')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  Future<void> _copyQrImage() async {
    final qr = _encode(_qrString);
    if (qr == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final copy = widget.copyImage ?? copyPngToClipboard;

    try {
      await copy(await renderQrPng(qr, size: _imageSize));
      messenger.showSnackBar(
        const SnackBar(content: Text('QR code copied as an image')),
      );
    } on ImageClipboardException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Could not copy: $error')));
    }
  }

  /// What the preview is showing, in the beginner's terms.
  String _describe(EncodedQr qr) {
    final level = qr.errorCorrection;
    final chosen = _errorCorrection == ErrorCorrection.auto ? 'Auto: ' : '';
    final side = _imageSize.pixelsFor(qr);
    return '$chosen${level.label} error correction, survives '
        '${level.recoveryPercent}% damage · $side × $side px';
  }

  /// Error correction and image size, side by side. Each takes half the row, as
  /// the buttons below do, so both still fit the 390px phone layout.
  Widget _buildOutputOptions() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<ErrorCorrection>(
            initialValue: _errorCorrection,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Error correction',
              border: OutlineInputBorder(),
            ),
            items: ErrorCorrection.values
                .map(
                  (level) => DropdownMenuItem(
                    value: level,
                    child: Text(switch (level.recoveryPercent) {
                      null => level.label,
                      final percent => '${level.label} ($percent%)',
                    }, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (level) {
              if (level == null) return;
              setState(() => _errorCorrection = level);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<ImageSize>(
            initialValue: _imageSize,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Image size',
              border: OutlineInputBorder(),
            ),
            items: ImageSize.values
                .map(
                  (size) => DropdownMenuItem(
                    value: size,
                    child: Text(size.label, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (size) {
              if (size == null) return;
              setState(() => _imageSize = size);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQrPanel({required double qrSize, required bool expandPreview}) {
    final qrString = _qrString;
    final filled = _isReady && qrString.isNotEmpty;
    final qr = filled ? _encode(qrString) : null;
    final ready = qr != null;

    final preview = Center(
      child: switch ((filled, qr)) {
        (_, final EncodedQr qr) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(16),
          child: QrImageView.withQr(qr: qr.code, size: qrSize),
        ),
        (true, null) => const Text(
          'Too much data for a QR code\nat this error correction',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.red),
        ),
        (false, _) => const Text(
          'Fill in the required fields\nto generate a QR code',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Wide layout lets the preview absorb the leftover height; stacked
        // layout must not, since it lives inside a scroll view.
        if (expandPreview)
          Expanded(child: preview)
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: preview,
          ),
        if (qr != null) ...[
          const SizedBox(height: 8),
          Text(
            _describe(qr),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        _buildOutputOptions(),
        const SizedBox(height: 16),
        // Expanded rather than intrinsic widths: two buttons side by side must
        // still fit the 390px phone layout.
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: ready ? _saveQrPng : null,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Save PNG'),
              ),
            ),
            if (imageClipboardSupported) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: ready ? _copyQrImage : null,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Copy image'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Text('QR Code Data', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  ready ? qrString : '—',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              if (ready)
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy to clipboard',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: qrString));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
