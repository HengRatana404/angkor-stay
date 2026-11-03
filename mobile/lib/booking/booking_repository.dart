import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/api_error.dart';
import '../models/booking.dart';
import 'stay_provider.dart';

/// An open QR payment: the text inside the QR code and how long it is good for.
/// The payment is simulated, but the server writes it to the database and checks it there.
class QrPayment {
  final Booking booking;
  final String reference;

  /// The text to draw as a QR code (KHQR layout).
  final String payload;
  final double amount;
  final String merchant;
  final int secondsLeft;

  const QrPayment({
    required this.booking,
    required this.reference,
    required this.payload,
    required this.amount,
    required this.merchant,
    required this.secondsLeft,
  });
}

class BookingRepository {
  final Dio dio;
  const BookingRepository(this.dio);

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  Booking _booking(Response<dynamic> res) =>
      Booking.fromJson(res.data['data'] as Map<String, dynamic>);

  /// Asks the server for a room. The room is checked first and held for
  /// 5 minutes. Nothing is paid here.
  Future<Booking> create({required int roomTypeId, required Stay stay}) => _call(() async {
        final res = await dio.post('/bookings', data: {
          'room_type_id': roomTypeId,
          'check_in_date': stay.checkInText,
          'check_out_date': stay.checkOutText,
          'guests': stay.guests,
        });
        return _booking(res);
      });

  /// "I will pay at the hotel." The room is kept with no countdown.
  Future<Booking> payAtHotel(int bookingId) =>
      _call(() async => _booking(await dio.post('/bookings/$bookingId/pay-at-hotel')));

  /// Pay with a card. Any card works (the payment is simulated), unless it has expired.
  /// The server saves the payment, checks it in the database and confirms the booking.
  /// Wrong fields come back as an [ApiError] with `fieldErrors` (number, holder, expiry, cvv).
  Future<Booking> payByCard(
    int bookingId, {
    required String number,
    required String holder,
    required String expiry,
    required String cvv,
  }) =>
      _call(() async {
        final res = await dio.post('/bookings/$bookingId/pay-card', data: {
          'number': number,
          'holder': holder,
          'expiry': expiry,
          'cvv': cvv,
        });
        return _booking(res);
      });

  /// Pay with a QR code. The server opens the payment in the database and gives us the QR text.
  Future<QrPayment> startQr(int bookingId) => _call(() async {
        final res = await dio.post('/bookings/$bookingId/pay-qr');
        final qr = res.data['qr'] as Map<String, dynamic>;
        return QrPayment(
          booking: _booking(res),
          reference: qr['reference'] as String,
          payload: qr['payload'] as String,
          amount: (qr['amount'] as num).toDouble(),
          merchant: (qr['merchant'] ?? 'Angkor Stay') as String,
          secondsLeft: (qr['seconds_left'] as num).toInt(),
        );
      });

  /// "I paid." The server does not take our word: it finds the open QR payment in the database,
  /// checks it, and only then confirms the booking.
  Future<Booking> verifyPayment(int bookingId) =>
      _call(() async => _booking(await dio.post('/bookings/$bookingId/verify-payment')));

  /// The guest's own bookings, newest first.
  Future<List<Booking>> mine() => _call(() async {
        final res = await dio.get('/bookings');
        return (res.data['data'] as List)
            .map((j) => Booking.fromJson(j as Map<String, dynamic>))
            .toList();
      });

  /// Cancel before check-in. A paid online booking is refunded in full.
  Future<Booking> cancel(int bookingId) =>
      _call(() async => _booking(await dio.post('/bookings/$bookingId/cancel')));

  Future<void> release(int bookingId) => _call(() async {
        await dio.post('/bookings/$bookingId/release');
      });
}

final bookingRepositoryProvider = Provider<BookingRepository>(
  (ref) => BookingRepository(ref.watch(dioProvider)),
);

final myBookingsProvider = FutureProvider.autoDispose<List<Booking>>(
  (ref) => ref.watch(bookingRepositoryProvider).mine(),
);
