import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Set at build time (kept out of the public repo):
//   --dart-define=TUNNEL_URL=https://your-tunnel/api
//   --dart-define=SERVER_INFO_KEY=the-same-value-as-SERVER_INFO_KEY-in-backend/.env
// Empty TUNNEL_URL = no internet tunnel.
const cloudTunnelBaseUrl = String.fromEnvironment('TUNNEL_URL');
const serverInfoKey = String.fromEnvironment('SERVER_INFO_KEY');

/// First guess for the Wi-Fi address, used until the app learns the real one.
const defaultBaseUrl = 'http://192.168.123.6:8000/api';
const _baseUrlKey = 'api_base_url';
const _lanUrlKey = 'lan_base_url';

/// The last Wi-Fi address that worked (or the first guess).
String savedLanUrl(SharedPreferences prefs) {
  final saved = prefs.getString(_lanUrlKey);
  return (saved != null && saved.isNotEmpty) ? saved : defaultBaseUrl;
}

/// True when [baseUrl] answers GET /health quickly.
Future<bool> _isAlive(String baseUrl, Duration limit) async {
  try {
    final res = await Dio(
      BaseOptions(
        connectTimeout: limit,
        receiveTimeout: limit,
        headers: {'ngrok-skip-browser-warning': 'true'},
      ),
    ).get<dynamic>('$baseUrl/health');
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// Asks the tunnel where the server is on the Wi-Fi now. The server keeps its
/// current Wi-Fi address in the database, so this still works after the router
/// gave the PC a new IP. Returns null when it cannot be learned.
Future<String?> fetchLanUrlFromTunnel({
  String tunnelUrl = cloudTunnelBaseUrl,
  String infoKey = serverInfoKey,
}) async {
  if (tunnelUrl.isEmpty || infoKey.isEmpty) return null;
  try {
    final res = await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
        headers: {
          'ngrok-skip-browser-warning': 'true',
          'X-Server-Key': infoKey,
        },
      ),
    ).get<dynamic>('$tunnelUrl/server-info');
    final data = res.data;
    final url = data is Map ? data['lan_url'] : null;
    return (url is String && url.isNotEmpty) ? url : null;
  } catch (_) {
    return null;
  }
}

/// True for the private address ranges used by home, school and hotel Wi-Fi.
bool isPrivateIPv4(String ip) {
  final p = ip.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.any((n) => n == null || n < 0 || n > 255)) {
    return false;
  }
  final a = p[0]!;
  final b = p[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// All 254 neighbours of [phoneIp] on the same /24 network (x.y.z.1 to .254).
List<String> subnetHosts(String phoneIp) {
  final p = phoneIp.split('.');
  final prefix = '${p[0]}.${p[1]}.${p[2]}';
  return [for (var i = 1; i <= 254; i++) '$prefix.$i'];
}

/// True for a network card that is Wi-Fi (Android wlan0, iPhone en0), not mobile data.
bool isWifiInterface(String name) {
  final n = name.toLowerCase();
  return n.startsWith('wlan') || n.startsWith('en') || n.contains('wi-fi');
}

/// The phone's own private addresses on Wi-Fi. Mobile data is left out, so the
/// scan never probes a phone company network.
Future<List<String>> phonePrivateIps() async {
  try {
    final cards = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final c in cards)
        if (isWifiInterface(c.name))
          for (final a in c.addresses)
            if (isPrivateIPv4(a.address)) a.address,
    ];
  } catch (_) {
    return [];
  }
}

/// Looks for our server on the Wi-Fi the phone is on: asks every neighbour
/// address on port [port] for /api/health and returns the first one that says
/// it is the Angkor Stay API. Needs no tunnel and no saved address.
///
/// [hosts] is for tests; leave it out to scan the phone's own Wi-Fi network.
Future<String?> scanForServer({
  List<String>? hosts,
  int port = 8000,
  Duration timeout = const Duration(milliseconds: 700),
}) async {
  var targets = hosts;
  if (targets == null) {
    final subnets = <String>{};
    final found = <String>[];
    for (final ip in (await phonePrivateIps()).take(2)) {
      if (subnets.add(ip.substring(0, ip.lastIndexOf('.')))) {
        found.addAll(subnetHosts(ip));
      }
    }
    targets = found;
  }
  if (targets.isEmpty) return null;

  final client = HttpClient()..connectionTimeout = timeout;
  final done = Completer<String?>();
  var pending = targets.length;
  void finish(String? result) {
    if (!done.isCompleted) done.complete(result);
  }

  Future<void> probe(String host) async {
    try {
      final limit = timeout * 2;
      final request = await client
          .getUrl(Uri.parse('http://$host:$port/api/health'))
          .timeout(limit);
      final response = await request.close().timeout(limit);
      final body = await response.transform(utf8.decoder).join().timeout(limit);
      if (response.statusCode == 200 && body.contains('Angkor Stay API')) {
        finish('http://$host:$port/api');
      }
    } catch (_) {
      // Nothing there, or not our server.
    } finally {
      pending--;
      if (pending == 0) finish(null);
    }
  }

  for (final host in targets) {
    unawaited(probe(host));
  }
  final result = await done.future;
  client.close(force: true);
  return result;
}

/// Probes and discovers the server automatically without manual typing.
///
/// Order: saved Wi-Fi address, then a scan of the Wi-Fi the phone is on, then
/// the tunnel (and, through it, the server's new Wi-Fi address).
Future<String> detectBestServer({
  String tunnelUrl = cloudTunnelBaseUrl,
  String infoKey = serverInfoKey,
  List<String>? scanHosts,
  int scanPort = 8000,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final lan = savedLanUrl(prefs);

  // 1. Saved Wi-Fi address (fast, works at the hotel).
  if (await _isAlive(lan, const Duration(milliseconds: 1200))) return lan;

  // 2. Look for the server on the Wi-Fi we are on (the PC may have a new IP).
  final scanned = await scanForServer(hosts: scanHosts, port: scanPort);
  if (scanned != null) {
    await prefs.setString(_lanUrlKey, scanned);
    return scanned;
  }

  // 3. The tunnel works from any network. Ask it for the server's current
  //    Wi-Fi address: if the PC got a new IP, we are on the same Wi-Fi again.
  final tunnelOk =
      tunnelUrl.isNotEmpty &&
      await _isAlive(tunnelUrl, const Duration(seconds: 4));
  if (tunnelOk) {
    final fresh = await fetchLanUrlFromTunnel(
      tunnelUrl: tunnelUrl,
      infoKey: infoKey,
    );
    if (fresh != null &&
        fresh != lan &&
        await _isAlive(fresh, const Duration(milliseconds: 1500))) {
      await prefs.setString(_lanUrlKey, fresh);
      return fresh;
    }
    return tunnelUrl;
  }

  return tunnelUrl.isNotEmpty ? tunnelUrl : lan;
}

/// Filled in main() before the app starts, so settings are ready on screen 1.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);

class BaseUrlNotifier extends Notifier<String> {
  @override
  String build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final saved = prefs.getString(_baseUrlKey);
    return (saved != null && saved.isNotEmpty) ? saved : savedLanUrl(prefs);
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
        if (error.response?.statusCode == 403 &&
            error.response?.data is Map &&
            (error.response!.data as Map)['code'] == 'outside_hotel_network') {
          // Staff and admin were refused because this address is the internet
          // tunnel. Find the Wi-Fi address (it may have changed) and retry once.
          try {
            final best = await detectBestServer();
            if (best != baseUrl && best != cloudTunnelBaseUrl) {
              await ref.read(baseUrlProvider.notifier).save(best);
              final newOptions = error.requestOptions..baseUrl = best;
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
