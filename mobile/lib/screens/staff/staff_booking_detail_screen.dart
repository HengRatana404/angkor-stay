import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../models/staff_booking.dart';
import '../../staff/staff_booking_repository.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/status_chip.dart';
import 'take_payment_screen.dart';
import '../../widgets/angkor_app_bar.dart';
import '../../core/theme.dart';

/// One booking: the guest, the money, who did what, and the buttons.
class StaffBookingDetailScreen extends ConsumerStatefulWidget {
  final int bookingId;
  const StaffBookingDetailScreen({super.key, required this.bookingId});

  @override
  ConsumerState<StaffBookingDetailScreen> createState() =>
      _StaffBookingDetailScreenState();
}

class _StaffBookingDetailScreenState
    extends ConsumerState<StaffBookingDetailScreen> {
  bool _busy = false;
  String? _error;

  void _refresh() {
    ref.invalidate(staffBookingProvider(widget.bookingId));
    ref.invalidate(staffBookingsProvider);
  }

  Future<bool> _confirm(String title, String text, String yes) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirm-yes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _run(
    Future<StaffBooking> Function(StaffBookingRepository repo) action,
    String done,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(staffBookingRepositoryProvider));
      _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
      _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkIn(StaffBooking b) async {
    final ok = await _confirm(
      'Check in',
      'Check ${b.guestName} in to room ${b.roomNumber}?',
      'Check in',
    );
    if (ok) await _run((r) => r.checkIn(b.id), '${b.guestName} is checked in.');
  }

  Future<void> _checkOut(StaffBooking b) async {
    final ok = await _confirm(
      'Check out',
      'Check ${b.guestName} out of room ${b.roomNumber}?',
      'Check out',
    );
    if (ok) {
      await _run((r) => r.checkOut(b.id), '${b.guestName} is checked out.');
    }
  }

  Future<void> _takePayment(StaffBooking b) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => TakePaymentScreen(booking: b)));
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(staffBookingProvider(widget.bookingId));

    return Scaffold(
      appBar: AngkorAppBar(title: 'Booking'),
      body: booking.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ErrorBanner('$error'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
        data: (b) => _body(context, b),
      ),
      bottomNavigationBar: booking.maybeWhen(
        data: (b) {
          final buttons = _buttons(b);
          if (buttons.isEmpty) return null;
          return Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).viewPadding.bottom),
            decoration: BoxDecoration(
              color: context.pal.surface,
              border: Border(top: BorderSide(color: context.pal.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: buttons,
            ),
          );
        },
        orElse: () => null,
      ),
    );
  }

  Widget _body(BuildContext context, StaffBooking b) {
    final paid = b.payments.where((p) => p.status == 'paid').toList();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (_error != null) ...[
          ErrorBanner(_error!),
          const SizedBox(height: 16),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                b.code,
                key: const Key('detail-code'),
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: context.pal.text,
                ),
              ),
            ),
            StatusChip(b.status),
          ],
        ),
        const SizedBox(height: 16),

        // ------------------------------------------------------------- guest
        _Section(
          title: 'Guest',
          children: [
            _Row(Icons.person_outline, b.guestName),
            if (b.guest?.phone != null)
              _Row(Icons.phone_outlined, b.guest!.phone!),
            if (b.guest != null) _Row(Icons.email_outlined, b.guest!.email),
          ],
        ),

        // -------------------------------------------------------------- stay
        _Section(
          title: 'Stay',
          children: [
            _Row(
              Icons.meeting_room_outlined,
              '${b.roomTypeName} · Room ${b.roomNumber}',
            ),
            _Row(Icons.login, 'Check-in ${formatShortDate(b.checkIn)}'),
            _Row(Icons.logout, 'Check-out ${formatShortDate(b.checkOut)}'),
            _Row(Icons.nights_stay_outlined, nightsText(b.nights)),
            _Row(
              Icons.people_outline,
              b.guestCount == 1 ? '1 guest' : '${b.guestCount} guests',
            ),
          ],
        ),

        // ------------------------------------------------------------- money
        _Section(
          title: 'Payment',
          children: [
            _Row(
              Icons.attach_money,
              '${formatMoney(b.pricePerNight)} × ${nightsText(b.nights)} = ${formatMoney(b.totalPrice)}',
            ),
            if (b.discountAmount > 0)
              _Row(
                Icons.local_offer_outlined,
                'Online discount ${b.discountPercent}%: -${formatMoney(b.discountAmount)}',
                key: const Key('discount-line'),
              ),
            if (b.isPayingOnline)
              _Row(
                Icons.info_outline,
                'This guest started paying online. Taking payment here closes that online payment and the price is the full ${formatMoney(b.totalPrice)}.',
                key: const Key('paying-online-note'),
              ),
            if (paid.isEmpty)
              _Row(
                Icons.hourglass_empty,
                b.status == 'pending'
                    ? 'Not paid yet. ${formatMoney(b.totalPrice)} to collect.'
                    : 'Not paid.',
                key: const Key('payment-line'),
              )
            else
              for (final p in paid)
                _Row(
                  Icons.check_circle_outline,
                  'Paid ${formatMoney(p.amount)} by ${methodLabel(p.method)}'
                  '${p.receivedBy == null ? '' : ', received by ${p.receivedBy!.name}'}'
                  '${p.paidAt == null ? '' : ' · ${formatDateTime(p.paidAt!)}'}',
                  key: const Key('payment-line'),
                ),
          ],
        ),

        if (b.status == 'no_show' && paid.isNotEmpty)
          const _NoteBox(
            'Marked as a no-show. The guest did not arrive and this payment was not refunded.',
          ),

        // ------------------------------------------------------ who did what
        if (b.checkedInBy != null || b.checkedOutBy != null)
          _Section(
            title: 'History',
            children: [
              if (b.checkedInBy != null)
                _Row(
                  Icons.login,
                  'Checked in by ${b.checkedInBy!.name}${b.checkedInAt == null ? '' : ' · ${formatDateTime(b.checkedInAt!)}'}',
                  key: const Key('checked-in-line'),
                ),
              if (b.checkedOutBy != null)
                _Row(
                  Icons.logout,
                  'Checked out by ${b.checkedOutBy!.name}${b.checkedOutAt == null ? '' : ' · ${formatDateTime(b.checkedOutAt!)}'}',
                  key: const Key('checked-out-line'),
                ),
            ],
          ),

        const SizedBox(height: 8),
      ],
    );
  }

  List<Widget> _buttons(StaffBooking b) {
    final a = b.actions;
    final widgets = <Widget>[];

    if (a.canTakePayment) {
      widgets.add(
        FilledButton.icon(
          key: const Key('take-payment'),
          onPressed: _busy ? null : () => _takePayment(b),
          icon: const Icon(Icons.payments_outlined),
          label: Text('Take payment (${formatMoney(b.totalPrice)})'),
        ),
      );
    }

    if (a.canCheckIn) {
      widgets.add(
        FilledButton.icon(
          key: const Key('check-in'),
          onPressed: _busy ? null : () => _checkIn(b),
          icon: const Icon(Icons.login),
          label: const Text('Check in'),
        ),
      );
    } else if (b.status == 'confirmed' && a.checkInProblem != null) {
      // Paid, but not time yet (or the stay is over): say why.
      widgets.add(
        Text(
          a.checkInProblem!,
          key: const Key('check-in-problem'),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (a.canCheckOut) {
      widgets.add(
        FilledButton.icon(
          key: const Key('check-out'),
          onPressed: _busy ? null : () => _checkOut(b),
          icon: const Icon(Icons.logout),
          label: const Text('Check out'),
        ),
      );
    }

    return [
      for (var i = 0; i < widgets.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        widgets[i],
      ],
    ];
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: pal.text),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Row(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: pal.goldWash,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: pal.goldDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(text, style: TextStyle(color: pal.text, height: 1.25)),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteBox extends StatelessWidget {
  final String text;
  const _NoteBox(this.text);

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: pal.goldWash,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.goldSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: pal.goldDeep),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: pal.goldDeep, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
