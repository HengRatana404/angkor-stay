import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/api_error.dart';
import '../models/admin_room.dart';
import '../models/dashboard.dart';
import '../models/hotel_settings.dart';
import '../models/staff_member.dart';

/// What the automatic jobs did when they ran.
class CleanupResult {
  final int expiredHolds;
  final int noShows;
  final double refunded;
  final int failed;

  const CleanupResult({
    required this.expiredHolds,
    required this.noShows,
    required this.refunded,
    required this.failed,
  });

  String get summary {
    final text = '$expiredHolds old hold${expiredHolds == 1 ? '' : 's'} tidied up, '
        '$noShows no-show${noShows == 1 ? '' : 's'} marked'
        '${refunded > 0 ? ' (\$${refunded.toStringAsFixed(2)} refunded)' : ''}.';
    return failed > 0 ? '$text $failed refund${failed == 1 ? '' : 's'} failed and will be tried again.' : text;
  }
}

/// Admin-only calls: staff accounts and hotel settings.
class AdminRepository {
  final Dio dio;
  const AdminRepository(this.dio);

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<List<StaffMember>> staff() => _call(() async {
        final res = await dio.get('/admin/staff');
        return (res.data['data'] as List)
            .map((e) => StaffMember.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<StaffMember> createStaff({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) =>
      _call(() async {
        final res = await dio.post('/admin/staff', data: {
          'name': name,
          'email': email,
          'phone': phone,
          'password': password,
        });
        return StaffMember.fromJson(res.data['data'] as Map<String, dynamic>);
      });

  /// Only the fields that are given are sent.
  Future<StaffMember> updateStaff(
    int id, {
    String? name,
    String? phone,
    bool? isActive,
    String? password,
  }) =>
      _call(() async {
        final res = await dio.patch('/admin/staff/$id', data: {
          'name': ?name,
          'phone': ?phone,
          'is_active': ?isActive,
          'password': ?password,
        });
        return StaffMember.fromJson(res.data['data'] as Map<String, dynamic>);
      });

  /// Runs the automatic jobs now: tidy old holds, mark no-shows and refund them.
  Future<CleanupResult> runCleanup() => _call(() async {
        final res = await dio.post('/admin/maintenance/run');
        final d = res.data['data'] as Map<String, dynamic>;
        return CleanupResult(
          expiredHolds: d['expired_holds'] as int,
          noShows: d['no_shows'] as int,
          refunded: (d['refunded'] as num).toDouble(),
          failed: d['failed'] as int,
        );
      });

  Future<Dashboard> dashboard() => _call(() async {
        final res = await dio.get('/admin/dashboard');
        return Dashboard.fromJson(res.data['data'] as Map<String, dynamic>);
      });

  // ----------------------------------------------------- room types and rooms

  Future<List<AdminRoomType>> roomTypes() => _call(() async {
        final res = await dio.get('/admin/room-types');
        return (res.data['data'] as List)
            .map((e) => AdminRoomType.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Creates a room type (id null) or changes one. Photos are web links; the first is the cover.
  Future<AdminRoomType> saveRoomType({
    int? id,
    required String name,
    required String description,
    required double price,
    required int capacity,
    required List<String> images,
  }) =>
      _call(() async {
        final body = {
          'name': name,
          'description': description,
          'price_per_night': price,
          'capacity': capacity,
          'images': images,
        };
        final res = id == null
            ? await dio.post('/admin/room-types', data: body)
            : await dio.patch('/admin/room-types/$id', data: body);
        return AdminRoomType.fromJson(res.data['data'] as Map<String, dynamic>);
      });

  Future<void> deleteRoomType(int id) => _call(() async {
        await dio.delete('/admin/room-types/$id');
      });

  Future<void> addRoom({required int roomTypeId, required String roomNumber, required int floor}) =>
      _call(() async {
        await dio.post('/admin/rooms',
            data: {'room_type_id': roomTypeId, 'room_number': roomNumber, 'floor': floor});
      });

  Future<void> setRoomStatus(int roomId, {required bool maintenance}) => _call(() async {
        await dio.patch('/admin/rooms/$roomId',
            data: {'status': maintenance ? 'maintenance' : 'available'});
      });

  Future<void> deleteRoom(int roomId) => _call(() async {
        await dio.delete('/admin/rooms/$roomId');
      });

  Future<SettingsResult> settings() => _call(() async {
        final res = await dio.get('/admin/settings');
        return _settingsResult(res.data as Map<String, dynamic>);
      });

  Future<SettingsResult> saveSettings(HotelSettings settings) => _call(() async {
        final res = await dio.put('/admin/settings', data: settings.toJson());
        return _settingsResult(res.data as Map<String, dynamic>);
      });

  SettingsResult _settingsResult(Map<String, dynamic> body) => SettingsResult(
        HotelSettings.fromJson(body['data'] as Map<String, dynamic>),
        (body['your_ip'] ?? '') as String,
      );
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(dioProvider)),
);

final staffListProvider = FutureProvider.autoDispose<List<StaffMember>>(
  (ref) => ref.watch(adminRepositoryProvider).staff(),
);

final dashboardProvider = FutureProvider.autoDispose<Dashboard>(
  (ref) => ref.watch(adminRepositoryProvider).dashboard(),
);

final adminRoomTypesProvider = FutureProvider.autoDispose<List<AdminRoomType>>(
  (ref) => ref.watch(adminRepositoryProvider).roomTypes(),
);

final hotelSettingsProvider = FutureProvider.autoDispose<SettingsResult>(
  (ref) => ref.watch(adminRepositoryProvider).settings(),
);
