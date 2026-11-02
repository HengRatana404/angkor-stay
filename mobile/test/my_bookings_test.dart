import 'package:angkor_stay/booking/booking_repository.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/models/booking.dart';
import 'package:angkor_stay/screens/my_bookings_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

Booking _b({
  int id = 1,
  String status = 'confirmed',
  bool paid = true,
  String? method = 'online',
  bool canCancel = true,
  double refunded = 0,
}) =>
    Booking(
      id: id,
      code: 'AS-000$id',
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
      holdSecondsLeft: null,
      paid: paid,
      paymentMethod: method,
      canCancel: canCancel,
      refundedAmount: refunded,
    );

class _Repo extends BookingRepository {
  _Repo(this.list) : super(Dio());
  final List<Booking> list;
  ApiError? cancelError;
  final cancelled = <int>[];

  @override
  Future<List<Booking>> mine() async => list;

  @override
  Future<Booking> cancel(int bookingId) async {
    if (cancelError != null) throw cancelError!;
    cancelled.add(bookingId);
    return _b(id: bookingId, status: 'cancelled', paid: false, method: null, canCancel: false, refunded: 30);
  }
}

Future<void> _pump(WidgetTester tester, Widget home, _Repo repo) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (c, e) => null,
    overrides: [bookingRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the list shows code, room, status and paid state', (tester) async {
    await _pump(tester, const MyBookingsScreen(),
        _Repo([_b(), _b(id: 2, status: 'pending', paid: false, method: null)]));

    expect(find.textContaining('AS-0001'), findsOneWidget);
    expect(find.textContaining('AS-0002'), findsOneWidget);
    expect(find.textContaining('Room 101'), findsNWidgets(2));
    expect(find.textContaining('Paid'), findsOneWidget);
    expect(find.textContaining('Not paid yet'), findsOneWidget);
  });

  testWidgets('an empty list says so', (tester) async {
    await _pump(tester, const MyBookingsScreen(), _Repo([]));
    expect(find.text('You have no bookings yet.'), findsOneWidget);
  });

  testWidgets('a confirmed booking shows a QR receipt', (tester) async {
    await _pump(tester, BookingDetailScreen(booking: _b()), _Repo([]));
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('a cancelled booking has no QR and no cancel button', (tester) async {
    await _pump(tester,
        BookingDetailScreen(booking: _b(status: 'cancelled', paid: false, canCancel: false, refunded: 30)), _Repo([]));
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Cancel booking'), findsNothing);
    expect(find.textContaining('Refunded'), findsOneWidget);
  });

  testWidgets('cancel asks first, then shows the refund', (tester) async {
    final repo = _Repo([]);
    await _pump(tester, BookingDetailScreen(booking: _b()), repo);

    await tester.tap(find.text('Cancel booking'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sent back in full'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
    await tester.pumpAndSettle();

    expect(repo.cancelled, [1]);
    expect(find.textContaining('Refunded'), findsWidgets);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('"Keep it" cancels nothing', (tester) async {
    final repo = _Repo([]);
    await _pump(tester, BookingDetailScreen(booking: _b()), repo);

    await tester.tap(find.text('Cancel booking'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();

    expect(repo.cancelled, isEmpty);
  });

  testWidgets('a refused cancel shows the server message', (tester) async {
    final repo = _Repo([])..cancelError = ApiError('We could not send your money back yet.');
    await _pump(tester, BookingDetailScreen(booking: _b()), repo);

    await tester.tap(find.text('Cancel booking'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not send your money back'), findsOneWidget);
  });

  testWidgets('paid at the front desk: no cancel button, a hint instead', (tester) async {
    await _pump(tester, BookingDetailScreen(booking: _b(method: 'cash', canCancel: false)), _Repo([]));
    expect(find.text('Cancel booking'), findsNothing);
    expect(find.textContaining('front desk'), findsWidgets);
  });
}
