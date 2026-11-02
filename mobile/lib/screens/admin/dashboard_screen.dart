import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/admin_repository.dart';
import '../../core/format.dart';
import '../../models/dashboard.dart';
import '../../widgets/error_banner.dart';
import '../staff/staff_booking_detail_screen.dart';

/// The admin's overview: today, rooms, money, bookings waiting to be paid, last 7 days.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dashboardProvider),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ErrorBanner('$e'),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => ref.invalidate(dashboardProvider), child: const Text('Retry')),
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
        Row(children: [
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
        ]),
        Row(children: [
          _Stat(keyName: 'stat-free', label: 'Free rooms', value: '${d.roomsFree}', note: 'of ${d.roomsTotal}'),
          _Stat(
            keyName: 'stat-occupied',
            label: 'Occupied',
            value: '${d.roomsOccupied}',
            note: d.roomsMaintenance > 0 ? '${d.roomsMaintenance} in maintenance' : 'guests in the hotel',
          ),
        ]),
        const SizedBox(height: 16),
        Text('Money', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Row(children: [
          _Stat(keyName: 'stat-money-today', label: 'Today', value: formatMoney(d.moneyToday)),
          _Stat(keyName: 'stat-money-month', label: 'This month', value: formatMoney(d.moneyMonth)),
        ]),
        Row(children: [
          _Stat(keyName: 'stat-online', label: 'Online (month)', value: formatMoney(d.moneyMonthOnline)),
          _Stat(keyName: 'stat-hotel', label: 'At hotel (month)', value: formatMoney(d.moneyMonthHotel)),
        ]),
        if (d.moneyMonthRefunded > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text('Refunded this month: ${formatMoney(d.moneyMonthRefunded)}'),
          ),
        const SizedBox(height: 16),
        Text('Last 7 days', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        _Chart(days: d.days),
        const SizedBox(height: 16),
        Text('Waiting to be paid (${d.pendingCount})', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (d.pending.isEmpty)
          const Text('Nothing is waiting.')
        else
          for (final p in d.pending)
            Card(
              child: ListTile(
                key: Key('pending-${p.id}'),
                title: Text('${p.code} · Room ${p.roomNumber}'),
                subtitle: Text(
                  '${p.guest}\n${formatShortDate(p.checkIn)} - ${formatShortDate(p.checkOut)} · ${formatMoney(p.amountDue)}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => StaffBookingDetailScreen(bookingId: p.id),
                  ));
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
  const _Stat({required this.keyName, required this.label, required this.value, this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        key: Key(keyName),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: theme.textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (note != null) Text(note!, style: theme.textTheme.bodySmall),
          ]),
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
    final color = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                      Text('${day.bookings}', key: Key('bar-count-${isoDate(day.date)}')),
                      const SizedBox(height: 4),
                      Container(
                        key: Key('bar-${isoDate(day.date)}'),
                        height: most == 0 ? 2 : 2 + 80.0 * day.bookings / most,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(height: 4),
                      Text(_names[day.date.weekday - 1], style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
