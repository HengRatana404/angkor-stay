import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../booking/stay_provider.dart';
import '../core/api_client.dart';
import '../core/api_error.dart';
import '../models/room_type.dart';

/// The room types, with "rooms left" for the nights in [stayProvider].
final roomTypesProvider = FutureProvider.autoDispose<List<RoomType>>((ref) async {
  final stay = ref.watch(stayProvider);

  try {
    final res = await ref.watch(dioProvider).get<dynamic>('/room-types', queryParameters: {
      'check_in_date': stay.checkInText,
      'check_out_date': stay.checkOutText,
    });
    final list = res.data['data'] as List;
    return list
        .map((e) => RoomType.fromJson(e as Map<String, dynamic>))
        .toList();
  } on DioException catch (e) {
    throw ApiError.from(e);
  }
});
