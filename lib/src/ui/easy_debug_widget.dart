import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/config_model.dart';
import '../core/log_manager.dart';
import '../core/log_model.dart';
import 'debug_theme.dart';
import 'general_logs_view.dart';
import 'log_detail_page.dart';
import 'log_list_view.dart';

enum DebugViewMode { network, generalLogs, settings }

class EasyDebugWidget extends StatefulWidget {
  const EasyDebugWidget({super.key, required this.child});
  final Widget child;
  static void close(BuildContext context) =>
      context.findAncestorStateOfType<_EasyDebugWidgetState>()?.closeConsole();
  @override
  State<EasyDebugWidget> createState() => _EasyDebugWidgetState();
}

class _EasyDebugWidgetState extends State<EasyDebugWidget> {
  bool _visible = false;
  Offset _position = const Offset(20, 100);
  DebugViewMode _mode = DebugViewMode.network;
  NetworkLog? _selectedLog;

  @override
  void initState() {
    super.initState();
    EasyDebugManager().configNotifier.addListener(_onConfigChanged);
  }

  void _onConfigChanged() {
    if (!EasyDebugManager().enabled) closeConsole();
  }

  @override
  void dispose() {
    EasyDebugManager().configNotifier.removeListener(_onConfigChanged);
    super.dispose();
  }

  void closeConsole() => setState(() {
    _visible = false;
    _selectedLog = null;
  });

  @override
  Widget build(BuildContext context) => _ConsoleOverlay(
    child: ValueListenableBuilder<EasyDebugConfig>(
      valueListenable: EasyDebugManager().configNotifier,
      child: widget.child,
      builder: (context, config, child) {
        if (!config.enabled) return child!;
        return LayoutBuilder(
          builder: (context, constraints) {
            final padding = MediaQuery.paddingOf(context);
            final maxX = math.max(0.0, constraints.maxWidth - 64);
            final maxY = math.max(
              padding.top,
              constraints.maxHeight - padding.bottom - 64,
            );
            final position = Offset(
              _position.dx.clamp(0.0, maxX),
              _position.dy.clamp(padding.top, maxY),
            );
            return Stack(
              children: [
                child!,
                if (!_visible)
                  Positioned(
                    left: position.dx,
                    top: position.dy,
                    child: GestureDetector(
                      onPanUpdate: (details) => setState(() {
                        _position = Offset(
                          (position.dx + details.delta.dx).clamp(0.0, maxX),
                          (position.dy + details.delta.dy).clamp(
                            padding.top,
                            maxY,
                          ),
                        );
                      }),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: IconButton.filled(
                          tooltip: 'Open Easy Debug',
                          icon: const Icon(Icons.bug_report_outlined),
                          onPressed: () => setState(() => _visible = true),
                        ),
                      ),
                    ),
                  ),
                if (_visible)
                  Positioned.fill(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.escape):
                            closeConsole,
                      },
                      child: Focus(
                        autofocus: true,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: closeConsole,
                                child: const ColoredBox(
                                  color: Color(0x66000000),
                                ),
                              ),
                            ),
                            SafeArea(
                              minimum: const EdgeInsets.all(12),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 760,
                                    maxHeight: 840,
                                  ),
                                  child: RepaintBoundary(
                                    key: const ValueKey('easy_debug_panel'),
                                    child: Theme(
                                      data: debugTheme(
                                        Theme.of(context).brightness,
                                      ),
                                      child: Material(
                                        elevation: 12,
                                        borderRadius: BorderRadius.circular(24),
                                        clipBehavior: Clip.antiAlias,
                                        child: _selectedLog == null
                                            ? _buildConsole()
                                            : LogDetailPage(
                                                log: _selectedLog!,
                                                onBack: () => setState(
                                                  () => _selectedLog = null,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );

  Widget _buildConsole() => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    Icons.bug_report_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Easy Debug',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (constraints.maxHeight >= 440)
                      Text(
                        'Your app, under the lens',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Clear logs',
                onPressed: EasyDebugManager().clearLogs,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
              IconButton(
                tooltip: 'Close console',
                onPressed: closeConsole,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<DebugViewMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: DebugViewMode.network,
                  label: Text('Network'),
                ),
                ButtonSegment(
                  value: DebugViewMode.generalLogs,
                  label: Text('Logs'),
                ),
                ButtonSegment(
                  value: DebugViewMode.settings,
                  label: Text('Settings'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (values) =>
                  setState(() => _mode = values.first),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (_mode) {
            DebugViewMode.network => LogListView(
              onSelect: (log) => setState(() => _selectedLog = log),
            ),
            DebugViewMode.generalLogs => const GeneralLogsView(),
            DebugViewMode.settings => const _EnvironmentSettings(),
          },
        ),
        if (constraints.maxHeight >= 440)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 7,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: ValueListenableBuilder<AppEnvironment?>(
                    valueListenable: EasyDebugManager().currentEnvNotifier,
                    builder: (_, env, _) => Text(
                      env?.name ?? 'Live capture',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    'Stored on this device',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// MaterialApp.builder is above its Navigator, so controls need their own
/// overlay for tooltips, selection handles and text-field menus.
class _ConsoleOverlay extends StatefulWidget {
  const _ConsoleOverlay({required this.child});
  final Widget child;
  @override
  State<_ConsoleOverlay> createState() => _ConsoleOverlayState();
}

class _ConsoleOverlayState extends State<_ConsoleOverlay> {
  late final _entry = OverlayEntry(builder: (_) => widget.child);
  @override
  void didUpdateWidget(_ConsoleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

class _EnvironmentSettings extends StatelessWidget {
  const _EnvironmentSettings();
  @override
  Widget build(BuildContext context) {
    final manager = EasyDebugManager();
    if (manager.availableEnvironments.isEmpty) {
      return const DebugEmptyState(
        icon: Icons.dns_outlined,
        title: 'Choose your environment',
        message:
            'Add your API environments during initialization to switch between them here.',
      );
    }
    return ValueListenableBuilder<AppEnvironment?>(
      valueListenable: manager.currentEnvNotifier,
      builder: (context, selected, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'API ENVIRONMENT',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 12),
          for (final env in manager.availableEnvironments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card.filled(
                color: selected == env
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  title: Text(
                    env.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(env.baseUrl),
                  trailing: Icon(
                    selected == env
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  onTap: () async {
                    try {
                      await manager.changeEnvironment(env);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not save environment. Please try again.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            'Your app must listen for environment changes to update its network clients.',
          ),
        ],
      ),
    );
  }
}
