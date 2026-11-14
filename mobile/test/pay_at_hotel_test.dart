import 'package:angkor_stay/booking/booking_repository.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/core/format.dart';
import 'package:angkor_stay/core/public_settings_provider.dart';
import 'package:angkor_stay/models/public_settings.dart';
import 'package:angkor_stay/models/booking.dart';
import 'package:angkor_stay/models/staff_booking.dart';
import 'package:angkor_stay/screens/booking_hold_screen.dart';
import 'package:angkor_stay/widgets/status_chip.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Booking _holding({int seconds = 300}) => Booking(
      id: 7,
      code: 'AS-0007',
      status: 'pending',
      roomNumber: '101',
      roomTypeName: 'Single',
      coverImage: null,
      checkIn: DateTime.utc(2026, 11, 10),
      checkOut: DateTime.utc(2026, 11, 12),
      nights: 2,
      guests: 1,
      pricePerNight: 15,
      totalPrice: 30,
      holdSecondsLeft: seconds,
    );

Booking _kept() => Booking(
      id: 7,
      code: 'AS-0007',
      status: 'pending',
      roomNumber: '101',
      roomTypeName: 'Single',
      coverImage: null,
      checkIn: DateTime.utc(2026, 11, 10),
      checkOut: DateTime.utc(2026, 11, 12),
      nights: 2,
      guests: 1,
      pricePerNight: 15,
      totalPrice: 30,
      paymentChoice: 'hotel',
      holdSecondsLeft: null,
    );

class _FakeBookings extends BookingRepository {
  _FakeBookings() : super(Dio());

  ApiError? payError;
  final payCalls = <int>[];
  final released = <int>[];

  @override
  Future<Booking> payAtHotel(int bookingId) async {
    payCalls.add(bookingId);
    if (payError != null) throw payError!;
    return _kept();
  }

  @override
  Future<void> release(int bookingId) async => released.add(bookingId);
}

/// Opens the hold screen on top of a plain "ROOT" page, like the real app does.
Future<void> _open(WidgetTester tester, Booking booking, _FakeBookings repo) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      bookingRepositoryProvider.overrideWithValue(repo),
      publicSettingsProvider.overrideWith(
        (ref) async => const PublicSettings(onlineDiscountPercent: 15, checkInTime: '14:00', checkOutTime: '12:00'),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: Text('ROOT'))),
  ));

  final navigator = tester.state<NavigatorState>(find.byType(Navigator));
  navigator.push(MaterialPageRoute<void>(builder: (_) => BookingHoldScreen(booking: booking)));
  await tester.pumpAndSettle();
}

void main() {
  group('customer: pay at the hotel', () {
    testWidgets('the hold screen offers card, QR code and the hotel', (tester) async {
      await _open(tester, _holding(), _FakeBookings());

      expect(find.text('How do you want to pay?'), findsOneWidget);
      expect(find.text('Pay by card and save 15%'), findsOneWidget);
      expect(find.text('Pay with a QR code and save 15%'), findsOneWidget);
      expect(find.text('\$25.50 instead of \$30'), findsOneWidget);
      expect(find.text('Pay at the hotel'), findsOneWidget);
      expect(find.textContaining('No discount'), findsOneWidget);
      expect(find.byKey(const Key('countdown')), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // stop the timer
    });

    testWidgets('choosing it keeps the room, shows the booking code and stops the countdown', (tester) async {
      final repo = _FakeBookings();
      await _open(tester, _holding(), repo);

      await tester.tap(find.byKey(const Key('pay-at-hotel')));
      await tester.pumpAndSettle();

      expect(repo.payCalls, [7]);
      expect(find.byKey(const Key('kept-card')), findsOneWidget);
      expect(find.text('Room 101 is yours'), findsOneWidget);
      expect(find.byKey(const Key('booking-code')), findsOneWidget);
      expect(find.text('AS-0007'), findsOneWidget);
      expect(find.textContaining('You pay \$30 when you arrive'), findsOneWidget);
      expect(find.text('Paying at the hotel has no discount.'), findsOneWidget);

      // The countdown and the payment choices are gone.
      expect(find.byKey(const Key('countdown')), findsNothing);
      expect(find.text('How do you want to pay?'), findsNothing);
      expect(find.text('Release this room'), findsNothing);
      expect(find.text('Back to rooms'), findsOneWidget);
      expect(find.text('Cancel this booking'), findsOneWidget);

      // Ten minutes later the room is still kept.
      await tester.pump(const Duration(minutes: 10));
      expect(find.text('Hold ran out'), findsNothing);
      expect(find.byKey(const Key('kept-card')), findsOneWidget);
    });

    testWidgets('a hold that ran out shows the server message and keeps the choices', (tester) async {
      final repo = _FakeBookings()
        ..payError = const ApiError(
          'Your 5 minutes ran out and the room may be taken. Please book again.',
          statusCode: 409,
          code: 'hold_expired',
        );
      await _open(tester, _holding(), repo);

      await tester.tap(find.byKey(const Key('pay-at-hotel')));
      await tester.pumpAndSettle();

      expect(find.textContaining('5 minutes ran out'), findsOneWidget);
      expect(find.byKey(const Key('kept-card')), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('too many unpaid rooms shows the message', (tester) async {
      final repo = _FakeBookings()
        ..payError = const ApiError(
          'You already have 3 rooms waiting to be paid at the hotel. Cancel one first.',
          statusCode: 409,
          code: 'too_many_unpaid',
        );
      await _open(tester, _holding(), repo);

      await tester.tap(find.byKey(const Key('pay-at-hotel')));
      await tester.pumpAndSettle();

      expect(find.textContaining('3 rooms waiting'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a booking that is already kept opens straight on the kept page', (tester) async {
      await _open(tester, _kept(), _FakeBookings());

      expect(find.byKey(const Key('kept-card')), findsOneWidget);
      expect(find.text('AS-0007'), findsOneWidget);
      expect(find.byKey(const Key('countdown')), findsNothing);
    });

    testWidgets('cancelling a kept booking tells the server and goes back', (tester) async {
      final repo = _FakeBookings();
      await _open(tester, _kept(), repo);

      await tester.tap(find.byKey(const Key('cancel-kept')));
      await tester.pumpAndSettle();

      expect(repo.released, [7]);
      expect(find.byType(BookingHoldScreen), findsNothing);
      expect(find.text('ROOT'), findsOneWidget);
      expect(find.text('The booking was cancelled.'), findsOneWidget);
    });

    testWidgets('after the countdown ends the payment choices are gone', (tester) async {
      await _open(tester, _holding(seconds: 3), _FakeBookings());
      expect(find.text('Pay at the hotel'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));

      expect(find.text('Hold ran out'), findsOneWidget);
      expect(find.text('Pay at the hotel'), findsNothing);
      expect(find.text('Back to rooms'), findsOneWidget);
    });
  });

  group('models and helpers', () {
    test('Booking reads the new fields and knows when it is kept for the hotel', () {
      final json = {
        'id': 9,
        'code': 'AS-0009',
        'status': 'pending',
        'room_number': '301',
        'room_type': {'id': 3, 'name': 'VIP', 'cover_image': null},
        'check_in_date': '2026-11-10',
        'check_out_date': '2026-11-12',
        'nights': 2,
        'guests': 2,
        'price_per_night': 50,
        'total_price': 100,
        'payment_choice': 'hotel',
        'paid': false,
        'hold_seconds_left': null,
      };

      final kept = Booking.fromJson(json);
      expect(kept.code, 'AS-0009');
      expect(kept.paymentChoice, 'hotel');
      expect(kept.paid, isFalse);
      expect(kept.isKeptForHotel, isTrue);

      // A running hold is not "kept".
      final holding = Booking.fromJson({...json, 'payment_choice': null, 'hold_seconds_left': 120});
      expect(holding.isKeptForHotel, isFalse);

      // Paid bookings are not "kept" either.
      final confirmed = Booking.fromJson({...json, 'status': 'confirmed', 'paid': true});
      expect(confirmed.isKeptForHotel, isFalse);
      expect(confirmed.paid, isTrue);
    });

    test('StaffBooking reads the guest, the payments, who did what and the actions', () {
      final b = StaffBooking.fromJson({
        'id': 12,
        'code': 'AS-0012',
        'status': 'checked_in',
        'room_number': '102',
        'room_type': {'id': 1, 'name': 'Single'},
        'check_in_date': '2026-11-02',
        'check_out_date': '2026-11-04',
        'nights': 2,
        'guests': 1,
        'price_per_night': 15,
        'total_price': 30,
        'payment_choice': 'hotel',
        'paid': true,
        'hold_seconds_left': null,
        'guest': {'id': 5, 'name': 'Sok Dara', 'phone': '012345678', 'email': 'dara@example.com'},
        'payments': [
          {
            'id': 1,
            'amount': 30,
            'method': 'cash',
            'status': 'paid',
            'received_by': {'id': 2, 'name': 'Front Desk'},
            'paid_at': '2026-11-02T10:00:00+07:00',
          },
        ],
        'checked_in_at': '2026-11-02T11:00:00+07:00',
        'checked_in_by': {'id': 2, 'name': 'Front Desk'},
        'checked_out_at': null,
        'checked_out_by': null,
        'actions': {
          'can_take_payment': false,
          'can_check_in': false,
          'check_in_problem': 'This guest is already checked in.',
          'can_check_out': true,
        },
      });

      expect(b.guestName, 'Sok Dara');
      expect(b.guest!.phone, '012345678');
      expect(b.payments.single.method, 'cash');
      expect(b.payments.single.amount, 30);
      expect(b.payments.single.receivedBy!.name, 'Front Desk');
      expect(b.checkedInBy!.name, 'Front Desk');
      expect(b.checkedOutBy, isNull);
      expect(b.actions.canCheckOut, isTrue);
      expect(b.actions.canCheckIn, isFalse);
      expect(b.actions.checkInProblem, 'This guest is already checked in.');
    });

    test('a booking without a guest or payments still reads', () {
      final b = StaffBooking.fromJson({
        'id': 1,
        'code': 'AS-0001',
        'status': 'pending',
        'room_number': '101',
        'room_type': null,
        'check_in_date': '2026-11-02',
        'check_out_date': '2026-11-03',
        'nights': 1,
        'guests': 1,
        'price_per_night': 15,
        'total_price': 15,
        'payment_choice': null,
        'paid': false,
        'hold_seconds_left': 200,
        'guest': null,
        'payments': <Object>[],
        'checked_in_at': null,
        'checked_in_by': null,
        'checked_out_at': null,
        'checked_out_by': null,
        'actions': {'can_take_payment': true, 'can_check_in': false, 'check_in_problem': 'Take payment first.', 'can_check_out': false},
      });

      expect(b.guestName, 'Unknown guest');
      expect(b.payments, isEmpty);
      expect(b.roomTypeName, '');
    });

    test('status and payment words', () {
      expect(statusLabel('pending'), 'Waiting for payment');
      expect(statusLabel('confirmed'), 'Confirmed');
      expect(statusLabel('checked_in'), 'Checked in');
      expect(statusLabel('checked_out'), 'Checked out');
      expect(statusLabel('cancelled'), 'Cancelled');
      expect(statusLabel('no_show'), 'No-show');
      expect(statusLabel('something_new'), 'something_new');

      expect(methodLabel('khqr'), 'KHQR');
      expect(methodLabel('cash'), 'Cash');
      expect(methodLabel('card'), 'Card');
      expect(methodLabel('online'), 'Online');
    });

    test('formatDateTime shows the day and the time', () {
      final text = formatDateTime(DateTime(2026, 11, 5, 14, 5));
      expect(text, 'Thu 5 Nov 14:05');
    });

    testWidgets('StatusChip shows the words, not the code', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Column(children: [StatusChip('pending'), StatusChip('checked_in')]),
      ));

      expect(find.text('Waiting for payment'), findsOneWidget);
      expect(find.text('Checked in'), findsOneWidget);
      expect(find.text('pending'), findsNothing);
    });
  });
}
