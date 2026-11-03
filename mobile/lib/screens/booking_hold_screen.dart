import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../booking/booking_repository.dart';
import '../core/api_error.dart';
import '../core/format.dart';
import '../core/public_settings_provider.dart';
import '../models/booking.dart';
import '../rooms/room_types_provider.dart';
import '../widgets/card_formatters.dart';
import '../widgets/error_banner.dart';
import '../widgets/room_photo.dart';

/// Where the guest is while paying.
enum _Step {
  /// Choosing: card, QR code or at the hotel.
  choose,

  /// Typing a card.
  card,

  /// Showing a QR code and waiting for "I have paid".
  qr,
}

/// Shown right after booking. The room is held while the guest chooses how to pay.
/// - Pay at the hotel: the room is kept with no countdown.
/// - Pay by card or QR: the payment is simulated, but the SERVER saves it in the database and checks it there.
class BookingHoldScreen extends ConsumerStatefulWidget {
  final Booking booking;
  const BookingHoldScreen({super.key, required this.booking});

  @override
  ConsumerState<BookingHoldScreen> createState() => _BookingHoldScreenState();
}

class _BookingHoldScreenState extends ConsumerState<BookingHoldScreen> {
  static const _firstHoldSeconds = 300; // the server holds a room for 5 minutes

  late Booking _booking = widget.booking;
  _Step _step = _Step.choose;
  QrPayment? _qr;

  // The card form.
  final _number = TextEditingController();
  final _holder = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  Map<String, String> _fieldErrors = {};

  // The server tells us how many seconds are left, and we count down from
  // there. We never compare with the phone's clock, which may be wrong.
  final _stopwatch = clock.stopwatch()..start();
  late int _startSeconds = widget.booking.holdSecondsLeft ?? 0;
  late int _totalSeconds = _startSeconds > 0 ? _startSeconds : _firstHoldSeconds;
  Timer? _timer;

  bool _busy = false;
  String? _error;
  String? _info;

  int get _remaining {
    final left = _startSeconds - _stopwatch.elapsed.inSeconds;
    return left < 0 ? 0 : left;
  }

  bool get _paid => _booking.isPaidAndConfirmed;
  bool get _kept => _booking.isKeptForHotel;
  bool get _expired => !_kept && !_paid && _remaining == 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_number, _holder, _expiry, _cvv]) {
      c.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {});
      if (_expired || _paid || _kept) {
        t.cancel();
        // The room may be free again, so the list must show the new numbers.
        if (_expired) ref.invalidate(roomTypesProvider);
      }
    });
  }

  /// Paying online gives more time. Start counting again from what the server says.
  void _resetCountdown(int seconds) {
    _startSeconds = seconds;
    _totalSeconds = seconds > 0 ? seconds : _totalSeconds;
    _stopwatch
      ..reset()
      ..start();
    _startTimer();
  }

  void _backToRooms() {
    ref.invalidate(roomTypesProvider);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _fieldErrors = {};
    });
    try {
      await action();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ----------------------------------------------------------------- actions

  Future<void> _release() => _run(() async {
        await ref.read(bookingRepositoryProvider).release(_booking.id);
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final kept = _kept;
        _backToRooms();
        messenger.showSnackBar(
          SnackBar(content: Text(kept ? 'The booking was cancelled.' : 'The room was released.')),
        );
      });

  Future<void> _payAtHotel() => _run(() async {
        final kept = await ref.read(bookingRepositoryProvider).payAtHotel(_booking.id);
        if (!mounted) return;
        _timer?.cancel(); // no countdown any more
        ref.invalidate(roomTypesProvider);
        setState(() {
          _booking = kept;
          _step = _Step.choose;
          _qr = null;
        });
      });

  /// The guest sends the card. The server checks the fields, saves the payment in the database,
  /// checks it there, and confirms the booking.
  Future<void> _payByCard() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
      _fieldErrors = {};
    });
    try {
      final confirmed = await ref.read(bookingRepositoryProvider).payByCard(
            _booking.id,
            number: _number.text,
            holder: _holder.text.trim(),
            expiry: _expiry.text.trim(),
            cvv: _cvv.text.trim(),
          );
      if (!mounted) return;
      _timer?.cancel();
      ref.invalidate(roomTypesProvider);
      setState(() => _booking = confirmed);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = e.fieldErrors;
        // A field problem is shown under the field. Anything else goes in the banner.
        _error = e.fieldErrors.isEmpty ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The guest wants to pay with a QR code: the server opens the payment and gives us the QR text.
  Future<void> _startQr() => _run(() async {
        final qr = await ref.read(bookingRepositoryProvider).startQr(_booking.id);
        if (!mounted) return;

        setState(() {
          _booking = qr.booking;
          _qr = qr;
          _step = _Step.qr;
        });
        final seconds = qr.booking.holdSecondsLeft ?? qr.secondsLeft;
        _resetCountdown(seconds);
      });

  /// "I have paid." The server finds the QR payment in the database and checks it.
  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final confirmed = await ref.read(bookingRepositoryProvider).verifyPayment(_booking.id);
      if (!mounted) return;
      _timer?.cancel();
      ref.invalidate(roomTypesProvider);
      setState(() => _booking = confirmed);
    } on ApiError catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'payment_expired' || 'payment_not_open' || 'no_payment_started':
          setState(() {
            _error = e.message;
            _step = _Step.choose;
            _qr = null;
          });
        default:
          setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _chooseAnotherWay() => setState(() {
        _step = _Step.choose;
        _error = null;
        _info = null;
        _fieldErrors = {};
      });

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    final theme = Theme.of(context);

    final title = _paid
        ? 'Booked and paid'
        : _kept
            ? 'Room kept for you'
            : 'Your room is held';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToRooms();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _backToRooms),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
            if (_info != null) ...[
              Text(_info!, key: const Key('info'), textAlign: TextAlign.center),
              const SizedBox(height: 16),
            ],
            if (_paid)
              _paidCard(theme, b)
            else if (_kept)
              _keptCard(theme, b)
            else
              _countdownCard(theme, b),
            const SizedBox(height: 16),
            _summaryCard(theme, b),
            const SizedBox(height: 16),
            ..._actions(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(ThemeData theme) {
    final backButton = FilledButton(onPressed: _backToRooms, child: const Text('Back to rooms'));

    if (_paid) return [backButton];

    if (_kept) {
      return [
        backButton,
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('cancel-kept'),
          onPressed: _busy ? null : _release,
          child: const Text('Cancel this booking'),
        ),
      ];
    }

    if (_expired) return [backButton];

    return [
      ...switch (_step) {
        _Step.choose => _choices(theme),
        _Step.card => [_cardForm(theme), const SizedBox(height: 16)],
        _Step.qr => [_qrCard(theme), const SizedBox(height: 16)],
      },
      OutlinedButton(
        onPressed: _busy ? null : _release,
        child: const Text('Release this room'),
      ),
    ];
  }

  // --------------------------------------------------------------- the cards

  Widget _countdownCard(ThemeData theme, Booking b) {
    final progress = (_remaining / _totalSeconds).clamp(0.0, 1.0);

    return Card(
      color: _expired ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(_expired ? Icons.timer_off_outlined : Icons.timer_outlined, size: 40),
            const SizedBox(height: 8),
            Text(
              _expired ? 'Hold ran out' : formatCountdown(_remaining),
              key: const Key('countdown'),
              style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _expired
                  ? 'The room is free again. You can book it again.'
                  : 'Room ${b.roomNumber} is kept for you. Please finish before the time runs out.',
              textAlign: TextAlign.center,
            ),
            if (!_expired) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paidCard(ThemeData theme, Booking b) {
    final how = b.paymentDetail == null ? 'online' : 'online with ${b.paymentDetail}';

    return Card(
      key: const Key('paid-card'),
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.verified_outlined, size: 40, color: Colors.green.shade700),
            const SizedBox(height: 8),
            Text('Room ${b.roomNumber} is yours', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text('Your booking number', style: TextStyle(fontSize: 13)),
            Text(
              b.code,
              key: const Key('booking-code'),
              style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            const SizedBox(height: 12),
            Text(
              'Paid ${formatMoney(b.toPay)} $how.'
              '${b.hasDiscount ? ' You saved ${formatMoney(b.discountAmount)} (${b.discountPercent}% off).' : ''}',
              key: const Key('paid-text'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Show this number at the front desk when you arrive.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keptCard(ThemeData theme, Booking b) {
    return Card(
      key: const Key('kept-card'),
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline, size: 40, color: Colors.green.shade700),
            const SizedBox(height: 8),
            Text('Room ${b.roomNumber} is yours', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text('Your booking number', style: TextStyle(fontSize: 13)),
            Text(
              b.code,
              key: const Key('booking-code'),
              style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
            const SizedBox(height: 12),
            Text(
              'Tell this number at the front desk. You pay ${formatMoney(b.totalPrice)} when you arrive.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Paying at the hotel has no discount.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  /// The price after the online discount, from the public setting. The server sets the real one.
  double get _onlineDue {
    final percent = ref.watch(publicSettingsProvider).value?.onlineDiscountPercent ?? 0;
    return onlinePrice(_booking.totalPrice, percent).due;
  }

  Widget _cardForm(ThemeData theme) {
    final payButton = FilledButton(
      key: const Key('card-pay'),
      onPressed: _busy ? null : _payByCard,
      child: _busy
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Text('Pay ${formatMoney(_onlineDue)}'),
    );

    return Card(
      key: const Key('card-form'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pay by card', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'This is a practice payment. Any card number works. No money moves.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('card-number'),
              controller: _number,
              keyboardType: TextInputType.number,
              inputFormatters: [CardNumberFormatter()],
              decoration: InputDecoration(
                labelText: 'Card number',
                prefixIcon: const Icon(Icons.credit_card),
                errorText: _fieldErrors['number'],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('card-holder'),
              controller: _holder,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Name on the card', errorText: _fieldErrors['holder']),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('card-expiry'),
                    controller: _expiry,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ExpiryFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Expires (MM/YY)',
                      hintText: '11/26',
                      errorText: _fieldErrors['expiry'],
                      errorMaxLines: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const Key('card-cvv'),
                    controller: _cvv,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    decoration: InputDecoration(labelText: 'CVV', errorText: _fieldErrors['cvv']),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            payButton,
            TextButton(
              key: const Key('another-way'),
              onPressed: _busy ? null : _chooseAnotherWay,
              child: const Text('Choose another way to pay'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qrCard(ThemeData theme) {
    final qr = _qr;
    if (qr == null) return const SizedBox.shrink();

    return Card(
      key: const Key('qr-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Scan to pay', style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Open your banking app and scan this KHQR code.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(key: const Key('qr-image'), data: qr.payload, size: 220),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              formatMoney(qr.amount),
              key: const Key('qr-amount'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              '${qr.merchant} · ${qr.reference}',
              key: const Key('qr-reference'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            TextButton.icon(
              key: const Key('copy-qr'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: qr.payload));
                if (mounted) setState(() => _info = 'The text of the QR code was copied.');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy the code text'),
            ),
            const SizedBox(height: 4),
            const Text(
              'Practice payment: no money moves. Tap the button when you are done.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('check-payment'),
              onPressed: _busy ? null : _verify,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('I have paid'),
            ),
            TextButton(
              key: const Key('another-way'),
              onPressed: _busy ? null : _chooseAnotherWay,
              child: const Text('Choose another way to pay'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(ThemeData theme, Booking b) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoomPhoto(url: b.coverImage, height: 140),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${b.roomTypeName} · Room ${b.roomNumber}', style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                _Line(Icons.login, 'Check-in', formatShortDate(b.checkIn)),
                _Line(Icons.logout, 'Check-out', formatShortDate(b.checkOut)),
                _Line(Icons.nights_stay_outlined, 'Nights', '${b.nights}'),
                _Line(Icons.people_outline, 'Guests', '${b.guests}'),
                const Divider(height: 24),
                _Line(
                  Icons.attach_money,
                  '${formatMoney(b.pricePerNight)} × ${nightsText(b.nights)}',
                  formatMoney(b.totalPrice),
                  bold: !b.hasDiscount,
                ),
                if (b.hasDiscount) ...[
                  _Line(
                    Icons.local_offer_outlined,
                    'Online discount (${b.discountPercent}%)',
                    '-${formatMoney(b.discountAmount)}',
                    key: const Key('discount-line'),
                  ),
                  _Line(Icons.payments_outlined, 'To pay', formatMoney(b.toPay), bold: true, key: const Key('to-pay-line')),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------ the payment choices

  List<Widget> _choices(ThemeData theme) {
    final percent = ref.watch(publicSettingsProvider).value?.onlineDiscountPercent ?? 0;
    final price = onlinePrice(_booking.totalPrice, percent);
    final offer = percent > 0
        ? '${formatMoney(price.due)} instead of ${formatMoney(_booking.totalPrice)}'
        : 'Your room is kept while you pay.';

    return [
      Text('How do you want to pay?', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          key: const Key('pay-card'),
          enabled: !_busy,
          leading: const Icon(Icons.credit_card),
          title: Text(percent > 0 ? 'Pay by card and save $percent%' : 'Pay by card'),
          subtitle: Text(offer),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : () => setState(() {
                _step = _Step.card;
                _error = null;
              }),
        ),
      ),
      Card(
        child: ListTile(
          key: const Key('pay-qr'),
          enabled: !_busy,
          leading: _busy
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.qr_code_2),
          title: Text(percent > 0 ? 'Pay with a QR code and save $percent%' : 'Pay with a QR code'),
          subtitle: const Text('Scan with your banking app (KHQR).'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _startQr,
        ),
      ),
      Card(
        child: ListTile(
          key: const Key('pay-at-hotel'),
          enabled: !_busy,
          leading: const Icon(Icons.storefront_outlined),
          title: const Text('Pay at the hotel'),
          subtitle: const Text('Pay when you arrive. We keep your room. No discount.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _payAtHotel,
        ),
      ),
      const SizedBox(height: 16),
    ];
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool bold;
  const _Line(this.icon, this.label, this.value, {this.bold = false, super.key});

  @override
  Widget build(BuildContext context) {
    final style = bold ? Theme.of(context).textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
