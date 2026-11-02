import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../models/staff_booking.dart';
import '../../staff/staff_booking_repository.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/status_chip.dart';
import 'staff_booking_detail_screen.dart';

/// Every booking, with a search box and status chips.
class StaffBookingsScreen extends ConsumerStatefulWidget {
  const StaffBookingsScreen({super.key});

  @override
  ConsumerState<StaffBookingsScreen> createState() => _StaffBookingsScreenState();
}

class _StaffBookingsScreenState extends ConsumerState<StaffBookingsScreen> {
  static const _filters = <(String?, String)>[
    (null, 'All'),
    ('pending', 'Waiting for payment'),
    ('confirmed', 'Confirmed'),
    ('checked_in', 'Checked in'),
    ('checked_out', 'Checked out'),
    ('cancelled', 'Cancelled'),
    ('no_show', 'No-show'),
  ];

  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Wait a moment after the last letter, so we do not ask the server for every key.
  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(bookingFilterProvider.notifier).setSearch(text);
    });
  }

  Future<void> _open(StaffBooking booking) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StaffBookingDetailScreen(bookingId: booking.id)),
    );
    ref.invalidate(staffBookingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(bookingFilterProvider);
    final bookings = ref.watch(staffBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bookings')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              key: const Key('booking-search'),
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Name, phone, email, room or code (AS-0012)',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          ref.read(bookingFilterProvider.notifier).setSearch('');
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (status, label) in _filters)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      key: Key('filter-${status ?? 'all'}'),
                      label: Text(label),
                      selected: filter.status == status,
                      onSelected: (_) => ref.read(bookingFilterProvider.notifier).setStatus(status),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(staffBookingsProvider);
                try {
                  await ref.read(staffBookingsProvider.future);
                } catch (_) {}
              },
              child: bookings.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    ErrorBanner('$error'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(staffBookingsProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.all(24),
                      children: const [
                        SizedBox(height: 48),
                        Icon(Icons.event_busy, size: 64),
                        SizedBox(height: 16),
                        Text('No bookings found.', textAlign: TextAlign.center),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _BookingTile(booking: list[i], onTap: () => _open(list[i])),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  final StaffBooking booking;
  final VoidCallback onTap;
  const _BookingTile({required this.booking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    return ListTile(
      key: Key('booking-${b.id}'),
      onTap: onTap,
      title: Text('${b.code} · Room ${b.roomNumber}'),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(b.guestName),
            Text('${formatShortDate(b.checkIn)} → ${formatShortDate(b.checkOut)}'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                StatusChip(b.status),
                if (b.paid) const Chip(label: Text('Paid'), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
        ),
      ),
      isThreeLine: true,
      trailing: Text(formatMoney(b.totalPrice), style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
