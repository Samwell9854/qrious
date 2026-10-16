import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Tells [onDragging] while files are dragged over the window and hands [onDrop] the
/// paths of those dropped, as the Linux runner reports them on `qrious/drop`
/// (linux/runner/my_application.cc).
///
/// The runner sends `enter` once per drag, `leave` when it ends or the pointer goes
/// away, and `drop` with a list of paths. GTK emits the leave right before the drop,
/// so a drop is always preceded by `onDragging(false)`; nothing here relies on the
/// order. Only one instance should exist, since a channel has one handler.
class FileDropRegion extends StatefulWidget {
  const FileDropRegion({
    super.key,
    required this.child,
    required this.onDragging,
    required this.onDrop,
  });

  final Widget child;
  final ValueChanged<bool> onDragging;
  final ValueChanged<List<String>> onDrop;

  @override
  State<FileDropRegion> createState() => _FileDropRegionState();
}

class _FileDropRegionState extends State<FileDropRegion> {
  static const _channel = MethodChannel('qrious/drop');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handle);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handle(MethodCall call) async {
    if (!mounted) return;
    switch (call.method) {
      case 'enter':
        widget.onDragging(true);
      case 'leave':
        widget.onDragging(false);
      case 'drop':
        widget.onDragging(false);
        widget.onDrop((call.arguments as List).cast<String>());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
