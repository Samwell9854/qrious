import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../formats/email_format.dart';
import '../formats/phone_format.dart';
import '../formats/text_format.dart';
import '../formats/url_format.dart';
import '../formats/vcard_format.dart';
import '../formats/wifi_format.dart';
import '../models/qr_field.dart';
import '../models/qr_format.dart';
import '../widgets/version_badge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<QrFormat> _formats = [
    WifiFormat(),
    VCardFormat(),
    UrlFormat(),
    EmailFormat(),
    PhoneFormat(),
    TextFormat(),
  ];

  late QrFormat _selectedFormat;
  final Map<String, String> _values = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _selectedFormat = _formats.first;
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

  bool get _isReady {
    for (final field in _selectedFormat.fields) {
      if (field.required && (_values[field.id] ?? '').isEmpty) return false;
    }
    return true;
  }

  /// Below this width the two-column layout stacks into one scrolling column.
  static const double _wideLayoutBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Qrious'),
        centerTitle: false,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: VersionBadge()),
          ),
        ],
      ),
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
      items: _formats
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
          ),
          maxLines: 4,
        ),
        QrFieldType.password => TextFormField(
          controller: _controllers[field.id],
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.hint,
            border: const OutlineInputBorder(),
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
          ),
        ),
      },
    );
  }

  Widget _buildQrPanel({required double qrSize, required bool expandPreview}) {
    final qrString = _qrString;
    final ready = _isReady && qrString.isNotEmpty;

    final preview = Center(
      child: ready
          ? Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(16),
              child: QrImageView(
                data: qrString,
                version: QrVersions.auto,
                size: qrSize,
                errorStateBuilder: (context, error) => const Center(
                  child: Text(
                    'QR data too large',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            )
          : const Text(
              'Fill in the required fields\nto generate a QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
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
