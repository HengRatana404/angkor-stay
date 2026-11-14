import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/admin_repository.dart';
import '../../core/format.dart';
import '../../models/dashboard.dart';
import '../../widgets/error_banner.dart';
import '../staff/staff_booking_detail_screen.dart';
import '../../core/theme.dart';
import '../../widgets/angkor_app_bar.dart';

/// The admin's overview: today, rooms, money, bookings waiting to be paid, last 7 days.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);

    return Scaffold(
        appBar: AngkorAppBar(title: 'Dashboard'),
        body: RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardProvider),
          child: data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ListView(
              padding: const EdgeInsets.all(24),
              children: [
                ErrorBanner('$e'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(dashboardProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
            data: (d) => _Body(d),
          ),
        ),
      );
  }
}

class _Body extends ConsumerWidget {
  final Dashboard d;
  const _Body(this.d);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Text('Today', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            _Stat(
              keyName: 'stat-checkins',
              label: 'Check-ins',
              value: '${d.checkIns}',
              note: '${d.checkedInSoFar} done',
            ),
            _Stat(
              keyName: 'stat-checkouts',
              label: 'Check-outs',
              value: '${d.checkOuts}',
              note: '${d.checkedOutSoFar} done',
            ),
          ],
        ),
        Row(
          children: [
            _Stat(
              keyName: 'stat-free',
              label: 'Free rooms',
              value: '${d.roomsFree}',
              note: 'of ${d.roomsTotal}',
            ),
            _Stat(
              keyName: 'stat-occupied',
              label: 'Occupied',
              value: '${d.roomsOccupied}',
              note: d.roomsMaintenance > 0
                  ? '${d.roomsMaintenance} in maintenance'
                  : 'guests in the hotel',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Money', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            _Stat(
              keyName: 'stat-money-today',
              label: 'Today',
              value: formatMoney(d.moneyToday),
            ),
            _Stat(
              keyName: 'stat-money-month',
              label: 'This month',
              value: formatMoney(d.moneyMonth),
            ),
          ],
        ),
        Row(
          children: [
            _Stat(
              keyName: 'stat-online',
              label: 'Online (month)',
              value: formatMoney(d.moneyMonthOnline),
            ),
            _Stat(
              keyName: 'stat-hotel',
              label: 'At hotel (month)',
              value: formatMoney(d.moneyMonthHotel),
            ),
          ],
        ),
        if (d.moneyMonthRefunded > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(
              'Refunded this month: ${formatMoney(d.moneyMonthRefunded)}',
            ),
          ),
        const SizedBox(height: 16),
        Text('Last 7 days', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        _Chart(days: d.days),
        const SizedBox(height: 16),
        Text(
          'Waiting to be paid (${d.pendingCount})',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (d.pending.isEmpty)
          const Text('Nothing is waiting.')
        else
          for (final p in d.pending)
            Card(
              key: Key('pending-${p.id}'),
              margin: const EdgeInsets.only(bottom: 10),
              color: context.pal.surface,
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: context.pal.border, width: 1.2),
              ),
              child: ListTile(
                title: Text(
                  '${p.code} · Room ${p.roomNumber}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: context.pal.text,
                  ),
                ),
                subtitle: Text(
                  '${p.guest}\n${formatShortDate(p.checkIn)} - ${formatShortDate(p.checkOut)} · ${formatMoney(p.amountDue)}',
                  style: TextStyle(fontSize: 12, color: context.pal.textMuted),
                ),
                isThreeLine: true,
                trailing: Icon(Icons.chevron_right, color: context.pal.accent),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => StaffBookingDetailScreen(bookingId: p.id),
                    ),
                  );
                  ref.invalidate(dashboardProvider);
                },
              ),
            ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String keyName;
  final String label;
  final String value;
  final String? note;
  const _Stat({
    required this.keyName,
    required this.label,
    required this.value,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        key: Key(keyName),
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.pal.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.pal.border, width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.pal.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.pal.text,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: 2),
              Text(
                note!,
                style: TextStyle(fontSize: 12, color: context.pal.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bars for bookings made each day. Plain widgets, no chart package.
class _Chart extends StatelessWidget {
  final List<DayStat> days;
  const _Chart({required this.days});

  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final most = days.fold<int>(0, (m, d) => d.bookings > m ? d.bookings : m);
    final color = context.pal.accent;

    return Container(
      decoration: BoxDecoration(
        color: context.pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.pal.border, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final day in days)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${day.bookings}',
                      key: Key('bar-count-${isoDate(day.date)}'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.pal.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      key: Key('bar-${isoDate(day.date)}'),
                      height: most == 0 ? 3 : 3 + 80.0 * day.bookings / most,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _names[day.date.weekday - 1],
                      style: TextStyle(
                        fontSize: 12,
                        color: context.pal.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
