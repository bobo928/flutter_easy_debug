import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/log_export.dart';
import '../core/log_manager.dart';
import '../core/log_model.dart';
import '../core/log_query.dart';
import 'debug_copy_button.dart';
import 'debug_theme.dart';

class GeneralLogsView extends StatefulWidget {
  const GeneralLogsView({
    super.key,
    this.initialQuery = const GeneralLogQuery(),
    this.onQueryChanged,
  });
  final GeneralLogQuery initialQuery;
  final ValueChanged<GeneralLogQuery>? onQueryChanged;
  @override
  State<GeneralLogsView> createState() => _GeneralLogsViewState();
}

class _GeneralLogsViewState extends State<GeneralLogsView> {
  late String _query = widget.initialQuery.search;
  late GeneralLogSeverity? _severity = widget.initialQuery.severity;
  late final _search = TextEditingController(text: _query);
  Timer? _debounce;
  void _change(VoidCallback change) {
    setState(change);
    widget.onQueryChanged?.call(
      GeneralLogQuery(search: _query, severity: _severity),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<List<GeneralLog>>(
    valueListenable: EasyDebugManager().generalLogsNotifier,
    builder: (context, allLogs, _) {
      final selection = GeneralLogQuery(search: _query, severity: _severity);
      final logs = allLogs.where(selection.matches).toList();
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: 'Search messages',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        _debounce?.cancel();
                        _debounce = Timer(
                          const Duration(milliseconds: 150),
                          () => _change(() => _query = value),
                        );
                      },
                    ),
                  ),
                  DebugCopyButton(
                    tooltip: 'Copy filtered logs as JSON',
                    icon: Icons.file_download_outlined,
                    content: () => EasyDebugExport.generalJsonAsync(logs),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final severity in <GeneralLogSeverity?>[
                    null,
                    ...GeneralLogSeverity.values,
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(switch (severity) {
                          null => 'All',
                          GeneralLogSeverity.debug => 'Debug',
                          GeneralLogSeverity.info => 'Info',
                          GeneralLogSeverity.warning => 'Warn',
                          GeneralLogSeverity.error => 'Error',
                        }),
                        selected: _severity == severity,
                        showCheckmark: false,
                        onSelected: (_) => _change(() => _severity = severity),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (logs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: DebugEmptyState(
                icon: Icons.terminal,
                title: allLogs.isEmpty
                    ? 'A little more context'
                    : 'No matching messages',
                message: allLogs.isEmpty
                    ? 'Your debugPrint and EasyDebug.log messages appear here.'
                    : 'Try another level or search term.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) =>
                    _card(context, logs[logs.length - index - 1]),
              ),
            ),
        ],
      );
    },
  );

  Widget _card(BuildContext context, GeneralLog log) {
    final severity = severityOf(log);
    final color = severity == GeneralLogSeverity.error
        ? Theme.of(context).colorScheme.error
        : severity == GeneralLogSeverity.warning
        ? Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFF6C76A)
              : const Color(0xFF8A4B00)
        : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card.filled(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: log.message));
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('Log copied'),
                  duration: Duration(seconds: 1),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle, size: 6, color: color),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        log.level ?? severity.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    Text(
                      formatTime(log.timestamp),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.copy_outlined, size: 12),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  log.message,
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
