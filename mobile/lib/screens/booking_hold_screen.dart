import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../booking/booking_repository.dart';
import '../core/api_error.dart';
import '../core/format.dart';
import '../core/public_settings_provider.dart';
import '../core/url_opener.dart';
import '../models/booking.dart';
import '../rooms/room_types_provider.dart';
import '../widgets/error_banner.dart';
import '../widgets/room_photo.dart';

/// Where the guest is while paying online.
enum _Step {
  /// Choosing: online or at the hotel.
  choose,

  /// Stripe's payment page is open in the browser. We wait for the guest to come back.
  awaitingBrowser,

  /// Demo mode: a fake pay button.
  demoReady,
}

/// Shown right after booking. The room is held while the guest chooses how to pay.
/// - Pay at the hotel: the room is kept with no countdown.
/// - Pay online: more time, a payment page, and the SERVER checks the payment.
class BookingHoldScreen extends ConsumerStatefulWidget {
  final Booking booking;
  const BookingHoldScreen({super.key, required this.booking});

  @override
  ConsumerState<BookingHoldScreen> createState() => _BookingHoldScreenState();
}

class _BookingHoldScreenState extends ConsumerState<BookingHoldScreen> with WidgetsBindingObserver {
  static const _firstHoldSeconds = 300; // the server holds a room for 5 minutes

  late Booking _booking = widget.booking;
  _Step _step = _Step.choose;
  String? _checkoutUrl;
  String? _hint; // for example the sandbox test card, sent by the server

  /// The guest paid too late, the room was gone, and the money went back.
  bool _dead = false;

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
  bool get _expired => !_kept && !_paid && !_dead && _remaining == 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  /// The guest comes back from the browser: check the payment without asking them to tap.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _step == _Step.awaitingBrowser && !_busy && !_paid && !_dead) {
      _verify();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {});
      if (_expired || _paid || _kept || _dead) {
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
          _checkoutUrl = null;
        });
      });

  Future<void> _payOnline() => _run(() async {
        final result = await ref.read(bookingRepositoryProvider).payOnline(_booking.id);
        if (!mounted) return;

        setState(() => _booking = result.booking);
        final seconds = result.booking.holdSecondsLeft;
        if (seconds != null) _resetCountdown(seconds);

        if (result.isDemo) {
          setState(() => _step = _Step.demoReady);
          return;
        }

        _checkoutUrl = result.checkoutUrl;
        _hint = result.hint;
        setState(() => _step = _Step.awaitingBrowser);
        await _openPage();
      });

  Future<void> _openPage() async {
    final url = _checkoutUrl;
    if (url == null) return;

    bool opened;
    try {
      opened = await ref.read(urlOpenerProvider)(Uri.parse(url));
    } catch (_) {
      opened = false;
    }
    if (!opened && mounted) {
      setState(() => _error = 'Could not open the browser on this phone.');
    }
  }

  /// "I paid." The server asks Stripe. Only then is the booking confirmed.
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
        case 'payment_not_completed':
          setState(() => _info = 'Not paid yet. Finish the payment in the browser, then tap the button again.');
        case 'session_expired':
          setState(() {
            _error = e.message;
            _step = _Step.choose;
          });
        case 'room_gone_refunded' || 'booking_cancelled_refunded':
          // The money went back and the booking is cancelled. Nothing more to do here.
          _timer?.cancel();
          ref.invalidate(roomTypesProvider);
          setState(() {
            _error = e.message;
            _dead = true;
          });
        default:
          setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demoPay() => _run(() async {
        final confirmed = await ref.read(bookingRepositoryProvider).demoPay(_booking.id);
        if (!mounted) return;
        _timer?.cancel();
        ref.invalidate(roomTypesProvider);
        setState(() => _booking = confirmed);
      });

  void _chooseAnotherWay() => setState(() {
        _step = _Step.choose;
        _error = null;
        _info = null;
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
            : _dead
                ? 'Payment sent back'
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
            else if (!_dead)
              _countdownCard(theme, b),
            const SizedBox(height: 16),
            if (!_dead) _summaryCard(theme, b),
            if (!_dead) const SizedBox(height: 16),
            ..._actions(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(ThemeData theme) {
    final backButton = FilledButton(onPressed: _backToRooms, child: const Text('Back to rooms'));

    if (_paid || _dead) return [backButton];

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

    if (_expired) {
      return [
        // The guest may have paid just before the time ran out. The server decides what happens.
        if (_step == _Step.awaitingBrowser) ...[
          const Text(
            'If you already paid, tap the button. If the room is gone, your money is sent back.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('check-payment'),
            onPressed: _busy ? null : _verify,
            child: const Text('Check my payment'),
          ),
          const SizedBox(height: 8),
        ],
        backButton,
      ];
    }

    return [
      ...switch (_step) {
        _Step.choose => _choices(theme),
        _Step.awaitingBrowser => [_awaitingCard(theme), const SizedBox(height: 16)],
        _Step.demoReady => [_demoCard(theme), const SizedBox(height: 16)],
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
              'Paid ${formatMoney(b.toPay)} online.'
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

  Widget _awaitingCard(ThemeData theme) {
    return Card(
      key: const Key('awaiting-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Finish paying in your browser', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'We opened a secure payment page. Pay ${formatMoney(_booking.toPay)}, then come back to this app.',
            ),
            if (_hint != null) ...[
              const SizedBox(height: 8),
              Text(_hint!, key: const Key('payment-hint'), style: const TextStyle(fontSize: 13)),
            ],
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
                  : const Text('I have paid, check now'),
            ),
            TextButton(
              key: const Key('open-page-again'),
              onPressed: _busy ? null : _openPage,
              child: const Text('Open the payment page again'),
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

  Widget _demoCard(ThemeData theme) {
    return Card(
      key: const Key('demo-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Demo payment', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Demo mode is on, so no real money moves. This is for the presentation.'),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('demo-pay'),
              onPressed: _busy ? null : _demoPay,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Pay ${formatMoney(_booking.toPay)} (demo)'),
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

    return [
      Text('How do you want to pay?', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      Card(
        child: ListTile(
          key: const Key('pay-online'),
          enabled: !_busy,
          leading: const Icon(Icons.credit_card),
          title: Text(percent > 0 ? 'Pay online and save $percent%' : 'Pay online'),
          subtitle: Text(percent > 0
              ? '${formatMoney(price.due)} instead of ${formatMoney(_booking.totalPrice)}'
              : 'Pay now with a card. Your room is kept while you pay.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _busy ? null : _payOnline,
        ),
      ),
      Card(
        child: ListTile(
          key: const Key('pay-at-hotel'),
          enabled: !_busy,
          leading: _busy
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.storefront_outlined),
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
