import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/log_manager.dart';
import '../core/log_model.dart';
import 'debug_theme.dart';

class GeneralLogsView extends StatelessWidget {
  const GeneralLogsView({super.key});
  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<List<GeneralLog>>(
    valueListenable: EasyDebugManager().generalLogsNotifier,
    builder: (context, logs, _) {
      if (logs.isEmpty) {
        return const DebugEmptyState(
          icon: Icons.terminal,
          title: 'A little more context',
          message: 'Your debugPrint and EasyDebug.log messages appear here.',
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final log = logs[logs.length - index - 1];
          final message = '${log.level ?? ''} ${log.message}'.toLowerCase();
          final color = message.contains('error') || message.contains('fail')
              ? Theme.of(context).colorScheme.error
              : message.contains('warn')
              ? const Color(0xFFB7791F)
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
                              log.level ?? 'LOG',
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
        },
      );
    },
  );
}
