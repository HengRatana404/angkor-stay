import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../booking/booking_repository.dart';
import '../core/api_error.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/booking.dart';
import '../widgets/angkor_app_bar.dart';
import '../widgets/error_banner.dart';
import '../widgets/motion.dart';
import '../widgets/room_photo.dart';
import '../widgets/status_chip.dart';
import 'booking_hold_screen.dart';

bool _isEnded(String status) =>
    status == 'cancelled' || status == 'no_show' || status == 'checked_out';

/// What to tell the guest about the money for this booking. Always follows the real payment.
String bookingPayText(Booking b) {
  if (b.refundedAmount > 0) return 'Refunded ${formatMoney(b.refundedAmount)}';
  if (b.paid) {
    final how = b.paymentMethod == null
        ? ''
        : ' (${b.paymentDetail ?? methodLabel(b.paymentMethod!)})';
    return 'Paid ${formatMoney(b.toPay)}$how';
  }
  if (b.status == 'cancelled' || b.status == 'no_show') {
    return 'No payment taken';
  }
  return 'Not paid yet';
}

/// Asks first, then cancels. Returns the updated booking, or null when the guest kept it.
/// Throws [ApiError] when the server refuses.
Future<Booking?> confirmAndCancel(
  BuildContext context,
  WidgetRef ref,
  Booking b,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cancel this booking?'),
      content: Text(
        b.paid
            ? 'Your money (${formatMoney(b.toPay)}) will be sent back in full.'
            : 'The room will be let go.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Cancel booking'),
        ),
      ],
    ),
  );
  if (ok != true) return null;
  final updated = await ref.read(bookingRepositoryProvider).cancel(b.id);
  ref.invalidate(myBookingsProvider);
  return updated;
}

/// Asks twice before deleting for good. True only when the guest says yes both times.
Future<bool> confirmDeleteTwice(BuildContext context) async {
  final first = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this booking?'),
      content: const Text(
        'It will be deleted from your account. The hotel keeps its own record of the stay.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          key: const Key('delete-first'),
          style: FilledButton.styleFrom(
            backgroundColor: ctx.pal.danger,
            foregroundColor: ctx.pal.onAction,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (first != true || !context.mounted) return false;

  final second = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Are you sure?'),
      content: const Text(
        'This cannot be undone. You will not see this booking again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('No, keep it'),
        ),
        FilledButton(
          key: const Key('delete-second'),
          style: FilledButton.styleFrom(
            backgroundColor: ctx.pal.danger,
            foregroundColor: ctx.pal.onAction,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Yes, delete it'),
        ),
      ],
    ),
  );
  return second == true;
}

/// Deletes a finished booking after asking twice. False when the guest changed their mind.
/// Throws [ApiError] when the server refuses.
Future<bool> deleteBooking(
  BuildContext context,
  WidgetRef ref,
  Booking b,
) async {
  if (!await confirmDeleteTwice(context)) return false;
  await ref.read(bookingRepositoryProvider).delete(b.id);
  ref.invalidate(myBookingsProvider);
  return true;
}

/// All the guest's bookings. Tap one for the QR receipt. Swipe left to cancel, or to delete a finished one.
class MyBookingsScreen extends ConsumerWidget {
  /// True when shown as a tab inside the guest shell (no back arrow).
  final bool embedded;
  const MyBookingsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AngkorAppBar(title: 'My bookings', showBack: !embedded),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myBookingsProvider);
          try {
            await ref.read(myBookingsProvider.future);
          } catch (_) {}
        },
        child: bookings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ErrorBanner('$e'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => ref.invalidate(myBookingsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
          data: (list) {
            if (list.isEmpty) return const _Empty();

            final current = list.where((b) => !_isEnded(b.status)).toList();
            final past = list.where((b) => _isEnded(b.status)).toList();
            var i = 0;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (current.isNotEmpty) ...[
                  _SectionTitle('Current'),
                  for (final b in current)
                    FadeSlideIn(
                      index: i++,
                      child: _BookingTile(booking: b),
                    ),
                ],
                if (past.isNotEmpty) ...[
                  _SectionTitle('Past'),
                  for (final b in past)
                    FadeSlideIn(
                      index: i++,
                      child: _BookingTile(booking: b),
                    ),
                ],
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    'Swipe a booking left to cancel it, or to delete it once it is finished.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.pal.textMuted,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.luggage_outlined, size: 56, color: pal.goldDeep),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'You have no bookings yet.',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: pal.text,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Pick a room on the Home tab and your stay will show up here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: pal.textMuted),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: context.pal.text,
      ),
    ),
  );
}

class _BookingTile extends ConsumerWidget {
  final Booking booking;
  const _BookingTile({required this.booking});

  Color _payColor(AngkorPalette pal) {
    if (booking.paid) return pal.success;
    if (booking.refundedAmount > 0) return pal.goldDeep;
    if (_isEnded(booking.status)) return pal.textMuted;
    return pal.goldDeep;
  }

  IconData get _payIcon {
    if (booking.paid) return Icons.check_circle_rounded;
    if (booking.refundedAmount > 0) return Icons.undo_rounded;
    if (_isEnded(booking.status)) return Icons.remove_circle_outline;
    return Icons.schedule_rounded;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = context.pal;
    final b = booking;
    final ended = _isEnded(b.status);

    final card = PressScale(
      child: Container(
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
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BookingDetailScreen(booking: b),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: Opacity(
                        opacity: ended ? 0.55 : 1,
                        child: RoomPhoto(url: b.coverImage, height: 72),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                b.code,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: pal.textMuted,
                                ),
                              ),
                            ),
                            StatusChip(b.status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Room ${b.roomNumber} · ${b.roomTypeName}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: pal.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatShortDate(b.checkIn)} → ${formatShortDate(b.checkOut)} · ${nightsText(b.nights)}',
                          style: TextStyle(fontSize: 13, color: pal.textMuted),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(_payIcon, size: 15, color: _payColor(pal)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                bookingPayText(b),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _payColor(pal),
                                ),
                              ),
                            ),
                            if (!ended)
                              Icon(
                                Icons.qr_code_2,
                                size: 20,
                                color: pal.goldDeep,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final canSwipe = b.canCancel || ended;
    final wrapped = canSwipe
        ? Dismissible(
            key: ValueKey('booking-${b.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 22),
              decoration: BoxDecoration(
                color: ended ? pal.surfaceAlt : pal.dangerWash,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    ended ? 'Delete' : 'Cancel',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: pal.danger,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    ended ? Icons.delete_outline : Icons.cancel_outlined,
                    color: pal.danger,
                  ),
                ],
              ),
            ),
            confirmDismiss: (_) async {
              try {
                // A finished booking is deleted after two questions; a running one is cancelled.
                if (ended) return await deleteBooking(context, ref, b);
                await confirmAndCancel(context, ref, b);
              } on ApiError catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
              return false; // a cancelled booking stays in the list as "Cancelled"
            },
            onDismissed: (_) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text('Booking deleted')),
                );
            },
            child: card,
          )
        : card;

    return Padding(padding: const EdgeInsets.only(bottom: 12), child: wrapped);
  }
}

/// One booking: details, QR receipt, cancel or remove.
class BookingDetailScreen extends ConsumerStatefulWidget {
  final Booking booking;
  const BookingDetailScreen({super.key, required this.booking});

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  late Booking _booking = widget.booking;
  bool _busy = false;
  String? _error;

  Future<void> _cancel() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await confirmAndCancel(context, ref, _booking);
      if (updated != null && mounted) setState(() => _booking = updated);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Open the pay screen again for a room that is still held.
  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Ask the server again: the hold may have run out in the meantime.
      final fresh = (await ref.read(bookingRepositoryProvider).mine())
          .where((x) => x.id == _booking.id)
          .firstOrNull;
      if (fresh == null) return;
      if (!mounted) return;
      setState(() => _booking = fresh);
      if (fresh.status == 'pending' && (fresh.holdSecondsLeft ?? 0) > 0) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BookingHoldScreen(booking: fresh),
          ),
        );
        ref.invalidate(myBookingsProvider);
        if (mounted) Navigator.of(context).pop();
      } else {
        ref.invalidate(myBookingsProvider);
        setState(() => _error = 'This room is no longer held.');
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await deleteBooking(context, ref, _booking);
      if (done && mounted) Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    final pal = context.pal;
    final ended = _isEnded(b.status);
    final showQr =
        b.status == 'confirmed' || b.status == 'checked_in' || b.isKeptForHotel;

    return Scaffold(
      appBar: AngkorAppBar(title: b.code),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          FadeSlideIn(index: 0, child: _summary(context, b)),
          const SizedBox(height: 14),
          FadeSlideIn(index: 1, child: _payment(context, b)),
          if (showQr) ...[
            const SizedBox(height: 14),
            FadeSlideIn(index: 2, child: _qr(context, b)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(_error!),
          ],
          if (b.status == 'pending' &&
              !b.paid &&
              (b.holdSecondsLeft ?? 0) > 0) ...[
            const SizedBox(height: 22),
            FilledButton.icon(
              key: const Key('pay-now'),
              onPressed: _busy ? null : _pay,
              icon: const Icon(Icons.payments_outlined),
              label: Text(_busy ? 'Please wait...' : 'Pay now'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
          if (b.canCancel) ...[
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: _busy ? null : _cancel,
              icon: Icon(Icons.cancel_outlined, color: pal.danger),
              label: Text(
                _busy ? 'Cancelling...' : 'Cancel booking',
                style: TextStyle(color: pal.danger),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: pal.danger),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ] else if (b.status == 'confirmed' &&
              b.paid &&
              b.paymentMethod != 'online') ...[
            const SizedBox(height: 22),
            Text(
              'You paid at the front desk. Ask them if you need to cancel.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: pal.textMuted),
            ),
          ],
          if (ended) ...[
            const SizedBox(height: 18),
            TextButton.icon(
              key: const Key('delete-booking'),
              onPressed: _busy ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: pal.danger),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete booking'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required Widget child,
    EdgeInsets? padding,
  }) {
    final pal = context.pal;
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: pal.border),
      ),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: child,
    );
  }

  Widget _summary(BuildContext context, Booking b) {
    final pal = context.pal;
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoomPhoto(url: b.coverImage, height: 150),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Room ${b.roomNumber} · ${b.roomTypeName}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: pal.text,
                        ),
                      ),
                    ),
                    StatusChip(b.status),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _when(
                        context,
                        'Check-in',
                        b.checkIn,
                        'From 14:00',
                        CrossAxisAlignment.start,
                      ),
                    ),
                    Expanded(
                      child: _when(
                        context,
                        'Check-out',
                        b.checkOut,
                        'Until 12:00',
                        CrossAxisAlignment.end,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.people_outline, size: 18, color: pal.goldDeep),
                    const SizedBox(width: 6),
                    Text(
                      '${b.guests} guest${b.guests == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: pal.text,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: pal.goldWash,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: pal.goldSoft),
                      ),
                      child: Text(
                        nightsText(b.nights),
                        style: TextStyle(
                          color: pal.goldDeep,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _when(
    BuildContext context,
    String label,
    DateTime d,
    String time,
    CrossAxisAlignment align,
  ) {
    final pal = context.pal;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: pal.textMuted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          formatShortDate(d),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: pal.text,
          ),
        ),
        Text(time, style: TextStyle(fontSize: 12, color: pal.textMuted)),
      ],
    );
  }

  Widget _payment(BuildContext context, Booking b) {
    final pal = context.pal;
    final paid = b.paid;
    final refunded = b.refundedAmount > 0;
    final tone = paid
        ? (
            pal.successWash,
            pal.successBorder,
            pal.success,
            Icons.check_circle_rounded,
          )
        : refunded
        ? (pal.goldWash, pal.goldSoft, pal.goldDeep, Icons.undo_rounded)
        : _isEnded(b.status)
        ? (
            pal.surfaceAlt,
            pal.border,
            pal.textMuted,
            Icons.remove_circle_outline,
          )
        : (pal.goldWash, pal.goldSoft, pal.goldDeep, Icons.schedule_rounded);

    Widget line(String a, String c, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            a,
            style: TextStyle(
              color: bold ? pal.text : pal.textMuted,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          Text(
            c,
            style: TextStyle(
              color: pal.text,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return _card(
      context,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Payment',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: pal.text,
            ),
          ),
          const SizedBox(height: 8),
          line(
            '${formatMoney(b.pricePerNight)} × ${nightsText(b.nights)}',
            formatMoney(b.totalPrice),
          ),
          if (b.hasDiscount)
            line('Online discount', '-${formatMoney(b.discountAmount)}'),
          const Divider(height: 18),
          line('Total', formatMoney(b.toPay), bold: true),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: tone.$1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tone.$2),
            ),
            child: Row(
              children: [
                Icon(tone.$4, size: 18, color: tone.$3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bookingPayText(b),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: tone.$3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qr(BuildContext context, Booking b) {
    final pal = context.pal;
    return _card(
      context,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white, // a QR code needs a light background to scan
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.pal.accent, width: 1.5),
            ),
            child: QrImageView(data: b.code, size: 180),
          ),
          const SizedBox(height: 10),
          Text(
            'Booking #${b.code}',
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: pal.text,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Show this QR receipt at the front desk.',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: pal.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
