import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../booking/stay_provider.dart';
import '../core/format.dart';
import '../core/theme.dart';
import 'top_message.dart';

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

    final error =
        ref.read(stayProvider.notifier).setDates(range.start, range.end);
    if (error != null && context.mounted) {
      TopMessage.of(context).show(error, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stay = ref.watch(stayProvider);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: context.pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.pal.border, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: context.pal.goldWash,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.date_range,
                        size: 16,
                        color: context.pal.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Your stay',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: context.pal.text,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.pal.goldWash,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.pal.goldSoft),
                  ),
                  child: Text(
                    nightsText(stay.nights),
                    style: TextStyle(
                      color: context.pal.goldDeep,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              key: const Key('pick-dates'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => _pickDates(context, ref),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.pal.page,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.pal.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: context.pal.goldWash,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.calendar_month_outlined,
                        size: 16,
                        color: context.pal.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${formatShortDate(stay.checkIn)}  –  ${formatShortDate(stay.checkOut)}',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: context.pal.text,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: context.pal.goldWash,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.pal.goldSoft),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Edit',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: context.pal.goldDeep,
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(
                            Icons.edit_calendar_outlined,
                            size: 12,
                            color: context.pal.goldDeep,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: context.pal.goldWash,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.group_outlined,
                    size: 16,
                    color: context.pal.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Guests',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: context.pal.text,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                IconButton.outlined(
                  key: const Key('guests-minus'),
                  tooltip: 'Fewer guests',
                  onPressed:
                      stay.guests > 1 ? () => _changeGuests(ref, -1) : null,
                  icon: const Icon(Icons.remove, size: 16),
                  style: IconButton.styleFrom(
                    side: BorderSide(color: context.pal.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    backgroundColor:
                        stay.guests > 1 ? context.pal.page : Colors.transparent,
                    minimumSize: const Size(48, 48),
                    fixedSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Center(
                    child: Text(
                      '${stay.guests}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: context.pal.text,
                      ),
                    ),
                  ),
                ),
                IconButton.outlined(
                  key: const Key('guests-plus'),
                  tooltip: 'More guests',
                  onPressed: stay.guests < Stay.maxGuests
                      ? () => _changeGuests(ref, 1)
                      : null,
                  icon: const Icon(Icons.add, size: 16),
                  style: IconButton.styleFrom(
                    side: BorderSide(color: context.pal.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    backgroundColor: stay.guests < Stay.maxGuests
                        ? context.pal.page
                        : Colors.transparent,
                    minimumSize: const Size(48, 48),
                    fixedSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
