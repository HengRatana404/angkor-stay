import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/public_settings.dart';
import 'api_client.dart';
import 'api_error.dart';

/// The online discount and the check-in time. Needs no login.
final publicSettingsProvider = FutureProvider.autoDispose<PublicSettings>((ref) async {
  try {
    final res = await ref.watch(dioProvider).get<dynamic>('/settings/public');
    return PublicSettings.fromJson(res.data['data'] as Map<String, dynamic>);
  } on DioException catch (e) {
    throw ApiError.from(e);
  }
});
