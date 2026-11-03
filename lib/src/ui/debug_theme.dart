import 'package:flutter/material.dart';
import '../core/log_model.dart';

ThemeData debugTheme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF0F766E),
    brightness: brightness,
  ),
  visualDensity: VisualDensity.compact,
);

String formatTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

String logStatus(NetworkLog log) => log.isCancelled
    ? 'Cancelled'
    : log.error != null
    ? 'Error'
    : log.isPending
    ? 'Pending'
    : '${log.statusCode}';

Color statusColor(BuildContext context, NetworkLog log) => log.isCancelled
    ? Theme.of(context).colorScheme.onSurfaceVariant
    : log.isError
    ? Theme.of(context).colorScheme.error
    : log.isPending
    ? const Color(0xFFB7791F)
    : Theme.of(context).colorScheme.primary;

class DebugBadge extends StatelessWidget {
  const DebugBadge(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final foreground = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class DebugEmptyState extends StatelessWidget {
  const DebugEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
