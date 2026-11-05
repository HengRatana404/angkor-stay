import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../booking/booking_repository.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/booking.dart';
import '../screens/my_bookings_screen.dart';

/// One message in the bell list.
class AppNotification {
  final IconData icon;
  final String title;
  final String text;

  /// True when the guest should do something (finish a booking, show the QR).
  final bool needsAction;

  /// The booking this message is about; tapping the message opens it.
  final Booking? booking;
  const AppNotification(
    this.icon,
    this.title,
    this.text, {
    this.needsAction = false,
    this.booking,
  });

  AppNotification forBooking(Booking b) =>
      AppNotification(icon, title, text, needsAction: needsAction, booking: b);
}

/// Turns the guest's bookings into messages, newest stays first.
List<AppNotification> buildNotifications(List<Booking> bookings) {
  final list = [...bookings]..sort((a, b) => b.checkIn.compareTo(a.checkIn));
  final out = <AppNotification>[];
  for (final b in list) {
    final dates =
        '${formatShortDate(b.checkIn)} → ${formatShortDate(b.checkOut)}';
    final before = out.length;
    switch (b.status) {
      case 'pending':
        if (b.isKeptForHotel) {
          out.add(
            AppNotification(
              Icons.storefront_outlined,
              'Pay at the hotel',
              'Room ${b.roomNumber} is kept for you ($dates). Pay at the front desk when you arrive.',
              needsAction: true,
            ),
          );
        } else {
          out.add(
            AppNotification(
              Icons.timer_outlined,
              'Your room is held',
              'Room ${b.roomNumber} is held for a few minutes. Finish the booking to keep it.',
              needsAction: true,
            ),
          );
        }
      case 'confirmed':
        out.add(
          AppNotification(
            Icons.event_available_rounded,
            'Booking confirmed',
            '${b.code}: room ${b.roomNumber}, $dates. Show your QR receipt at the front desk.',
            needsAction: true,
          ),
        );
      case 'checked_in':
        out.add(
          AppNotification(
            Icons.login_rounded,
            'Welcome to Angkor Stay',
            'You are checked in to room ${b.roomNumber}. Check-out is on ${formatShortDate(b.checkOut)}.',
          ),
        );
      case 'checked_out':
        out.add(
          AppNotification(
            Icons.logout_rounded,
            'Thank you for staying',
            '${b.code} is complete. We hope to see you again.',
          ),
        );
      case 'cancelled':
        out.add(
          AppNotification(
            Icons.cancel_outlined,
            'Booking cancelled',
            b.refundedAmount > 0
                ? '${b.code} was cancelled. ${formatMoney(b.refundedAmount)} was sent back to you.'
                : '${b.code} was cancelled.',
          ),
        );
      case 'no_show':
        out.add(
          AppNotification(
            Icons.person_off_outlined,
            'Marked as a no-show',
            b.paid
                ? '${b.code}: you did not arrive. This payment was not refunded.'
                : '${b.code}: you did not arrive, so the booking was closed.',
          ),
        );
    }
    if (out.length > before) out[out.length - 1] = out.last.forBooking(b);
  }
  return out;
}

/// The bell in the header: opens the list, shows a dot when something needs the guest.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(myBookingsProvider).value ?? const <Booking>[];
    final needsAction = buildNotifications(bookings).any((n) => n.needsAction);

    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => showNotificationsSheet(context),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded, size: 26),
          if (needsAction)
            Positioned(
              right: 1,
              top: 1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(color: context.pal.strong, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void showNotificationsSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _NotificationsSheet(),
  );
}

class _NotificationsSheet extends ConsumerWidget {
  const _NotificationsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = context.pal;
    final bookings = ref.watch(myBookingsProvider);
    final items = buildNotifications(bookings.value ?? const <Booking>[]);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: pal.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: pal.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: Icon(Icons.close, color: pal.text),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: bookings.isLoading && items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  ? ListView(
                      controller: scroll,
                      padding: const EdgeInsets.all(32),
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 48,
                          color: pal.textMuted,
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'You are all caught up.',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: pal.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: Text(
                            'News about your bookings will show here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: pal.textMuted),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, i) => _NotificationTile(items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification n;
  const _NotificationTile(this.n);

  /// Close the list, then open the booking this message is about.
  void _open(BuildContext context, Booking b) {
    final nav = Navigator.of(context);
    nav.pop();
    nav.push(
      MaterialPageRoute<void>(builder: (_) => BookingDetailScreen(booking: b)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Material(
      color: n.needsAction ? pal.goldWash : pal.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: n.needsAction ? pal.goldSoft : pal.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: n.booking == null ? null : () => _open(context, n.booking!),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: pal.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(n.icon, size: 20, color: pal.goldDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: pal.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      n.text,
                      style: TextStyle(color: pal.textMuted, height: 1.3),
                    ),
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
