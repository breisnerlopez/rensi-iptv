import 'package:flutter/material.dart';
import 'package:rensi_iptv/l10n/localization_extension.dart';
import 'package:rensi_iptv/services/sleep_timer_service.dart';

/// Top-bar player button that opens a bottom sheet of sleep-timer presets
/// and, when a timer is running, overlays the remaining time as a chip.
class SleepTimerWidget extends StatelessWidget {
  const SleepTimerWidget({super.key});

  static const List<Duration> presets = <Duration>[
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
    Duration(minutes: 90),
    Duration(minutes: 120),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: SleepTimerService.instance.remaining,
      builder: (context, remaining, _) {
        return Tooltip(
          message: context.loc.sleep_timer,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: Icon(
                  remaining != null
                      ? Icons.bedtime
                      : Icons.bedtime_outlined,
                  color: Colors.white,
                ),
                onPressed: () => _openSheet(context),
              ),
              if (remaining != null)
                Positioned(
                  bottom: -2,
                  right: -4,
                  child: _CountdownChip(remaining: remaining),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.bedtime, color: Colors.white70),
                    const SizedBox(width: 12),
                    Text(
                      sheetContext.loc.sleep_timer,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              ListTile(
                leading: const Icon(
                  Icons.bedtime_off_outlined,
                  color: Colors.white70,
                ),
                title: Text(
                  sheetContext.loc.sleep_timer_off,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: SleepTimerService.instance.isActive
                    ? null
                    : const Icon(Icons.check, color: Colors.blue),
                onTap: () {
                  SleepTimerService.instance.cancel();
                  Navigator.of(sheetContext).pop();
                },
              ),
              const Divider(height: 1, color: Colors.white12),
              for (final preset in presets)
                ListTile(
                  leading: const Icon(
                    Icons.schedule,
                    color: Colors.white70,
                  ),
                  title: Text(
                    formatDuration(preset, sheetContext),
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    SleepTimerService.instance.start(preset);
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Formats a duration for the picker rows (e.g. "30 min", "1 h", "1 h 30 min").
  static String formatDuration(Duration d, BuildContext context) {
    final loc = context.loc;
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours == 0) return '$minutes ${loc.sleep_timer_minutes_suffix}';
    if (minutes == 0) return '$hours ${loc.sleep_timer_hours_suffix}';
    return '$hours ${loc.sleep_timer_hours_suffix} '
        '$minutes ${loc.sleep_timer_minutes_suffix}';
  }
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.remaining});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24, width: 0.5),
        ),
        child: Text(
          _formatCountdown(remaining),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static String _formatCountdown(Duration d) {
    if (d.inHours > 0) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
      return '$h:$m';
    }
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
