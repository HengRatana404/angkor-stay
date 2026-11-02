import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../models/staff_booking.dart';
import '../../staff/staff_booking_repository.dart';
import '../../widgets/error_banner.dart';

/// Staff take the money at the front desk: KHQR, cash or card.
/// The amount is always the booking's own total. There is no discount here.
class TakePaymentScreen extends ConsumerStatefulWidget {
  final StaffBooking booking;
  const TakePaymentScreen({super.key, required this.booking});

  @override
  ConsumerState<TakePaymentScreen> createState() => _TakePaymentScreenState();
}

class _TakePaymentScreenState extends ConsumerState<TakePaymentScreen> {
  String _method = 'cash';
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    final b = widget.booking;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(staffBookingRepositoryProvider).takePayment(b.id, _method);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Payment of ${formatMoney(b.totalPrice)} saved (${methodLabel(_method)}).')),
      );
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Take payment')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
          Text('${b.code} · ${b.guestName}', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            formatMoney(b.totalPrice),
            key: const Key('amount'),
            textAlign: TextAlign.center,
            style: theme.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            '${formatMoney(b.pricePerNight)} × ${nightsText(b.nights)}. No discount at the hotel.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SegmentedButton<String>(
            key: const Key('method'),
            segments: const [
              ButtonSegment(value: 'khqr', label: Text('KHQR'), icon: Icon(Icons.qr_code_2)),
              ButtonSegment(value: 'cash', label: Text('Cash'), icon: Icon(Icons.payments_outlined)),
              ButtonSegment(value: 'card', label: Text('Card'), icon: Icon(Icons.credit_card)),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 24),
          if (_method == 'khqr') ...[
            Center(
              child: Container(
                key: const Key('qr'),
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: QrImageView(
                  data: 'ANGKORSTAY|${b.code}|${b.totalPrice.toStringAsFixed(2)}|USD',
                  size: 220,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Let the guest scan this and pay. Press the button only after the money arrived in the hotel account. '
              'This is a demo code. A real hotel shows its own Bakong KHQR here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ] else if (_method == 'cash')
            const Text('Take the cash from the guest, then press the button.', textAlign: TextAlign.center)
          else
            const Text('Use the card machine, then press the button when it says approved.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('confirm-payment'),
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('Guest paid ${formatMoney(b.totalPrice)} by ${methodLabel(_method)}'),
          ),
        ],
      ),
    );
  }
}
