import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../booking/booking_repository.dart';
import '../core/api_error.dart';
import '../core/format.dart';
import '../models/booking.dart';
import '../widgets/error_banner.dart';
import '../widgets/status_chip.dart';

/// All the guest's bookings. Tap one to see the QR receipt or cancel.
class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
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
          data: (list) => list.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(32),
                  children: const [Center(child: Text('You have no bookings yet.'))],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _BookingTile(booking: list[i]),
                ),
        ),
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  final Booking booking;
  const _BookingTile({required this.booking});

  String get _payText {
    if (booking.status == 'cancelled' || booking.status == 'no_show') {
      return booking.refundedAmount > 0
          ? 'Refunded ${formatMoney(booking.refundedAmount)}'
          : 'Not paid';
    }
    return booking.paid ? 'Paid' : 'Not paid yet';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => BookingDetailScreen(booking: booking)),
        ),
        title: Text('${booking.code}  ·  Room ${booking.roomNumber}'),
        subtitle: Text(
          '${booking.roomTypeName}\n'
          '${formatShortDate(booking.checkIn)} - ${formatShortDate(booking.checkOut)}  ·  $_payText',
        ),
        isThreeLine: true,
        trailing: StatusChip(booking.status),
      ),
    );
  }
}

/// One booking: details, QR receipt and the cancel button.
class BookingDetailScreen extends ConsumerStatefulWidget {
  final Booking booking;
  const BookingDetailScreen({super.key, required this.booking});

  @override
  ConsumerState<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  late Booking _booking = widget.booking;
  bool _busy = false;
  String? _error;

  Future<void> _cancel() async {
    final paidOnline = _booking.paid;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(paidOnline
            ? 'Your money (${formatMoney(_booking.toPay)}) will be sent back in full.'
            : 'The room will be let go.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel booking')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref.read(bookingRepositoryProvider).cancel(_booking.id);
      ref.invalidate(myBookingsProvider);
      if (mounted) setState(() => _booking = updated);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    final showQr = b.status == 'confirmed' || b.status == 'checked_in' || b.isKeptForHotel;

    return Scaffold(
      appBar: AppBar(title: Text(b.code)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(children: [
            Expanded(child: Text('Room ${b.roomNumber} · ${b.roomTypeName}',
                style: Theme.of(context).textTheme.titleLarge)),
            StatusChip(b.status),
          ]),
          const SizedBox(height: 12),
          Text('${formatShortDate(b.checkIn)} - ${formatShortDate(b.checkOut)}  (${nightsText(b.nights)})'),
          Text('${b.guests} guest${b.guests == 1 ? '' : 's'}'),
          const SizedBox(height: 12),
          if (b.hasDiscount) Text('Online discount: -${formatMoney(b.discountAmount)}'),
          Text('Total: ${formatMoney(b.toPay)}', style: Theme.of(context).textTheme.titleMedium),
          Text(b.paid
              ? 'Paid${b.paymentMethod == null ? '' : ' (${b.paymentDetail ?? methodLabel(b.paymentMethod!)})'}'
              : b.refundedAmount > 0
                  ? 'Refunded ${formatMoney(b.refundedAmount)}'
                  : 'Not paid yet'),
          if (showQr) ...[
            const SizedBox(height: 24),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: b.code, size: 200),
              ),
            ),
            const SizedBox(height: 8),
            const Center(child: Text('Show this QR receipt at the front desk.')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(_error!),
          ],
          if (b.canCancel) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _busy ? null : _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: Text(_busy ? 'Cancelling...' : 'Cancel booking'),
            ),
          ] else if (b.status == 'confirmed' && b.paid && b.paymentMethod != 'online') ...[
            const SizedBox(height: 24),
            const Text('You paid at the front desk. Ask them if you need to cancel.'),
          ],
        ],
      ),
    );
  }
}
