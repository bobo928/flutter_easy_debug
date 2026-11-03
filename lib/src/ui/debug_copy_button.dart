import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copy feedback remains visible when the console covers the host Scaffold.
class DebugCopyButton extends StatefulWidget {
  const DebugCopyButton({
    super.key,
    required this.tooltip,
    required this.content,
    this.icon = Icons.copy_outlined,
  });
  final String tooltip;
  final FutureOr<String> Function() content;
  final IconData icon;
  @override
  State<DebugCopyButton> createState() => _DebugCopyButtonState();
}

class _DebugCopyButtonState extends State<DebugCopyButton> {
  Timer? _reset;
  bool _copied = false;
  bool _failed = false;
  bool _busy = false;
  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: _copied
        ? 'Copied'
        : _failed
        ? 'Copy failed'
        : widget.tooltip,
    icon: _busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            _copied
                ? Icons.check
                : _failed
                ? Icons.error_outline
                : widget.icon,
          ),
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              final content = await widget.content();
              if (!mounted) return;
              await Clipboard.setData(ClipboardData(text: content));
              if (!mounted) return;
              setState(() {
                _copied = true;
                _failed = false;
                _busy = false;
              });
            } catch (_) {
              if (!mounted) return;
              setState(() {
                _copied = false;
                _failed = true;
                _busy = false;
              });
            }
            _reset?.cancel();
            _reset = Timer(const Duration(seconds: 2), () {
              if (mounted) {
                setState(() {
                  _copied = false;
                  _failed = false;
                });
              }
            });
          },
  );
}
