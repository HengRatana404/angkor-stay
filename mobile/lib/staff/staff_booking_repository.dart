import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/api_error.dart';
import '../models/staff_booking.dart';

/// Staff and admin calls: find bookings, take payment, check in and out.
class StaffBookingRepository {
  final Dio dio;
  const StaffBookingRepository(this.dio);

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  StaffBooking _one(Response<dynamic> res) =>
      StaffBooking.fromJson(res.data['data'] as Map<String, dynamic>);

  Future<List<StaffBooking>> list({String search = '', String? status}) => _call(() async {
        final res = await dio.get<dynamic>('/staff/bookings', queryParameters: {
          'search': ?(search.trim().isEmpty ? null : search.trim()),
          'status': ?status,
        });
        return (res.data['data'] as List)
            .map((e) => StaffBooking.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<StaffBooking> get(int id) => _call(() async => _one(await dio.get<dynamic>('/staff/bookings/$id')));

  /// [method] is khqr, cash or card. The amount is the booking's own total.
  Future<StaffBooking> takePayment(int id, String method) => _call(() async =>
      _one(await dio.post<dynamic>('/staff/bookings/$id/payments', data: {'method': method})));

  Future<StaffBooking> checkIn(int id) =>
      _call(() async => _one(await dio.post<dynamic>('/staff/bookings/$id/check-in')));

  Future<StaffBooking> checkOut(int id) =>
      _call(() async => _one(await dio.post<dynamic>('/staff/bookings/$id/check-out')));
}

final staffBookingRepositoryProvider = Provider<StaffBookingRepository>(
  (ref) => StaffBookingRepository(ref.watch(dioProvider)),
);

/// What the staff typed in the search box and which status chip is chosen.
class BookingFilter {
  final String search;
  final String? status;
  const BookingFilter({this.search = '', this.status});
}

class BookingFilterNotifier extends Notifier<BookingFilter> {
  @override
  BookingFilter build() => const BookingFilter();

  void setSearch(String search) => state = BookingFilter(search: search, status: state.status);

  void setStatus(String? status) => state = BookingFilter(search: state.search, status: status);
}

final bookingFilterProvider =
    NotifierProvider<BookingFilterNotifier, BookingFilter>(BookingFilterNotifier.new);

final staffBookingsProvider = FutureProvider.autoDispose<List<StaffBooking>>((ref) {
  final filter = ref.watch(bookingFilterProvider);
  return ref.watch(staffBookingRepositoryProvider).list(search: filter.search, status: filter.status);
});

final staffBookingProvider = FutureProvider.autoDispose.family<StaffBooking, int>(
  (ref, id) => ref.watch(staffBookingRepositoryProvider).get(id),
);
