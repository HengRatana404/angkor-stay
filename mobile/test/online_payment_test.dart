import 'package:angkor_stay/booking/booking_repository.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/core/format.dart';
import 'package:angkor_stay/core/public_settings_provider.dart';
import 'package:angkor_stay/models/booking.dart';
import 'package:angkor_stay/models/public_settings.dart';
import 'package:angkor_stay/screens/booking_hold_screen.dart';
import 'package:angkor_stay/widgets/card_formatters.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

Booking _booking({
  String status = 'pending',
  String? choice,
  int? hold = 300,
  int percent = 0,
  double discount = 0,
  double? due,
  bool paid = false,
  String? method,
  String? detail,
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
      paymentDetail: detail,
      holdSecondsLeft: hold,
    );

Booking _holding() => _booking();

/// The booking after the guest started a QR payment: 15% off, more time.
Booking _qrStarted({int? hold = 900}) => _booking(choice: 'online', hold: hold, percent: 15, discount: 4.5, due: 25.5);

Booking _paidByCard() => _booking(
      status: 'confirmed',
      choice: 'online',
      hold: null,
      percent: 15,
      discount: 4.5,
      due: 25.5,
      paid: true,
      method: 'online',
      detail: 'Visa ending 4242',
    );

Booking _paidByQr() => _booking(
      status: 'confirmed',
      choice: 'online',
      hold: null,
      percent: 15,
      discount: 4.5,
      due: 25.5,
      paid: true,
      method: 'online',
      detail: 'KHQR',
    );

Booking _kept() => _booking(choice: 'hotel', hold: null);

const _payload = '00020101021229190015angkorstay@demo52047011530384054052.5058025KH5911Angkor Stay6010Phnom Penh6304ABCD';

/// A server that answers from memory and remembers what it was asked.
class _FakePay extends BookingRepository {
  _FakePay() : super(Dio());

  // card
  Object cardResult = _paidByCard(); // a Booking, or an ApiError to throw
  final cardCalls = <Map<String, String>>[];

  // qr
  QrPayment? qrResult;
  ApiError? qrError;
  int qrCalls = 0;

  /// What "I have paid" answers, one by one. When empty: a paid booking.
  final verifyQueue = <Object>[];
  int verifyCalls = 0;

  ApiError? hotelError;
  int hotelCalls = 0;
  final released = <int>[];

  @override
  Future<Booking> payByCard(
    int bookingId, {
    required String number,
    required String holder,
    required String expiry,
    required String cvv,
  }) async {
    cardCalls.add({'number': number, 'holder': holder, 'expiry': expiry, 'cvv': cvv});
    final r = cardResult;
    if (r is ApiError) throw r;
    return r as Booking;
  }

  @override
  Future<QrPayment> startQr(int bookingId) async {
    qrCalls++;
    if (qrError != null) throw qrError!;
    return qrResult ??
        QrPayment(
          booking: _qrStarted(),
          reference: 'AS7-K3F9QZ7M',
          payload: _payload,
          amount: 25.5,
          merchant: 'Angkor Stay',
          secondsLeft: 900,
        );
  }

  @override
  Future<Booking> verifyPayment(int bookingId) async {
    verifyCalls++;
    if (verifyQueue.isEmpty) return _paidByQr();
    final next = verifyQueue.removeAt(0);
    if (next is ApiError) throw next;
    return next as Booking;
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

Future<_FakePay> _open(WidgetTester tester, Booking booking, {bool settingsFail = false, int percent = 15}) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repo = _FakePay();

  await tester.pumpWidget(ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      bookingRepositoryProvider.overrideWithValue(repo),
      publicSettingsProvider.overrideWith((ref) async {
        if (settingsFail) throw const ApiError('no settings');
        return PublicSettings(onlineDiscountPercent: percent, checkInTime: '14:00', checkOutTime: '12:00');
      }),
    ],
    child: const MaterialApp(home: Scaffold(body: Text('ROOT'))),
  ));

  tester.state<NavigatorState>(find.byType(Navigator)).push(
        MaterialPageRoute<void>(builder: (_) => BookingHoldScreen(booking: booking)),
      );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _tapPayByCard(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pay-card')));
  await tester.pumpAndSettle();
}

Future<void> _tapPayByQr(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pay-qr')));
  await tester.pumpAndSettle();
}

/// Types into the card form. The formatters run, like on a real phone.
Future<void> _fillCard(
  WidgetTester tester, {
  String number = '4242424242424242',
  String holder = 'Sokha Demo',
  String expiry = '1126',
  String cvv = '987',
}) async {
  await tester.enterText(find.byKey(const Key('card-number')), number);
  await tester.enterText(find.byKey(const Key('card-holder')), holder);
  await tester.enterText(find.byKey(const Key('card-expiry')), expiry);
  await tester.enterText(find.byKey(const Key('card-cvv')), cvv);
  await tester.pump();
}

Future<void> _tapPay(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('card-pay')));
  await tester.tap(find.byKey(const Key('card-pay')));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  group('the payment choices', () {
    testWidgets('card and QR show the saving, worked out from the discount setting', (tester) async {
      await _open(tester, _holding());

      expect(find.text('Pay by card and save 15%'), findsOneWidget);
      expect(find.text('\$25.50 instead of \$30'), findsOneWidget);
      expect(find.text('Pay with a QR code and save 15%'), findsOneWidget);
      expect(find.text('Pay at the hotel'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // stop the timer
    });

    testWidgets('with no discount it just says Pay by card', (tester) async {
      await _open(tester, _holding(), percent: 0);

      expect(find.text('Pay by card'), findsOneWidget);
      expect(find.text('Pay with a QR code'), findsOneWidget);
      expect(find.textContaining('save'), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('if the settings cannot be loaded, paying online is still offered without a number', (tester) async {
      await _open(tester, _holding(), settingsFail: true);

      expect(find.text('Pay by card'), findsOneWidget);
      expect(find.text('Pay with a QR code'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('paying by card', () {
    testWidgets('opens a card form that shows the discounted price on the button', (tester) async {
      await _open(tester, _holding());
      await _tapPayByCard(tester);

      expect(find.byKey(const Key('card-form')), findsOneWidget);
      expect(find.text('Pay \$25.50'), findsOneWidget);
      expect(find.textContaining('Any card number works'), findsOneWidget);
      expect(find.byKey(const Key('pay-card')), findsNothing); // the choices are gone

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('sends exactly what was typed and then shows the paid booking', (tester) async {
      final repo = await _open(tester, _holding());
      await _tapPayByCard(tester);
      await _fillCard(tester, holder: '  Sokha Demo  ');
      await _tapPay(tester);

      expect(repo.cardCalls, [
        {'number': '4242 4242 4242 4242', 'holder': 'Sokha Demo', 'expiry': '11/26', 'cvv': '987'},
      ]);
      expect(find.byKey(const Key('paid-card')), findsOneWidget);
      expect(find.byKey(const Key('booking-code')), findsOneWidget);
      expect(find.text('AS-0007'), findsOneWidget);
      expect(find.byKey(const Key('countdown')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('paid-text'))).data,
        'Paid \$25.50 online with Visa ending 4242. You saved \$4.50 (15% off).',
      );
    });

    testWidgets('an expired card shows the server message under the date field and stays on the form', (tester) async {
      final repo = await _open(tester, _holding());
      repo.cardResult = const ApiError(
        'This card has expired.',
        statusCode: 422,
        fieldErrors: {'expiry': 'This card has expired.'},
      );
      await _tapPayByCard(tester);
      await _fillCard(tester, expiry: '1026');
      await _tapPay(tester);

      expect(find.text('This card has expired.'), findsOneWidget);
      expect(find.byKey(const Key('card-form')), findsOneWidget);
      expect(find.byKey(const Key('paid-card')), findsNothing);
      expect(_fieldText(tester, 'card-number'), '4242 4242 4242 4242'); // nothing was cleared

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('every wrong field is marked at once', (tester) async {
      final repo = await _open(tester, _holding());
      repo.cardResult = const ApiError('Enter the card number.', statusCode: 422, fieldErrors: {
        'number': 'The card number must have 12 to 19 digits.',
        'holder': 'Enter the name on the card.',
        'expiry': 'Write the expiry date as MM/YY, for example 11/26.',
        'cvv': 'The security code has 3 or 4 digits.',
      });
      await _tapPayByCard(tester);
      await _tapPay(tester);

      expect(find.text('The card number must have 12 to 19 digits.'), findsOneWidget);
      expect(find.text('Enter the name on the card.'), findsOneWidget);
      expect(find.text('Write the expiry date as MM/YY, for example 11/26.'), findsOneWidget);
      expect(find.text('The security code has 3 or 4 digits.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a problem that is not about a field (the five minutes ran out) shows in the banner', (tester) async {
      final repo = await _open(tester, _holding());
      repo.cardResult = const ApiError('Your 5 minutes ran out and the room may be taken. Please book again.',
          statusCode: 409, code: 'hold_expired');
      await _tapPayByCard(tester);
      await _fillCard(tester);
      await _tapPay(tester);

      expect(find.text('Your 5 minutes ran out and the room may be taken. Please book again.'), findsOneWidget);
      expect(find.byKey(const Key('paid-card')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"choose another way" goes back to the choices, and the hotel works from there', (tester) async {
      final repo = await _open(tester, _holding());
      await _tapPayByCard(tester);

      await tester.ensureVisible(find.byKey(const Key('another-way')));
      await tester.tap(find.byKey(const Key('another-way')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pay-card')), findsOneWidget);
      expect(find.byKey(const Key('card-form')), findsNothing);

      await tester.tap(find.byKey(const Key('pay-at-hotel')));
      await tester.pumpAndSettle();
      expect(repo.hotelCalls, 1);
      expect(find.byKey(const Key('kept-card')), findsOneWidget);
    });

    testWidgets('the CVV is hidden while typing', (tester) async {
      await _open(tester, _holding());
      await _tapPayByCard(tester);

      expect(tester.widget<TextField>(find.byKey(const Key('card-cvv'))).obscureText, isTrue);
      expect(tester.widget<TextField>(find.byKey(const Key('card-number'))).obscureText, isFalse);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('typing groups the number in fours and writes the date with a slash by itself', (tester) async {
      await _open(tester, _holding());
      await _tapPayByCard(tester);
      await _fillCard(tester, number: '5500000000000004', expiry: '1126', cvv: '12a34567');

      expect(_fieldText(tester, 'card-number'), '5500 0000 0000 0004');
      expect(_fieldText(tester, 'card-expiry'), '11/26');
      expect(_fieldText(tester, 'card-cvv'), '1234'); // digits only, at most 4

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('paying with a QR code', () {
    testWidgets('asks the server, then shows a QR code of the server text with the price and reference', (tester) async {
      final repo = await _open(tester, _holding());
      await _tapPayByQr(tester);

      expect(repo.qrCalls, 1);
      expect(find.byKey(const Key('qr-card')), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('qr-amount'))).data, '\$25.50');
      expect(find.text('Angkor Stay · AS7-K3F9QZ7M'), findsOneWidget);
      expect(find.textContaining('KHQR'), findsWidgets);
      expect(find.byKey(const Key('discount-line')), findsOneWidget); // the booking now has the discount

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the QR text can be copied, so it can be tried in any QR reader', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await _open(tester, _holding());
      await _tapPayByQr(tester);

      await tester.ensureVisible(find.byKey(const Key('copy-qr')));
      await tester.tap(find.byKey(const Key('copy-qr')));
      await tester.pumpAndSettle();

      expect(copied, [_payload]);
      expect(find.text('The text of the QR code was copied.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the payment gets more time: the countdown restarts from what the server says', (tester) async {
      await _open(tester, _booking(hold: 60));
      expect(find.text('1:00'), findsOneWidget);

      await _tapPayByQr(tester);

      expect(find.text('15:00'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"I have paid" asks the server, then shows the paid booking with KHQR', (tester) async {
      final repo = await _open(tester, _holding());
      await _tapPayByQr(tester);

      await tester.tap(find.byKey(const Key('check-payment')));
      await tester.pumpAndSettle();

      expect(repo.verifyCalls, 1);
      expect(find.byKey(const Key('paid-card')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('paid-text'))).data, contains('online with KHQR'));
      expect(find.byKey(const Key('qr-card')), findsNothing);
    });

    testWidgets('a QR that expired sends the guest back to the choices with the message', (tester) async {
      final repo = await _open(tester, _holding());
      repo.verifyQueue.add(const ApiError('The QR code expired. Please start again.', statusCode: 409, code: 'payment_expired'));
      await _tapPayByQr(tester);

      await tester.tap(find.byKey(const Key('check-payment')));
      await tester.pumpAndSettle();

      expect(find.text('The QR code expired. Please start again.'), findsOneWidget);
      expect(find.byKey(const Key('pay-qr')), findsOneWidget);
      expect(find.byKey(const Key('qr-card')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('any other server problem while checking shows its message and keeps the QR', (tester) async {
      final repo = await _open(tester, _holding());
      repo.verifyQueue.add(const ApiError('The amount does not match this booking. Please start again.', statusCode: 422, code: 'payment_mismatch'));
      await _tapPayByQr(tester);

      await tester.tap(find.byKey(const Key('check-payment')));
      await tester.pumpAndSettle();

      expect(find.text('The amount does not match this booking. Please start again.'), findsOneWidget);
      expect(find.byKey(const Key('qr-card')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('if the server refuses to start, the message shows and the guest can still choose', (tester) async {
      final repo = await _open(tester, _holding());
      repo.qrError = const ApiError('Your 5 minutes ran out and the room may be taken. Please book again.',
          statusCode: 409, code: 'hold_expired');

      await _tapPayByQr(tester);

      expect(find.text('Your 5 minutes ran out and the room may be taken. Please book again.'), findsOneWidget);
      expect(find.byKey(const Key('qr-card')), findsNothing);
      expect(find.byKey(const Key('pay-at-hotel')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"choose another way" goes back to the choices', (tester) async {
      await _open(tester, _holding());
      await _tapPayByQr(tester);

      await tester.ensureVisible(find.byKey(const Key('another-way')));
      await tester.tap(find.byKey(const Key('another-way')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay-card')), findsOneWidget);
      expect(find.byKey(const Key('qr-card')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('screens that open already paid, kept or run out', () {
    testWidgets('a paid booking opens straight on the paid page', (tester) async {
      await _open(tester, _paidByCard());

      expect(find.byKey(const Key('paid-card')), findsOneWidget);
      expect(find.byKey(const Key('countdown')), findsNothing);
      expect(find.text('Release this room'), findsNothing);
    });

    testWidgets('a hold that already ran out offers no way to pay', (tester) async {
      await _open(tester, _booking(hold: 0));

      expect(find.text('Hold ran out'), findsOneWidget);
      expect(find.byKey(const Key('pay-card')), findsNothing);
      expect(find.byKey(const Key('pay-qr')), findsNothing);
      expect(find.text('Back to rooms'), findsOneWidget);
    });

    testWidgets('releasing a room while paying tells the server', (tester) async {
      final repo = await _open(tester, _holding());
      await _tapPayByQr(tester);

      await tester.tap(find.text('Release this room'));
      await tester.pumpAndSettle();

      expect(repo.released, [7]);
      expect(find.byType(BookingHoldScreen), findsNothing);
      expect(find.text('The room was released.'), findsOneWidget);
    });
  });

  group('card input helpers', () {
    TextEditingValue run(TextInputFormatter f, String old, String now) =>
        f.formatEditUpdate(TextEditingValue(text: old), TextEditingValue(text: now));

    test('the card number is grouped in fours and limited to 19 digits', () {
      final f = CardNumberFormatter();
      expect(run(f, '', '4242424242424242').text, '4242 4242 4242 4242');
      expect(run(f, '', '4242 4242 42').text, '4242 4242 42');
      expect(run(f, '', 'ab12cd').text, '12');
      expect(run(f, '', '12345678901234567890123').text, '1234 5678 9012 3456 789');
    });

    test('the expiry date gets its slash by itself and keeps 4 digits', () {
      final f = ExpiryFormatter();
      expect(run(f, '', '1').text, '1');
      expect(run(f, '1', '11').text, '11/');
      expect(run(f, '11/', '11/2').text, '11/2');
      expect(run(f, '', '1126').text, '11/26');
      expect(run(f, '', '112699').text, '11/26');
    });

    test('the guest can delete back over the slash', () {
      final f = ExpiryFormatter();
      expect(run(f, '11/', '11').text, '11'); // deleted the slash: it does not come back at once
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

    test('Booking reads the discount and how it was paid', () {
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
        'payment_detail': 'Visa ending 4242',
        'hold_seconds_left': null,
      });

      expect(b.discountPercent, 15);
      expect(b.discountAmount, 4.5);
      expect(b.toPay, 25.5);
      expect(b.hasDiscount, isTrue);
      expect(b.paymentMethod, 'online');
      expect(b.paymentDetail, 'Visa ending 4242');
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
      expect(b.paymentDetail, isNull);
      expect(b.isPaidAndConfirmed, isFalse);
    });

    test('a cancelled or pending booking is never "paid and confirmed"', () {
      expect(_booking(status: 'cancelled', paid: true).isPaidAndConfirmed, isFalse);
      expect(_booking(status: 'pending', paid: true).isPaidAndConfirmed, isFalse);
      expect(_booking(status: 'confirmed', paid: false).isPaidAndConfirmed, isFalse);
      expect(_booking(status: 'checked_in', paid: true).isPaidAndConfirmed, isTrue);
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
