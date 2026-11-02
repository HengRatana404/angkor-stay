import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/api_error.dart';
import '../models/booking.dart';
import 'stay_provider.dart';

/// The answer to "I want to pay online".
class PayOnlineResult {
  final Booking booking;

  /// "online" (a real payment page from the payment company) or "demo" (faked, switched on by the admin).
  final String mode;
  final String? checkoutUrl;

  /// A sentence from the server for the guest, such as the sandbox test card to use.
  final String? hint;

  const PayOnlineResult({required this.booking, required this.mode, required this.checkoutUrl, this.hint});

  bool get isDemo => mode == 'demo';
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

  /// "I will pay online." The server saves the discount and opens a payment page
  /// (or, in demo mode, says the payment will be faked).
  Future<PayOnlineResult> payOnline(int bookingId) => _call(() async {
        final res = await dio.post('/bookings/$bookingId/pay-online');
        return PayOnlineResult(
          booking: _booking(res),
          mode: res.data['mode'] as String,
          checkoutUrl: res.data['checkout_url'] as String?,
          hint: res.data['checkout_hint'] as String?,
        );
      });

  /// "I paid." The server does not take our word: it asks the payment company.
  Future<Booking> verifyPayment(int bookingId) =>
      _call(() async => _booking(await dio.post('/bookings/$bookingId/verify-payment')));

  /// Demo mode only: the fake payment button.
  Future<Booking> demoPay(int bookingId) =>
      _call(() async => _booking(await dio.post('/bookings/$bookingId/demo-pay')));

  /// The guest's own bookings, newest first.
  Future<List<Booking>> mine() => _call(() async {
        final res = await dio.get('/bookings');
        return (res.data['data'] as List)
            .map((j) => Booking.fromJson(j as Map<String, dynamic>))
            .toList();
      });

  /// Cancel before check-in. Online money is sent back by the server first.
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
