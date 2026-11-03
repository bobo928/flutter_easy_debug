import 'dart:async';
import 'package:flutter/material.dart';
import '../core/easy_debug_navigator_observer.dart';
import '../core/log_manager.dart';
import '../core/log_model.dart';
import 'debug_theme.dart';
import 'log_detail_page.dart';

enum LogFilter { all, success, error, pending }

class LogListView extends StatefulWidget {
  const LogListView({super.key, this.filter = LogFilter.all, this.onSelect});
  final LogFilter filter;
  final ValueChanged<NetworkLog>? onSelect;
  @override
  State<LogListView> createState() => _LogListViewState();
}

class _LogListViewState extends State<LogListView> {
  late LogFilter _filter = widget.filter;
  String _query = '';
  Timer? _debounce;
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          decoration: InputDecoration(
            hintText: 'Search URL or method',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            isDense: true,
          ),
          onChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(
              const Duration(milliseconds: 150),
              () => setState(() => _query = value.toLowerCase()),
            );
          },
        ),
      ),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (final filter in LogFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(switch (filter) {
                    LogFilter.all => 'All',
                    LogFilter.success => 'Success',
                    LogFilter.error => 'Error',
                    LogFilter.pending => 'Pending',
                  }),
                  selected: _filter == filter,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: ValueListenableBuilder<List<NetworkLog>>(
          valueListenable: EasyDebugManager().logsNotifier,
          builder: (context, allLogs, _) {
            final logs = allLogs.where((log) {
              final matches = switch (_filter) {
                LogFilter.all => true,
                LogFilter.success =>
                  !log.isPending &&
                      !log.isCancelled &&
                      !log.isError &&
                      log.statusCode >= 200 &&
                      log.statusCode < 400,
                LogFilter.error => log.isError,
                LogFilter.pending => log.isPending,
              };
              return matches &&
                  (log.url.toLowerCase().contains(_query) ||
                      log.method.toLowerCase().contains(_query));
            }).toList();
            if (logs.isEmpty) {
              return DebugEmptyState(
                icon: Icons.travel_explore,
                title: allLogs.isEmpty
                    ? 'Waiting for requests'
                    : 'No matching requests',
                message: allLogs.isEmpty
                    ? 'Make a request in your app to inspect it here.'
                    : 'Try another filter or search term.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                final uri = Uri.tryParse(log.url);
                return Padding(
                  key: ValueKey(log.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card.filled(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        if (widget.onSelect != null) {
                          widget.onSelect!(log);
                          return;
                        }
                        final navigator =
                            EasyDebugNavigatorObserver.navigatorState ??
                            Navigator.maybeOf(context);
                        navigator?.push(
                          MaterialPageRoute<void>(
                            builder: (_) => LogDetailPage(log: log),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                DebugBadge(log.method.toUpperCase()),
                                const Spacer(),
                                DebugBadge(
                                  logStatus(log),
                                  color: statusColor(context, log),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              uri?.path.isNotEmpty == true
                                  ? uri!.path
                                  : log.url,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              uri?.host ?? log.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    formatTime(log.timestamp),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ),
                                Text(
                                  log.durationMs == null
                                      ? 'In progress'
                                      : '${log.durationMs} ms',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward_ios, size: 10),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ],
  );
}
