import 'package:angkor_stay/booking/booking_repository.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/core/format.dart';
import 'package:angkor_stay/core/public_settings_provider.dart';
import 'package:angkor_stay/core/url_opener.dart';
import 'package:angkor_stay/models/booking.dart';
import 'package:angkor_stay/models/public_settings.dart';
import 'package:angkor_stay/screens/booking_hold_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Booking _booking({
  String status = 'pending',
  String? choice,
  int? hold = 300,
  int percent = 0,
  double discount = 0,
  double? due,
  bool paid = false,
  String? method,
}) =>
    Booking(
      id: 7,
      code: 'AS-0007',
      status: status,
      roomNumber: '101',
      roomTypeName: 'Single',
      coverImage: null,
      checkIn: DateTime.utc(2026, 11, 10),
      checkOut: DateTime.utc(2026, 11, 12),
      nights: 2,
      guests: 1,
      pricePerNight: 15,
      totalPrice: 30,
      discountPercent: percent,
      discountAmount: discount,
      amountDue: due,
      paymentChoice: choice,
      paid: paid,
      paymentMethod: method,
      holdSecondsLeft: hold,
    );

Booking _holding() => _booking();

/// The booking after "pay online": 15% off, more time.
Booking _onlineStarted({int? hold = 900}) =>
    _booking(choice: 'online', hold: hold, percent: 15, discount: 4.5, due: 25.5);

Booking _paid() => _booking(
      status: 'confirmed',
      choice: 'online',
      hold: null,
      percent: 15,
      discount: 4.5,
      due: 25.5,
      paid: true,
      method: 'online',
    );

Booking _kept() => _booking(choice: 'hotel', hold: null);

/// A server that answers from memory and remembers what it was asked.
class _FakePay extends BookingRepository {
  _FakePay() : super(Dio());

  PayOnlineResult? onlineResult;
  ApiError? onlineError;
  ApiError? demoError;
  ApiError? hotelError;

  /// What "check my payment" answers, one by one. When empty: "not paid yet".
  final verifyQueue = <Object>[];
  Booking demoResult = _paid();

  int onlineCalls = 0;
  int verifyCalls = 0;
  int demoCalls = 0;
  int hotelCalls = 0;
  final released = <int>[];

  @override
  Future<PayOnlineResult> payOnline(int bookingId) async {
    onlineCalls++;
    if (onlineError != null) throw onlineError!;
    return onlineResult ??
        PayOnlineResult(
          booking: _onlineStarted(),
          mode: 'online',
          checkoutUrl: 'https://checkout.stripe.test/pay/cs_test_1',
          hint: 'Sandbox test card: 5156 8399 3770 6777, expiry 01/30, CVV 993.',
        );
  }

  @override
  Future<Booking> verifyPayment(int bookingId) async {
    verifyCalls++;
    if (verifyQueue.isEmpty) {
      throw const ApiError('The payment is not finished yet.', statusCode: 409, code: 'payment_not_completed');
    }
    final next = verifyQueue.removeAt(0);
    if (next is ApiError) throw next;
    return next as Booking;
  }

  @override
  Future<Booking> demoPay(int bookingId) async {
    demoCalls++;
    if (demoError != null) throw demoError!;
    return demoResult;
  }

  @override
  Future<Booking> payAtHotel(int bookingId) async {
    hotelCalls++;
    if (hotelError != null) throw hotelError!;
    return _kept();
  }

  @override
  Future<void> release(int bookingId) async => released.add(bookingId);
}

class _Rig {
  final _FakePay repo = _FakePay();
  final opened = <Uri>[];
  bool browserWorks = true;
  AsyncValue<PublicSettings> settings = const AsyncData(
    PublicSettings(onlineDiscountPercent: 15, checkInTime: '14:00', checkOutTime: '12:00'),
  );
}

Future<_Rig> _open(WidgetTester tester, Booking booking, {_Rig? rig, bool settingsFail = false, int percent = 15}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final r = rig ?? _Rig();

  await tester.pumpWidget(ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      bookingRepositoryProvider.overrideWithValue(r.repo),
      urlOpenerProvider.overrideWithValue((uri) async {
        r.opened.add(uri);
        return r.browserWorks;
      }),
      publicSettingsProvider.overrideWith((ref) async {
        if (settingsFail) throw const ApiError('no settings');
        return PublicSettings(onlineDiscountPercent: percent, checkInTime: '14:00', checkOutTime: '12:00');
      }),
    ],
    child: const MaterialApp(home: Scaffold(body: Text('ROOT'))),
  ));

  tester.state<NavigatorState>(find.byType(Navigator)).push(
        MaterialPageRoute(builder: (_) => BookingHoldScreen(booking: booking)),
      );
  await tester.pumpAndSettle();
  return r;
}

/// Taps "Pay online" and lets everything settle.
Future<void> _tapPayOnline(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pay-online')));
  await tester.pumpAndSettle();
}

/// The phone goes to the browser and comes back.
Future<void> _leaveAndReturn(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  group('the payment choices', () {
    testWidgets('online shows the saving, worked out from the discount setting', (tester) async {
      await _open(tester, _holding());

      expect(find.text('Pay online and save 15%'), findsOneWidget);
      expect(find.text('\$25.50 instead of \$30'), findsOneWidget);
      expect(find.text('Pay at the hotel'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // stop the timer
    });

    testWidgets('with no discount it just says Pay online', (tester) async {
      await _open(tester, _holding(), percent: 0);

      expect(find.text('Pay online'), findsOneWidget);
      expect(find.textContaining('save'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('if the settings cannot be loaded, online is still offered without a number', (tester) async {
      await _open(tester, _holding(), settingsFail: true);

      expect(find.text('Pay online'), findsOneWidget);
      expect(find.byKey(const Key('pay-online')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('paying online with Stripe', () {
    testWidgets('opens the payment page in the browser and waits, with more time and the discount shown', (tester) async {
      final rig = await _open(tester, _holding());
      expect(find.text('5:00'), findsOneWidget);

      await _tapPayOnline(tester);

      expect(rig.repo.onlineCalls, 1);
      expect(rig.opened, [Uri.parse('https://checkout.stripe.test/pay/cs_test_1')]);

      expect(find.byKey(const Key('awaiting-card')), findsOneWidget);
      expect(find.text('Finish paying in your browser'), findsOneWidget);
      expect(find.byKey(const Key('payment-hint')), findsOneWidget);
      expect(find.textContaining('5156 8399 3770 6777'), findsOneWidget); // the test card the server sent
      expect(find.textContaining('4242'), findsNothing); // not a hard-coded Stripe card any more
      expect(find.textContaining('Pay \$25.50'), findsOneWidget);

      // The choices are gone, the countdown starts again from the server's 15 minutes.
      expect(find.byKey(const Key('pay-online')), findsNothing);
      expect(find.byKey(const Key('pay-at-hotel')), findsNothing);
      expect(find.text('15:00'), findsOneWidget);

      // The price shows the discount.
      expect(find.byKey(const Key('discount-line')), findsOneWidget);
      expect(find.text('Online discount (15%)'), findsOneWidget);
      expect(find.text('-\$4.50'), findsOneWidget);
      expect(find.byKey(const Key('to-pay-line')), findsOneWidget);
      expect(find.text('\$25.50'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with no hint from the server, no hint is shown', (tester) async {
      final rig = _Rig();
      rig.repo.onlineResult = PayOnlineResult(
        booking: _onlineStarted(),
        mode: 'online',
        checkoutUrl: 'https://checkout.payway.test/pay/AS7-ABCDEFGH',
      );
      await _open(tester, _holding(), rig: rig);

      await _tapPayOnline(tester);

      expect(find.byKey(const Key('awaiting-card')), findsOneWidget);
      expect(find.byKey(const Key('payment-hint')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"I have paid" asks the server and then shows the paid booking', (tester) async {
      final rig = await _open(tester, _holding());
      await _tapPayOnline(tester);
      rig.repo.verifyQueue.add(_paid());

      await tester.tap(find.byKey(const Key('check-payment')));
      await tester.pumpAndSettle();

      expect(rig.repo.verifyCalls, 1);
      expect(find.byKey(const Key('paid-card')), findsOneWidget);
      expect(find.text('Room 101 is yours'), findsOneWidget);
      expect(find.text('AS-0007'), findsOneWidget);
      expect(find.byKey(const Key('paid-text')), findsOneWidget);
      expect(find.text('Paid \$25.50 online. You saved \$4.50 (15% off).'), findsOneWidget);
      expect(find.text('Booked and paid'), findsOneWidget);

      // No countdown, no payment buttons, only a way back.
      expect(find.byKey(const Key('countdown')), findsNothing);
      expect(find.byKey(const Key('awaiting-card')), findsNothing);
      expect(find.text('Release this room'), findsNothing);
      expect(find.text('Back to rooms'), findsOneWidget);

      // Twenty minutes later it is still booked.
      await tester.pump(const Duration(minutes: 20));
      expect(find.text('Hold ran out'), findsNothing);
      expect(find.byKey(const Key('paid-card')), findsOneWidget);
    });

    testWidgets('while the guest has not paid, it says so and keeps waiting', (tester) async {
      final rig = await _open(tester, _holding());
      await _tapPayOnline(tester);

      await tester.tap(find.byKey(const Key('check-payment')));
      await tester.pumpAndSettle();

      expect(rig.repo.verifyCalls, 1);
      expect(find.byKey(const Key('info')), findsOneWidget);
      expect(find.textContaining('Not paid yet'), findsOneWidget);
      expect(find.byKey(const Key('awaiting-card')), findsOneWidget);
      expect(find.byKey(const Key('paid-card')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('coming back to the app from the browser checks the payment by itself', (tester) async {
      final rig = await _open(tester, _holding());
      await _tapPayOnline(tester);
      rig.repo.verifyQueue.add(_paid());

      await _leaveAndReturn(tester);

      expect(rig.repo.verifyCalls, 1);
      expect(find.byKey(const Key('paid-card')), findsOneWidget);
    });

    testWidgets('coming back does nothing while the guest is still choosing', (tester) async {
      final rig = await _open(tester, _holding());

      await _leaveAndReturn(tester);

      expect(rig.repo.verifyCalls, 0);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the payment page can be opened again', (tester) async {
      final rig = await _open(tester, _holding());
      await _tapPayOnline(tester);

      await tester.tap(find.byKey(const Key('open-page-again')));
      await tester.pumpAndSettle();

      expect(rig.opened, hasLength(2));
      expect(rig.opened.first, rig.opened.last);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('if the phone cannot open a browser, the guest is told', (tester) async {
      final rig = _Rig()..browserWorks = false;
      await _open(tester, _holding(), rig: rig);

      await _tapPayOnline(tester);

      expect(find.text('Could not open the browser on this phone.'), findsOneWidget);
      expect(find.byKey(const Key('awaiting-card')), findsOneWidget); // they can try again

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"choose another way" goes back to the choices and pay at the hotel works', (tester) async {
      final rig = await _open(tester, _holding());
      await _tapPayOnline(tester);

      await tester.tap(find.byKey(const Key('another-way')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('awaiting-card')), findsNothing);
      expect(find.byKey(const Key('pay-at-hotel')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pay-at-hotel')));
      await tester.pumpAndSettle();

      expect(rig.repo.hotelCalls, 1);
      expect(find.byKey(const Key('kept-card')), findsOneWidget);
    });

    testWidgets('a payment page that expired sends the guest back to the choices', (tester) async {
      final rig = await _open(tester, _holding());
      await _tapPayOnline(tester);
      rig.repo.verifyQueue.add(const ApiError('The payment page expired. Please start again.', statusCode: 409, code: 'session_expired'));

      await tester.tap(find.byKey(const Key('check-payment')));
      await tester.pumpAndSettle();

      expect(find.text('The payment page expired. Please start again.'), findsOneWidget);
      expect(find.byKey(const Key('pay-online')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a server problem while checking shows its message', (tester) async {
      final rig = await _open(tester, _holding());
      await _tapPayOnline(tester);
      rig.repo.verifyQueue.add(const ApiError('We could not check the payment yet. Please try again.', statusCode: 502, code: 'provider_error'));

      await tester.tap(find.byKey(const Key('check-payment')));
      await tester.pumpAndSettle();

      expect(find.textContaining('could not check the payment'), findsOneWidget);
      expect(find.byKey(const Key('awaiting-card')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('when starting is refused', () {
    testWidgets('online payment not set up: the message shows and the guest can choose the hotel', (tester) async {
      final rig = _Rig();
      rig.repo.onlineError = const ApiError(
        'Online payment is not set up yet. Please choose to pay at the hotel.',
        statusCode: 503,
        code: 'online_payment_unavailable',
      );
      await _open(tester, _holding(), rig: rig);

      await _tapPayOnline(tester);

      expect(find.textContaining('not set up yet'), findsOneWidget);
      expect(find.byKey(const Key('awaiting-card')), findsNothing);
      expect(find.byKey(const Key('pay-at-hotel')), findsOneWidget);
      expect(rig.opened, isEmpty);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the five minutes ran out: the message shows', (tester) async {
      final rig = _Rig();
      rig.repo.onlineError = const ApiError(
        'Your 5 minutes ran out and the room may be taken. Please book again.',
        statusCode: 409,
        code: 'hold_expired',
      );
      await _open(tester, _holding(), rig: rig);

      await _tapPayOnline(tester);

      expect(find.textContaining('5 minutes ran out'), findsOneWidget);
      expect(rig.opened, isEmpty);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('demo mode', () {
    _Rig demoRig() {
      final rig = _Rig();
      rig.repo.onlineResult = PayOnlineResult(booking: _onlineStarted(), mode: 'demo', checkoutUrl: null);
      return rig;
    }

    testWidgets('shows a demo button instead of opening a browser', (tester) async {
      final rig = await _open(tester, _holding(), rig: demoRig());

      await _tapPayOnline(tester);

      expect(find.byKey(const Key('demo-card')), findsOneWidget);
      expect(find.text('Demo payment'), findsOneWidget);
      expect(find.text('Pay \$25.50 (demo)'), findsOneWidget);
      expect(rig.opened, isEmpty);
      expect(find.text('15:00'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pressing the demo button confirms and shows the paid booking', (tester) async {
      final rig = await _open(tester, _holding(), rig: demoRig());
      await _tapPayOnline(tester);

      await tester.tap(find.byKey(const Key('demo-pay')));
      await tester.pumpAndSettle();

      expect(rig.repo.demoCalls, 1);
      expect(find.byKey(const Key('paid-card')), findsOneWidget);
      expect(find.text('Paid \$25.50 online. You saved \$4.50 (15% off).'), findsOneWidget);
    });

    testWidgets('if the admin switched demo mode off meanwhile, the message shows', (tester) async {
      final rig = demoRig();
      rig.repo.demoError = const ApiError('Demo payment is switched off.', statusCode: 403, code: 'demo_mode_off');
      await _open(tester, _holding(), rig: rig);
      await _tapPayOnline(tester);

      await tester.tap(find.byKey(const Key('demo-pay')));
      await tester.pumpAndSettle();

      expect(find.text('Demo payment is switched off.'), findsOneWidget);
      expect(find.byKey(const Key('paid-card')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('paying too late and money coming back', () {
    testWidgets('when the time runs out while waiting, the guest can still check their payment', (tester) async {
      final rig = _Rig();
      rig.repo.onlineResult = PayOnlineResult(
        booking: _onlineStarted(hold: 3),
        mode: 'stripe',
        checkoutUrl: 'https://checkout.stripe.test/pay/cs_test_1',
      );
      await _open(tester, _holding(), rig: rig);
      await _tapPayOnline(tester);

      await tester.pump(const Duration(seconds: 5));

      expect(find.text('Hold ran out'), findsOneWidget);
      expect(find.byKey(const Key('check-payment')), findsOneWidget);
      expect(find.textContaining('If you already paid'), findsOneWidget);

      rig.repo.verifyQueue.add(_paid()); // the guest did pay, and the room was still free
      await tester.tap(find.byKey(const Key('check-payment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('paid-card')), findsOneWidget);
    });

    testWidgets('a hold that ran out before any payment offers no payment check', (tester) async {
      await _open(tester, _booking(hold: 2));

      await tester.pump(const Duration(seconds: 4));

      expect(find.text('Hold ran out'), findsOneWidget);
      expect(find.byKey(const Key('check-payment')), findsNothing);
      expect(find.text('Back to rooms'), findsOneWidget);
    });

    testWidgets('if the room was taken, the money went back and the guest is told clearly', (tester) async {
      final rig = await _open(tester, _holding());
      await _tapPayOnline(tester);
      rig.repo.verifyQueue.add(const ApiError(
        'The room was taken before your payment arrived. Your money was sent back.',
        statusCode: 409,
        code: 'room_gone_refunded',
      ));

      await tester.tap(find.byKey(const Key('check-payment')));
      await tester.pumpAndSettle();

      expect(find.text('The room was taken before your payment arrived. Your money was sent back.'), findsOneWidget);
      expect(find.text('Payment sent back'), findsOneWidget);
      expect(find.text('Back to rooms'), findsOneWidget);
      expect(find.byKey(const Key('check-payment')), findsNothing);
      expect(find.byKey(const Key('pay-online')), findsNothing);
      expect(find.byKey(const Key('paid-card')), findsNothing);

      await tester.pump(const Duration(minutes: 20));
      expect(find.text('Hold ran out'), findsNothing);
    });

    testWidgets('a payment for a booking cancelled meanwhile is also shown as sent back', (tester) async {
      final rig = await _open(tester, _holding());
      await _tapPayOnline(tester);
      rig.repo.verifyQueue.add(const ApiError(
        'This booking was cancelled before the payment arrived. Your money was sent back.',
        statusCode: 409,
        code: 'booking_cancelled_refunded',
      ));

      await tester.tap(find.byKey(const Key('check-payment')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Your money was sent back'), findsOneWidget);
      expect(find.text('Payment sent back'), findsOneWidget);
    });
  });

  group('screens that open already paid or kept', () {
    testWidgets('a paid booking opens straight on the paid page', (tester) async {
      await _open(tester, _paid());

      expect(find.byKey(const Key('paid-card')), findsOneWidget);
      expect(find.byKey(const Key('countdown')), findsNothing);
      expect(find.text('Release this room'), findsNothing);
    });

    testWidgets('releasing a room while paying online tells the server', (tester) async {
      final rig = await _open(tester, _holding());
      await _tapPayOnline(tester);

      await tester.tap(find.text('Release this room'));
      await tester.pumpAndSettle();

      expect(rig.repo.released, [7]);
      expect(find.byType(BookingHoldScreen), findsNothing);
      expect(find.text('The room was released.'), findsOneWidget);
    });
  });

  group('models and helpers', () {
    test('onlinePrice works in whole cents', () {
      expect(onlinePrice(30, 15), (discount: 4.5, due: 25.5));
      expect(onlinePrice(15, 15), (discount: 2.25, due: 12.75));
      expect(onlinePrice(15, 10), (discount: 1.5, due: 13.5));
      expect(onlinePrice(50, 0), (discount: 0.0, due: 50.0));
      expect(onlinePrice(100, 50), (discount: 50.0, due: 50.0));
      expect(onlinePrice(15.5, 15), (discount: 2.33, due: 13.17)); // the same cents as the server
    });

    test('Booking reads the discount and the payment', () {
      final b = Booking.fromJson({
        'id': 7,
        'code': 'AS-0007',
        'status': 'confirmed',
        'room_number': '101',
        'room_type': {'id': 1, 'name': 'Single', 'cover_image': null},
        'check_in_date': '2026-11-10',
        'check_out_date': '2026-11-12',
        'nights': 2,
        'guests': 1,
        'price_per_night': 15,
        'total_price': 30,
        'discount_percent': 15,
        'discount_amount': 4.5,
        'amount_due': 25.5,
        'payment_choice': 'online',
        'paid': true,
        'payment_method': 'online',
        'hold_seconds_left': null,
      });

      expect(b.discountPercent, 15);
      expect(b.discountAmount, 4.5);
      expect(b.toPay, 25.5);
      expect(b.hasDiscount, isTrue);
      expect(b.paymentMethod, 'online');
      expect(b.isPaidAndConfirmed, isTrue);
      expect(b.isKeptForHotel, isFalse);
    });

    test('an old answer without discount fields still reads, and the price to pay is the total', () {
      final b = Booking.fromJson({
        'id': 1,
        'status': 'pending',
        'room_number': '101',
        'room_type': null,
        'check_in_date': '2026-11-10',
        'check_out_date': '2026-11-12',
        'nights': 2,
        'guests': 1,
        'price_per_night': 15,
        'total_price': 30,
        'hold_seconds_left': 200,
      });

      expect(b.discountPercent, 0);
      expect(b.hasDiscount, isFalse);
      expect(b.toPay, 30);
      expect(b.isPaidAndConfirmed, isFalse);
    });

    test('a cancelled or pending booking is never "paid and confirmed"', () {
      expect(_booking(status: 'cancelled', paid: true).isPaidAndConfirmed, isFalse);
      expect(_booking(status: 'pending', paid: true).isPaidAndConfirmed, isFalse);
      expect(_booking(status: 'confirmed', paid: false).isPaidAndConfirmed, isFalse);
      expect(_booking(status: 'checked_in', paid: true).isPaidAndConfirmed, isTrue);
    });

    test('PayOnlineResult knows demo mode', () {
      expect(PayOnlineResult(booking: _holding(), mode: 'demo', checkoutUrl: null).isDemo, isTrue);
      expect(PayOnlineResult(booking: _holding(), mode: 'stripe', checkoutUrl: 'https://x').isDemo, isFalse);
    });

    test('PublicSettings reads the API json', () {
      final s = PublicSettings.fromJson({
        'online_discount_percent': 20,
        'check_in_time': '13:00',
        'check_out_time': '11:00',
      });

      expect(s.onlineDiscountPercent, 20);
      expect(s.checkInTime, '13:00');
      expect(s.checkOutTime, '11:00');
    });
  });
}
