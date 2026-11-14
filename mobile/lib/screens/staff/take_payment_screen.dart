import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../models/staff_booking.dart';
import '../../staff/staff_booking_repository.dart';
import '../../widgets/error_banner.dart';
import '../../core/theme.dart';
import '../../widgets/angkor_app_bar.dart';
import '../../widgets/top_message.dart';

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
  double? _cashGiven;

  Future<void> _confirm() async {
    final b = widget.booking;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(staffBookingRepositoryProvider).takePayment(b.id, _method);
      if (!mounted) return;
      final top = TopMessage.of(context);
      Navigator.of(context).pop();
      top.show(
        'Payment of ${formatMoney(b.totalPrice)} saved (${methodLabel(_method)}).',
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

    final double change = (_cashGiven != null && _cashGiven! >= b.totalPrice)
        ? _cashGiven! - b.totalPrice
        : 0.0;

    return Scaffold(
      appBar: AngkorAppBar(title: 'Take payment'),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_error != null) ...[
            ErrorBanner(_error!),
            const SizedBox(height: 16),
          ],
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.pal.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.pal.border, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.pal.strong,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${b.code} · ${b.guestName}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: context.pal.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  formatMoney(b.totalPrice),
                  key: const Key('amount'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'serif',
                    color: context.pal.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatMoney(b.pricePerNight)} × ${nightsText(b.nights)}. No discount at the hotel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: context.pal.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            key: const Key('method'),
            segments: const [
              ButtonSegment(
                value: 'khqr',
                label: Text('KHQR'),
                icon: Icon(Icons.qr_code_2),
              ),
              ButtonSegment(
                value: 'cash',
                label: Text('Cash'),
                icon: Icon(Icons.payments_outlined),
              ),
              ButtonSegment(
                value: 'card',
                label: Text('Card'),
                icon: Icon(Icons.credit_card),
              ),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          const SizedBox(height: 20),
          if (_method == 'khqr') ...[
            Center(
              child: Container(
                key: const Key('qr'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white, // a QR code needs a light background to scan, also in dark mode
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.pal.border, width: 1.2),
                ),
                child: QrImageView(
                  data:
                      'ANGKORSTAY|${b.code}|${b.totalPrice.toStringAsFixed(2)}|USD',
                  size: 210,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Let the guest scan this and pay. Press the button only after the money arrived in the hotel account. '
              'This is a demo code. A real hotel shows its own Bakong KHQR here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ] else if (_method == 'cash') ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.pal.page,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.pal.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cash change calculator',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: context.pal.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final bill in [20.0, 30.0, 50.0, 100.0])
                        ActionChip(
                          label: Text('\$${bill.toInt()} bill'),
                          backgroundColor: _cashGiven == bill
                              ? context.pal.accent
                              : Colors.white,
                          onPressed: () => setState(() => _cashGiven = bill),
                        ),
                      if (_cashGiven != null)
                        ActionChip(
                          avatar: const Icon(Icons.clear, size: 14),
                          label: const Text('Reset'),
                          onPressed: () => setState(() => _cashGiven = null),
                        ),
                    ],
                  ),
                  if (_cashGiven != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _cashGiven! >= b.totalPrice
                            ? context.pal.successWash
                            : context.pal.dangerWash,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _cashGiven! >= b.totalPrice
                              ? context.pal.successBorder
                              : context.pal.dangerBorder,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _cashGiven! >= b.totalPrice
                                ? 'Change to return:'
                                : 'Need \$${(b.totalPrice - _cashGiven!).toStringAsFixed(2)} more',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _cashGiven! >= b.totalPrice
                                  ? context.pal.success
                                  : context.pal.danger,
                            ),
                          ),
                          Text(
                            formatMoney(change),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: _cashGiven! >= b.totalPrice
                                  ? context.pal.success
                                  : context.pal.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Take the cash from the guest, then press the button.',
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const Text(
              'Use the card machine, then press the button when it says approved.',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('confirm-payment'),
            onPressed: _busy ? null : _confirm,
            style: FilledButton.styleFrom(
              backgroundColor: context.pal.action,
              foregroundColor: context.pal.onAction,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _busy
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.pal.accent,
                    ),
                  )
                : Text(
                    'Guest paid ${formatMoney(b.totalPrice)} by ${methodLabel(_method)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
