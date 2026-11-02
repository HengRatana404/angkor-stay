import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 10.0.2.2 is how the Android emulator reaches the PC.
const defaultBaseUrl = 'http://10.0.2.2:8000/api';
const _baseUrlKey = 'api_base_url';

/// Filled in main() before the app starts, so settings are ready on screen 1.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);

class BaseUrlNotifier extends Notifier<String> {
  @override
  String build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_baseUrlKey);
    return (saved != null && saved.isNotEmpty) ? saved : defaultBaseUrl;
  }

  Future<void> save(String url) async {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    await ref.read(sharedPreferencesProvider).setString(_baseUrlKey, clean);
    state = clean;
  }
}

final baseUrlProvider =
    NotifierProvider<BaseUrlNotifier, String>(BaseUrlNotifier.new);

/// The login token of the current user, or null when logged out.
class AuthTokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? token) => state = token;
}

final authTokenProvider =
    NotifierProvider<AuthTokenNotifier, String?>(AuthTokenNotifier.new);

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(authTokenProvider);
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
    ),
  );

  return dio;
});

class HealthStatus {
  final bool ok;
  final String message;
  const HealthStatus(this.ok, this.message);
}

final healthProvider = FutureProvider.autoDispose<HealthStatus>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final res = await dio.get('/health');
    final db = res.data['database'];
    return HealthStatus(true, 'API connected, database: $db');
  } on DioException catch (e) {
    if (e.response != null) {
      return HealthStatus(false, 'API answered with error ${e.response!.statusCode}');
    }
    return const HealthStatus(false, 'Cannot reach the server. Check the address.');
  }
});
