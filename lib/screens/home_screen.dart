import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../formats/registry.dart';
import '../full_screen.dart';
import '../pixel_size.dart';
import '../models/qr_field.dart';
import '../models/qr_format.dart';
import '../image_clipboard.dart';
import '../qr_encoding.dart';
import '../qr_export.dart';
import '../qr_png.dart';
import '../save_location.dart';
import '../widgets/app_title.dart';
import '../widgets/fill_then_scroll.dart';
import '../widgets/full_screen_qr.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.pickSaveLocation,
    this.copyImage,
    this.setFullScreen,
    this.readPixelSize,
  });

  /// Injectable for tests; the real save dialog when null.
  final SaveLocationPicker? pickSaveLocation;

  /// Injectable for tests; the real clipboard when null.
  final PngClipboardCopier? copyImage;

  /// Injectable for tests; the real window when null.
  final FullScreenSetter? setFullScreen;

  /// Injectable for tests; the real monitor when null.
  final PixelSizeReader? readPixelSize;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late QrFormat _selectedFormat;
  final Map<String, String> _values = {};
  final Map<String, TextEditingController> _controllers = {};

  /// Password fields the user has asked to see in the clear.
  final Set<String> _revealed = {};

  // Not reset on a format switch: they describe the output, not the content.
  ErrorCorrection _errorCorrection = ErrorCorrection.auto;
  ImageSize _imageSize = ImageSize.medium;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readPixelSize();
    _selectedFormat = qrFormats.first;
    _initControllers();
  }

  void _initControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _values.clear();
    _revealed.clear();

    for (final field in _selectedFormat.fields) {
      switch (field.type) {
        case QrFieldType.dropdown:
          _values[field.id] = field.options!.first;
        case QrFieldType.checkbox:
          _values[field.id] = 'false';
        case QrFieldType.group:
          _values[field.id] = '0';
        default:
          _attachController(field.id, '');
      }
    }
  }

  /// A controller for the text at [key], writing every change back to `_values`.
  void _attachController(String key, String text) {
    _values[key] = text;
    final controller = TextEditingController(text: text);
    controller.addListener(() {
      setState(() => _values[key] = controller.text);
    });
    _controllers[key] = controller;
  }

  /// Appends an entry to [group], of its first kind, with its parts empty.
  void _addEntry(QrField group) {
    setState(() {
      final index = QrEntries.count(_values, group.id);
      for (final part in group.parts!) {
        _attachController(QrEntries.part(group.id, index, part.id), '');
      }
      if (group.kinds != null) {
        _values[QrEntries.kind(group.id, index)] = group.kinds!.first.value;
      }
      _values[group.id] = '${index + 1}';
    });
  }

  /// Removes entry [index] of [group], moving the ones after it up a place.
  ///
  /// The entries are rebuilt from their values rather than shuffled key by key:
  /// each controller is bound to its key, so the simplest correct move is to drop
  /// the group's controllers and attach fresh ones in the new positions.
  void _removeEntry(QrField group, int index) {
    setState(() {
      final entries = QrEntries.read(_values, group)..removeAt(index);
      final count = QrEntries.count(_values, group.id);
      for (var i = 0; i < count; i++) {
        for (final part in group.parts!) {
          final key = QrEntries.part(group.id, i, part.id);
          _controllers.remove(key)?.dispose();
          _values.remove(key);
          _revealed.remove(key);
        }
        _values.remove(QrEntries.kind(group.id, i));
      }
      for (final (i, entry) in entries.indexed) {
        for (final part in group.parts!) {
          _attachController(
            QrEntries.part(group.id, i, part.id),
            entry[part.id]!,
          );
        }
        if (group.kinds != null) {
          _values[QrEntries.kind(group.id, i)] = entry['kind']!;
        }
      }
      _values[group.id] = '${entries.length}';
    });
  }

  /// Millimetres per logical pixel on the current monitor, or null until known
  /// and on platforms that cannot say.
  double? _millimetresPerPixel;

  Future<void> _readPixelSize() async {
    final mm = await (widget.readPixelSize ?? readMillimetresPerPixel)();
    if (mounted && mm != _millimetresPerPixel) {
      setState(() => _millimetresPerPixel = mm);
    }
  }

  /// A move to another monitor arrives as a metrics change, as does a resize.
  @override
  void didChangeMetrics() => _readPixelSize();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
  String? _errorFor(QrField field, [String? key]) {
    final value = _values[key ?? field.id] ?? '';
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
      if (field.type == QrFieldType.group) {
        for (var i = 0; i < QrEntries.count(_values, field.id); i++) {
          for (final part in field.parts!) {
            final key = QrEntries.part(field.id, i, part.id);
            if (_errorFor(part, key) != null) return false;
          }
        }
        continue;
      }
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
                  : _buildNarrowLayout(constraints.deflate(padding).biggest),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    // Each column is its own focus group, so Tab finishes one side before it
    // crosses to the other. Ordered by position alone, it would zigzag between
    // the two wherever their fields happen to sit at the same height.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusTraversalGroup(
          child: SizedBox(
            width: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFormatPicker(),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: _selectedFormat.fields
                          .map(_buildField)
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(child: FocusTraversalGroup(child: _buildQrPanel())),
      ],
    );
  }

  Widget _buildNarrowLayout(Size available) {
    // As wide as the column, but no taller than the viewport, so a short window
    // can still see the whole code at once.
    final qrSize = max(_codeSizeFor(available), 120.0);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFormatPicker(),
          const SizedBox(height: 20),
          ..._selectedFormat.fields.map(_buildField),
          const SizedBox(height: 8),
          _buildQrPanel(qrSize: qrSize),
        ],
      ),
    );
  }

  Widget _buildFormatPicker() {
    return DropdownButtonFormField<QrFormat>(
      initialValue: _selectedFormat,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Format',
        border: OutlineInputBorder(),
      ),
      items: qrFormats
          .map(
            (f) => DropdownMenuItem(
              value: f,
              child: Row(
                children: [
                  Icon(f.icon, size: 20),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(f.name, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          )
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
    if (field.type == QrFieldType.group) return _buildGroup(field);
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
          // Grows with its text, then scrolls, so a long note is not read
          // through a four-line slot.
          minLines: 4,
          maxLines: 12,
        ),
        QrFieldType.password => TextFormField(
          controller: _controllers[field.id],
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.hint,
            border: const OutlineInputBorder(),
            errorText: error,
            suffixIcon: IconButton(
              icon: Icon(
                _revealed.contains(field.id)
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              tooltip: _revealed.contains(field.id)
                  ? 'Hide password'
                  : 'Show password',
              onPressed: () => setState(() {
                if (!_revealed.remove(field.id)) _revealed.add(field.id);
              }),
            ),
          ),
          obscureText: !_revealed.contains(field.id),
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

  /// A group's entries, then a button to add another. Nothing but the button
  /// until the user asks for an entry, so a contact with only a name stays short.
  Widget _buildGroup(QrField group) {
    final count = QrEntries.count(_values, group.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: group.parts!.length == 1
                ? _buildSingleEntry(group, i)
                : _buildBoxedEntry(group, i),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextButton.icon(
              onPressed: () => _addEntry(group),
              icon: const Icon(Icons.add, size: 18),
              label: Text('Add ${group.label.toLowerCase()}'),
            ),
          ),
        ),
      ],
    );
  }

  /// The kind of entry [index] of [group], falling back to the first.
  QrKind _kindOf(QrField group, int index) {
    final value = _values[QrEntries.kind(group.id, index)];
    return group.kinds!.firstWhere(
      (k) => k.value == value,
      orElse: () => group.kinds!.first,
    );
  }

  /// A menu of [group]'s kinds, each shown as its icon and its word, as the
  /// format picker shows formats. [child] is what opens it.
  Widget _kindMenu(QrField group, int index, Widget child) {
    return PopupMenuButton<String>(
      tooltip: '${group.label} type',
      initialValue: _kindOf(group, index).value,
      onSelected: (value) =>
          setState(() => _values[QrEntries.kind(group.id, index)] = value),
      itemBuilder: (_) => [
        for (final kind in group.kinds!)
          PopupMenuItem(
            value: kind.value,
            child: Row(
              children: [
                Icon(kind.icon, size: 20),
                const SizedBox(width: 12),
                Text(kind.label),
              ],
            ),
          ),
      ],
      child: child,
    );
  }

  Widget _removeButton(QrField group, int index) => IconButton(
    icon: const Icon(Icons.close, size: 18),
    tooltip: 'Remove ${group.label.toLowerCase()}',
    onPressed: () => _removeEntry(group, index),
  );

  /// One line: the kind as an icon inside the field, where it reads as part of
  /// the value it labels, and named again in the label so it is never an icon
  /// alone.
  Widget _buildSingleEntry(QrField group, int index) {
    final part = group.parts!.single;
    final key = QrEntries.part(group.id, index, part.id);
    final kind = group.kinds == null ? null : _kindOf(group, index);
    return TextFormField(
      controller: _controllers[key],
      decoration: InputDecoration(
        labelText: kind == null ? part.label : '${part.label} · ${kind.label}',
        hintText: part.hint,
        border: const OutlineInputBorder(),
        errorText: _errorFor(part, key),
        prefixIcon: kind == null
            ? null
            : _kindMenu(
                group,
                index,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(kind.icon, size: 20),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
        suffixIcon: _removeButton(group, index),
      ),
    );
  }

  /// Several parts boxed together, with the kind in a notch of the box's top
  /// edge. Rounder than a field, and tighter inside than the form around it, so
  /// the parts read as one entry and the entry as distinct from its neighbours.
  Widget _buildBoxedEntry(QrField group, int index) {
    final kind = group.kinds == null ? null : _kindOf(group, index);
    final legend = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kind == null)
          Text(group.label)
        else
          _kindMenu(
            group,
            index,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(kind.icon, size: 18),
                const SizedBox(width: 6),
                Text('${group.label} · ${kind.label}'),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
      ],
    );
    final colors = Theme.of(context).colorScheme;
    // Drawn by hand rather than with an InputDecorator, whose label cannot take a
    // tap. The legend sits over the box's top edge on the page's own background,
    // which reads as a notch in the line, as a field's floating label does.
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.outline),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 24, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final part in group.parts!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextFormField(
                        controller:
                            _controllers[QrEntries.part(
                              group.id,
                              index,
                              part.id,
                            )],
                        decoration: InputDecoration(
                          labelText: part.label,
                          hintText: part.hint,
                          border: const OutlineInputBorder(),
                          isDense: true,
                          errorText: _errorFor(
                            part,
                            QrEntries.part(group.id, index, part.id),
                          ),
                        ),
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => _removeEntry(group, index),
                      icon: const Icon(Icons.close, size: 18),
                      label: Text('Remove ${group.label.toLowerCase()}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        PositionedDirectional(
          start: 12,
          top: 0,
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SizedBox(height: 24, child: legend),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveQr(ExportFileType type) async {
    final qr = _encode(_qrString);
    if (qr == null) return;

    // Captured before the first await: the messenger must not be looked up from
    // a context that may be gone by the time the dialog closes.
    final messenger = ScaffoldMessenger.of(context);
    final pick = widget.pickSaveLocation ?? pickSaveLocation;

    try {
      final picked = await pick(
        qrFileName(_selectedFormat.id, DateTime.now(), type),
        type,
      );
      if (picked == null) return; // Cancelled, which is not a failure.

      final path = type.withExtension(picked);
      await File(path).writeAsBytes(await type.render(qr, _imageSize));
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

  Future<void> _showFullScreen(EncodedQr qr) async {
    final navigator = Navigator.of(context);
    final setter = widget.setFullScreen ?? setFullScreen;

    await setter(true);
    await navigator.push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => FullScreenQr(qr: qr),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
    await setter(false);
  }

  /// Below this many millimetres per module on the screen, the preview says the
  /// code can be shown full screen.
  ///
  /// A judgement, not a spec figure. A phone reads a module by the angle it covers,
  /// so size and distance trade off. 1.4mm modules (5px on a 24" 1080p monitor)
  /// scanned instantly from about 1.2m in testing; the same angle at a handheld
  /// 40cm is about 0.45mm.
  static const double _comfortableModuleMillimetres = 0.5;

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

  /// The white container around the code pads it by 16px on each side.
  static const double _codeBoxPadding = 16;

  /// The largest square code that fits [space] with its white container around it.
  static double _codeSizeFor(Size space) =>
      max(min(space.width, space.height) - 2 * _codeBoxPadding, 0);

  /// Whether a [qrSize] code leaves its modules too small to scan comfortably.
  /// QrImageView keeps 10px of padding on each side inside its size.
  bool _isDense(EncodedQr qr, double qrSize) {
    final mmPerPixel = _millimetresPerPixel ?? fallbackMillimetresPerPixel();
    final modulePixels = (qrSize - 20) / qr.moduleCount;
    return modulePixels * mmPerPixel < _comfortableModuleMillimetres;
  }

  Widget _buildCode(EncodedQr qr, double qrSize) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(_codeBoxPadding),
      // The whole code is the control, rather than a button beside it: it is the
      // obvious thing to reach for, and the hint below says so when the code is
      // small enough to need it.
      child: Tooltip(
        message: 'Show full screen',
        child: Semantics(
          button: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.zoomIn,
            child: GestureDetector(
              onTap: () => _showFullScreen(qr),
              child: QrImageView.withQr(qr: qr.code, size: qrSize),
            ),
          ),
        ),
      ),
    );
  }

  /// What the code produced, and when it is dense, that it can go full screen.
  List<Widget> _buildCaption(EncodedQr qr, {required bool dense}) {
    final small = Theme.of(context).textTheme.bodySmall;
    return [
      const SizedBox(height: 8),
      Text(_describe(qr), textAlign: TextAlign.center, style: small),
      if (dense) ...[
        const SizedBox(height: 4),
        Text(
          'This code is dense and may be hard to scan here. '
          '${pointerVerb()} it to show it full screen.',
          textAlign: TextAlign.center,
          style: small?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ],
    ];
  }

  /// The wide layout's code: as large as the panel's leftover space allows, and
  /// always square.
  ///
  /// The caption sits inside the measured space, so whether to show the dense
  /// hint is judged before the caption's height is known. [_captionAllowance]
  /// stands in for it; a code within a few pixels of the threshold may get the
  /// verdict its neighbour would, which is harmless either way.
  Widget _buildFittedCode(EncodedQr qr) {
    return LayoutBuilder(
      builder: (context, space) {
        final estimate = _codeSizeFor(
          Size(space.maxWidth, space.maxHeight - _captionAllowance),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, room) =>
                    Center(child: _buildCode(qr, _codeSizeFor(room.biggest))),
              ),
            ),
            ..._buildCaption(qr, dense: _isDense(qr, estimate)),
          ],
        );
      },
    );
  }

  /// Roughly the height of the caption under the wide layout's code.
  static const double _captionAllowance = 40;

  /// The least height the wide layout's code and caption get before the panel
  /// scrolls instead: a 200px code, its white box, and room for the caption with
  /// the dense hint wrapped over several lines in a narrow panel.
  static const double _minCodeArea = 200 + 2 * _codeBoxPadding + 120;

  /// About eight lines of the payload before its box scrolls.
  static const double _maxDataHeight = 150;

  /// The code, its caption and everything under it. With a [qrSize] the code is
  /// that size, for the stacked layout's scroll view; without one it fills the
  /// leftover height, which only the wide layout has to give.
  Widget _buildQrPanel({double? qrSize}) {
    final qrString = _qrString;
    final filled = _isReady && qrString.isNotEmpty;
    final qr = filled ? _encode(qrString) : null;
    final ready = qr != null;

    final preview = Center(
      child: switch ((filled, qr)) {
        (_, final EncodedQr qr) => _buildCode(qr, qrSize ?? 0),
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

    final rest = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        _buildOutputOptions(),
        const SizedBox(height: 16),
        // Expanded rather than intrinsic widths: two buttons side by side must
        // still fit the 390px phone layout.
        Row(
          children: [
            Expanded(
              // A menu rather than a choice in the save dialog, which on Linux
              // cannot report which file type was picked.
              child: MenuAnchor(
                menuChildren: [
                  for (final type in ExportFileType.values)
                    MenuItemButton(
                      onPressed: () => _saveQr(type),
                      child: Text(type.label),
                    ),
                ],
                builder: (context, menu, _) => FilledButton.icon(
                  onPressed: ready
                      ? () => menu.isOpen ? menu.close() : menu.open()
                      : null,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Save'),
                ),
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
                // Capped, because it is there to glance at and the button beside
                // it copies all of it; a long payload would otherwise push the
                // code itself off the screen.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _maxDataHeight),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      ready ? qrString : '—',
                      style: const TextStyle(
                        // Named fonts before the generic family: on a system with
                        // a Japanese font such as MS Gothic installed, "monospace"
                        // can resolve to one that draws the backslash as a yen
                        // sign, and a backslash is often part of the payload.
                        fontFamily: 'Noto Sans Mono',
                        fontFamilyFallback: [
                          'DejaVu Sans Mono',
                          'Liberation Mono',
                          'monospace',
                        ],
                        fontSize: 13,
                      ),
                    ),
                  ),
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

    // Wide layout gives the code whatever height the rest leaves, and scrolls
    // only when even its minimum does not fit. Stacked layout already lives in a
    // scroll view, with a code sized from the width.
    if (qrSize == null) {
      return LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          child: FillThenScroll(
            viewportHeight: viewport.maxHeight,
            minFillHeight: _minCodeArea,
            fill: qr != null ? _buildFittedCode(qr) : preview,
            rest: rest,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: preview,
        ),
        if (qr != null) ..._buildCaption(qr, dense: _isDense(qr, qrSize)),
        rest,
      ],
    );
  }
}
