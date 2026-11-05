import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// A small soft-coloured label for a booking status: tinted background, matching
/// text and a small icon, so each state can be told apart without a loud block.
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pal = context.pal;
    final tone = _tone(pal, dark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tone.icon, size: 14, color: tone.fg),
          const SizedBox(width: 5),
          Text(
            statusLabel(status),
            style: TextStyle(
              color: tone.fg,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  _Tone _tone(AngkorPalette pal, bool dark) => switch (status) {
        'pending' => _Tone(pal.goldWash, pal.goldSoft, pal.goldDeep, Icons.hourglass_top_rounded),
        'confirmed' => dark
            ? const _Tone(Color(0xFF14233F), Color(0xFF1E3A6E), Color(0xFF93C5FD), Icons.event_available_rounded)
            : const _Tone(Color(0xFFEFF5FF), Color(0xFFBFD7FE), Color(0xFF1D4ED8), Icons.event_available_rounded),
        'checked_in' => _Tone(pal.successWash, pal.successBorder, pal.success, Icons.login_rounded),
        'checked_out' => _Tone(pal.surfaceAlt, pal.border, pal.textMuted, Icons.logout_rounded),
        'cancelled' => _Tone(pal.dangerWash, pal.dangerBorder, pal.danger, Icons.cancel_outlined),
        // The guest never came: calm orange, not an alarm.
        'no_show' => dark
            ? const _Tone(Color(0xFF2E1B0E), Color(0xFF6B3A17), Color(0xFFFDBA74), Icons.person_off_outlined)
            : const _Tone(Color(0xFFFFF3E8), Color(0xFFFFD8B5), Color(0xFFC2410C), Icons.person_off_outlined),
        _ => _Tone(pal.surfaceAlt, pal.border, pal.textMuted, Icons.circle_outlined),
      };
}

class _Tone {
  final Color bg;
  final Color border;
  final Color fg;
  final IconData icon;
  const _Tone(this.bg, this.border, this.fg, this.icon);
}
