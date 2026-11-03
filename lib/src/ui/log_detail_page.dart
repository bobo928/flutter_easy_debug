import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/log_manager.dart';
import '../core/log_model.dart';
import '../core/log_export.dart';
import 'debug_copy_button.dart';
import 'debug_theme.dart';

class LogDetailPage extends StatefulWidget {
  const LogDetailPage({super.key, required this.log, this.onBack});
  final NetworkLog log;
  final VoidCallback? onBack;
  @override
  State<LogDetailPage> createState() => _LogDetailPageState();
}

class _LogDetailPageState extends State<LogDetailPage> {
  int _tab = 0;
  late NetworkLog _latest = widget.log;

  String _format(dynamic value) {
    if (value == null) return 'No body';
    if (value is Map || value is List) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    try {
      return const JsonEncoder.withIndent(
        '  ',
      ).convert(jsonDecode(value.toString()));
    } catch (_) {
      return value.toString();
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: debugTheme(Theme.of(context).brightness),
    child: ValueListenableBuilder<List<NetworkLog>>(
      valueListenable: EasyDebugManager().logsNotifier,
      builder: (context, logs, _) {
        _latest = EasyDebugManager().getLog(widget.log.id) ?? _latest;
        final log = _latest;
        final request = _tab == 0;
        final headers = request ? log.request?.headers : log.response?.headers;
        final body = request ? log.request?.body : log.response?.body;
        final truncated = request
            ? log.request?.bodyTruncated ?? false
            : log.response?.bodyTruncated ?? false;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Request details'),
            leading: widget.onBack == null
                ? null
                : IconButton(
                    tooltip: 'Back to requests',
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBack,
                  ),
            actions: [
              DebugCopyButton(
                tooltip: 'Copy as cURL',
                icon: Icons.terminal,
                content: () => EasyDebugExport.curl(
                  _latest,
                  config: EasyDebugManager().config,
                ),
              ),
              IconButton(
                tooltip: 'Copy details',
                icon: const Icon(Icons.copy_outlined),
                onPressed: () async {
                  final text =
                      'URL: ${log.url}\nMethod: ${log.method}\nStatus: ${logStatus(log)}\n'
                      '${log.error == null ? '' : 'Error: ${log.error!.errorMessage}\n'}'
                      'Headers: ${_format(headers)}\nBody: ${_format(body)}'
                      '${truncated ? '\n[Body truncated]' : ''}';
                  await Clipboard.setData(ClipboardData(text: text));
                  if (context.mounted) {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('Details copied')),
                    );
                  }
                },
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        DebugBadge(log.method),
                        DebugBadge(
                          logStatus(log),
                          color: statusColor(context, log),
                        ),
                        if (log.durationMs != null)
                          DebugBadge('${log.durationMs} ms'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      log.url,
                      minLines: 1,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Request')),
                    ButtonSegment(value: 1, label: Text('Response')),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (value) =>
                      setState(() => _tab = value.first),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!request && log.isPending)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text('Waiting for response…'),
                      ),
                    if (!request && log.error != null)
                      _section(
                        context,
                        'Error',
                        '${log.error!.errorMessage}\n${log.error!.stackTrace ?? ''}',
                      ),
                    _section(context, 'Headers', _format(headers)),
                    if (truncated)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Body truncated · capture limit reached',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    _section(context, 'Body', _format(body)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _section(BuildContext context, String title, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );
}
