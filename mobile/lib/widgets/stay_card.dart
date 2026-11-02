import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../booking/stay_provider.dart';
import '../core/format.dart';

/// "Your stay": pick the nights and the number of guests.
/// The room list below follows these choices.
class StayCard extends ConsumerWidget {
  const StayCard({super.key});

  /// Reads the number at the moment of the tap, so quick taps never lose a step.
  void _changeGuests(WidgetRef ref, int step) {
    final current = ref.read(stayProvider).guests;
    ref.read(stayProvider.notifier).setGuests(current + step);
  }

  Future<void> _pickDates(BuildContext context, WidgetRef ref) async {
    final stay = ref.read(stayProvider);
    final today = dateOnly(DateTime.now());

    final range = await showDateRangePicker(
      context: context,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: stay.checkIn, end: stay.checkOut),
      helpText: 'Choose check-in and check-out',
      saveText: 'Done',
    );
    if (range == null) return;

    final error = ref.read(stayProvider.notifier).setDates(range.start, range.end);
    if (error != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stay = ref.watch(stayProvider);
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your stay', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('pick-dates'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => _pickDates(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${formatShortDate(stay.checkIn)}  →  ${formatShortDate(stay.checkOut)}',
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            nightsText(stay.nights),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.edit_outlined, size: 18),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.people_outline),
                const SizedBox(width: 12),
                const Expanded(child: Text('Guests')),
                IconButton.outlined(
                  key: const Key('guests-minus'),
                  onPressed: stay.guests > 1 ? () => _changeGuests(ref, -1) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${stay.guests}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton.outlined(
                  key: const Key('guests-plus'),
                  onPressed: stay.guests < Stay.maxGuests ? () => _changeGuests(ref, 1) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
