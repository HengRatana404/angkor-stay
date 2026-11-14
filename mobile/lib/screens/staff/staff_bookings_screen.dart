import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_provider.dart';
import '../../core/format.dart';
import '../../models/staff_booking.dart';
import '../../staff/staff_booking_repository.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/motion.dart';
import '../../widgets/status_chip.dart';
import 'qr_scanner_screen.dart';
import 'staff_booking_detail_screen.dart';
import '../../core/theme.dart';
import '../../widgets/angkor_app_bar.dart';

/// Every booking, with a search box and status chips.
class StaffBookingsScreen extends ConsumerStatefulWidget {
  const StaffBookingsScreen({super.key});

  @override
  ConsumerState<StaffBookingsScreen> createState() =>
      _StaffBookingsScreenState();
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
      MaterialPageRoute<void>(
        builder: (_) => StaffBookingDetailScreen(bookingId: booking.id),
      ),
    );
    ref.invalidate(staffBookingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(bookingFilterProvider);
    final bookings = ref.watch(staffBookingsProvider);
    final user = ref.watch(authProvider).value;
    final isStaff = user?.role != 'admin';

    return Scaffold(
      appBar: AngkorAppBar(title: 'Bookings'),
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
                suffixIcon: _search.text.isEmpty
                    ? (isStaff
                          ? IconButton(
                              key: const Key('open-camera-scanner'),
                              tooltip: 'Scan QR Code Voucher',
                              icon: Icon(
                                Icons.qr_code_scanner,
                                color: context.pal.accent,
                              ),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const QrScannerScreen(),
                                ),
                              ),
                            )
                          : null)
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          ref
                              .read(bookingFilterProvider.notifier)
                              .setSearch('');
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
                      onSelected: (_) => ref
                          .read(bookingFilterProvider.notifier)
                          .setStatus(status),
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
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                    itemCount: list.length,
                    itemBuilder: (context, i) => FadeSlideIn(
                      index: i,
                      child: _BookingTile(
                        booking: list[i],
                        onTap: () => _open(list[i]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: isStaff
          ? FloatingActionButton.extended(
              key: const Key('staff-scan-fab'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const QrScannerScreen(),
                ),
              ),
              backgroundColor: context.pal.action,
              foregroundColor: context.pal.onAction,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text(
                'Scan QR',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }
}

class _BookingTile extends StatelessWidget {
  final StaffBooking booking;
  final VoidCallback onTap;
  const _BookingTile({
    required this.booking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final pal = context.pal;
    final isPaid = b.paid;
    final isCancelledOrNoShow =
        b.status == 'cancelled' || b.status == 'no_show';
    final payText = isPaid
        ? 'Paid'
        : (isCancelledOrNoShow ? 'Not paid' : 'Not paid yet');

    final (badgeBg, badgeBorder, badgeFg, badgeIcon) = isPaid
        ? (
            pal.successWash,
            pal.successBorder,
            pal.success,
            Icons.check_circle_rounded,
          )
        : isCancelledOrNoShow
        ? (
            pal.surfaceAlt,
            pal.border,
            pal.textMuted,
            Icons.remove_circle_outline,
          )
        : (pal.goldWash, pal.goldSoft, pal.goldDeep, Icons.schedule_rounded);

    final initial = b.guestName.trim().isEmpty
        ? '?'
        : b.guestName.trim()[0].toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PressScale(
        child: Container(
          key: Key('booking-${b.id}'),
          decoration: BoxDecoration(
            color: pal.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: pal.border),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: pal.goldWash,
                      child: Text(
                        initial,
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: pal.goldDeep,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.guestName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: pal.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${b.code} · Room ${b.roomNumber}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: pal.textMuted,
                            ),
                          ),
                          Text(
                            '${formatShortDate(b.checkIn)} → ${formatShortDate(b.checkOut)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: pal.textMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusChip(b.status, paid: isPaid),
                              // The chip already says "Paid"; do not say it twice.
                              if (!(b.status == 'confirmed' && isPaid))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeBg,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: badgeBorder),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(badgeIcon, size: 14, color: badgeFg),
                                    const SizedBox(width: 4),
                                    Text(
                                      payText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: badgeFg,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMoney(b.totalPrice),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: pal.text,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
