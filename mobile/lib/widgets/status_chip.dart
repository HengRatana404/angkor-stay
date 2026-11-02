import 'package:flutter/material.dart';

import '../core/format.dart';

/// A small coloured label for a booking status.
class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  Color get _color => switch (status) {
        'pending' => Colors.orange.shade800,
        'confirmed' => Colors.blue.shade700,
        'checked_in' => Colors.green.shade700,
        'checked_out' => Colors.blueGrey.shade600,
        'cancelled' => Colors.red.shade700,
        'no_show' => Colors.brown.shade600,
        _ => Colors.grey.shade700,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _color, borderRadius: BorderRadius.circular(12)),
      child: Text(
        statusLabel(status),
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
