import 'dart:async';
import 'package:flutter/material.dart';
import '../core/easy_debug_navigator_observer.dart';
import '../core/log_export.dart';
import '../core/log_manager.dart';
import '../core/log_model.dart';
import '../core/log_query.dart';
import 'debug_copy_button.dart';
import 'debug_theme.dart';
import 'log_detail_page.dart';

enum LogFilter { all, success, error, pending, cancelled }

class LogListView extends StatefulWidget {
  const LogListView({
    super.key,
    this.filter = LogFilter.all,
    this.onSelect,
    this.initialQuery,
    this.onQueryChanged,
  });
  final LogFilter filter;
  final NetworkLogQuery? initialQuery;
  final ValueChanged<NetworkLogQuery>? onQueryChanged;
  final ValueChanged<NetworkLog>? onSelect;
  @override
  State<LogListView> createState() => _LogListViewState();
}

class _LogListViewState extends State<LogListView> {
  late NetworkLogStatus _status =
      widget.initialQuery?.status ??
      NetworkLogStatus.values[widget.filter.index];
  late String _query = widget.initialQuery?.search ?? '';
  late String? _method = widget.initialQuery?.method;
  late String? _host = widget.initialQuery?.host;
  late int? _statusCode = widget.initialQuery?.statusCode;
  late bool _slow = widget.initialQuery?.minDurationMs != null;
  late bool _advanced = _method != null || _host != null || _slow;
  late final _search = TextEditingController(text: _query);
  Timer? _debounce;
  NetworkLogQuery get _selection => NetworkLogQuery(
    search: _query,
    status: _status,
    method: _method,
    host: _host,
    minDurationMs: _slow ? 1000 : null,
    statusCode: _statusCode,
  );

  void _change(VoidCallback change) {
    setState(change);
    widget.onQueryChanged?.call(_selection);
  }

  void _reset() {
    _debounce?.cancel();
    _search.clear();
    _change(() {
      _query = '';
      _status = NetworkLogStatus.all;
      _method = null;
      _host = null;
      _slow = false;
      _statusCode = null;
    });
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
  ) => ValueListenableBuilder<List<NetworkLog>>(
    valueListenable: EasyDebugManager().logsNotifier,
    builder: (context, allLogs, _) {
      final logs = allLogs.where(_selection.matches).toList();
      final optionsSource = _advanced ? allLogs : const <NetworkLog>[];
      final methods =
          optionsSource.map((e) => e.method.toUpperCase()).toSet().toList()
            ..sort();
      final hosts =
          optionsSource
              .map((e) => Uri.tryParse(e.url)?.host ?? '')
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (_method != null && !methods.contains(_method)) methods.add(_method!);
      if (_host != null && !hosts.contains(_host)) hosts.add(_host!);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search URL or method',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Reset filters',
                    icon: const Icon(Icons.clear),
                    onPressed: _reset,
                  ),
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
                    () => _change(() => _query = value),
                  );
                },
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
                  for (final status in NetworkLogStatus.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(switch (status) {
                          NetworkLogStatus.all => 'All',
                          NetworkLogStatus.success => 'Success',
                          NetworkLogStatus.error => 'Error',
                          NetworkLogStatus.pending => 'Pending',
                          NetworkLogStatus.cancelled => 'Cancelled',
                        }),
                        selected: _status == status,
                        showCheckmark: false,
                        onSelected: (_) => _change(() => _status = status),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${logs.length} / ${allLogs.length} requests',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Advanced filters',
                    isSelected: _advanced,
                    icon: const Icon(Icons.tune),
                    onPressed: () => setState(() => _advanced = !_advanced),
                  ),
                  DebugCopyButton(
                    tooltip: 'Copy filtered HAR',
                    icon: Icons.file_download_outlined,
                    content: () => EasyDebugExport.harAsync(
                      logs,
                      config: EasyDebugManager().config,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_advanced)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownMenu<String>(
                            key: ValueKey('method-${_method ?? ''}'),
                            expandedInsets: EdgeInsets.zero,
                            initialSelection: _method ?? '',
                            label: const Text('Method'),
                            dropdownMenuEntries: [
                              const DropdownMenuEntry(
                                value: '',
                                label: 'Any method',
                              ),
                              for (final method in methods)
                                DropdownMenuEntry(value: method, label: method),
                            ],
                            onSelected: (value) => _change(
                              () => _method = value == '' ? null : value,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownMenu<String>(
                            key: ValueKey('host-${_host ?? ''}'),
                            expandedInsets: EdgeInsets.zero,
                            initialSelection: _host ?? '',
                            label: const Text('Host'),
                            menuHeight: 240,
                            dropdownMenuEntries: [
                              const DropdownMenuEntry(
                                value: '',
                                label: 'Any host',
                              ),
                              for (final host in hosts)
                                DropdownMenuEntry(value: host, label: host),
                            ],
                            onSelected: (value) => _change(
                              () => _host = value == '' ? null : value,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        label: const Text('Slow requests · 1 s+'),
                        selected: _slow,
                        onSelected: (value) => _change(() => _slow = value),
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
                icon: Icons.travel_explore,
                title: allLogs.isEmpty
                    ? 'Waiting for requests'
                    : 'No matching requests',
                message: allLogs.isEmpty
                    ? 'Make a request in your app to inspect it here.'
                    : 'Try another filter or search term.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              sliver: SliverList.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) => _card(context, logs[index]),
              ),
            ),
        ],
      );
    },
  );

  Widget _card(BuildContext context, NetworkLog log) {
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
              MaterialPageRoute<void>(builder: (_) => LogDetailPage(log: log)),
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
                  uri?.path.isNotEmpty == true ? uri!.path : log.url,
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatTime(log.timestamp),
                        style: Theme.of(context).textTheme.labelSmall,
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
  }
}
