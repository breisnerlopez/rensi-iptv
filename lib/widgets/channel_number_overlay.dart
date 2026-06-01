import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Big, centered, semi-transparent badge that displays the digits the user
/// is typing on the remote (e.g. "4", "42"). Hides itself when the buffer
/// is empty.
class ChannelNumberOverlay extends StatelessWidget {
  const ChannelNumberOverlay({super.key, required this.buffer});

  final ValueListenable<String> buffer;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: buffer,
      builder: (context, value, _) {
        if (value.isEmpty) return const SizedBox.shrink();
        return IgnorePointer(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 120),
              child: Container(
                key: ValueKey<String>(value),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.78),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
