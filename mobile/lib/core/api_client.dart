import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Default to PC Wi-Fi IP so physical Android phone connects immediately.
const defaultBaseUrl = 'http://192.168.123.6:8000/api';
// Set at build time: --dart-define=TUNNEL_URL=https://your-tunnel/api
// (kept out of the public repo). Empty = no internet tunnel.
const cloudTunnelBaseUrl = String.fromEnvironment('TUNNEL_URL');
const _baseUrlKey = 'api_base_url';

/// Probes and discovers the server automatically without manual typing.
Future<String> detectBestServer() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 1500),
      receiveTimeout: const Duration(milliseconds: 1500),
      headers: {'ngrok-skip-browser-warning': 'true'},
    ),
  );

  // 1. Fast local Wi-Fi check (instant 0-latency for hotel desk & local guests)
  try {
    final localProbe = await dio.get<dynamic>('$defaultBaseUrl/health');
    if (localProbe.statusCode == 200) return defaultBaseUrl;
  } catch (_) {
    // Phone is outside local Wi-Fi (e.g. mobile 4G/5G or cafe)
  }

  // 2. Public internet tunnel (only when built with TUNNEL_URL)
  if (cloudTunnelBaseUrl.isNotEmpty) {
    try {
      final tunnelRes = await dio.get<dynamic>('$cloudTunnelBaseUrl/health');
      if (tunnelRes.statusCode == 200) return cloudTunnelBaseUrl;
    } catch (_) {}
  }

  // 3. Fallback: USB loopback
  try {
    final res = await dio.get<dynamic>('http://127.0.0.1:8000/api/health');
    if (res.statusCode == 200) return 'http://127.0.0.1:8000/api';
  } catch (_) {}

  return defaultBaseUrl;
}

/// Filled in main() before the app starts, so settings are ready on screen 1.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('Override sharedPreferencesProvider in main()'),
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

  Future<String> autoDetect() async {
    final detected = await detectBestServer();
    await save(detected);
    return detected;
  }
}

final baseUrlProvider = NotifierProvider<BaseUrlNotifier, String>(
  BaseUrlNotifier.new,
);

/// The login token of the current user, or null when logged out.
class AuthTokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? token) => state = token;
}

final authTokenProvider = NotifierProvider<AuthTokenNotifier, String?>(
  AuthTokenNotifier.new,
);

final dioProvider = Provider<Dio>((ref) {
  final baseUrl = ref.watch(baseUrlProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
        'ngrok-skip-browser-warning': 'true',
      },
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(authTokenProvider);
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) async {
        // Automatically auto-detect server and retry if connection was interrupted or timed out:
        final isNetworkError =
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.receiveTimeout;

        final path = error.requestOptions.path;
        if (isNetworkError && !path.contains('/health')) {
          try {
            final activeUrl = await ref
                .read(baseUrlProvider.notifier)
                .autoDetect();
            if (activeUrl != baseUrl) {
              final newOptions = error.requestOptions;
              newOptions.baseUrl = activeUrl;
              final retryRes = await dio.fetch<dynamic>(newOptions);
              return handler.resolve(retryRes);
            }
          } catch (_) {}
        }
        // Saved address is the internet tunnel, but the phone is now on the
        // hotel Wi-Fi: the server sees a public address and refuses staff.
        // Switch back to the Wi-Fi address and try once more.
        if (error.response?.statusCode == 403 && baseUrl != defaultBaseUrl) {
          try {
            final lan = await Dio(
              BaseOptions(
                connectTimeout: const Duration(milliseconds: 1500),
                receiveTimeout: const Duration(milliseconds: 1500),
              ),
            ).get<dynamic>('$defaultBaseUrl/health');
            if (lan.statusCode == 200) {
              await ref.read(baseUrlProvider.notifier).save(defaultBaseUrl);
              final newOptions = error.requestOptions..baseUrl = defaultBaseUrl;
              final retryRes = await dio.fetch<dynamic>(newOptions);
              return handler.resolve(retryRes);
            }
          } catch (_) {}
        }
        handler.next(error);
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
    final res = await dio.get<dynamic>('/health');
    final db = res.data['database'];
    return HealthStatus(true, 'API connected, database: $db');
  } on DioException catch (e) {
    if (e.response != null) {
      return HealthStatus(
        false,
        'API answered with error ${e.response!.statusCode}',
      );
    }
    return const HealthStatus(
      false,
      'Cannot reach the server. Check the address.',
    );
  }
});
