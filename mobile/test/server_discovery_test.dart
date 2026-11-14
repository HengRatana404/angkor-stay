import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:angkor_stay/core/api_client.dart';

/// A tiny real server on localhost, so the tests use real network calls.
class _FakeServer {
  _FakeServer._(this._server, this.requests);

  final HttpServer _server;
  final List<HttpRequest> requests;

  /// Base address the app would use, like http://127.0.0.1:5000/api
  String get url => 'http://127.0.0.1:${_server.port}/api';
  int get port => _server.port;

  static Future<_FakeServer> start({
    int healthStatus = 200,
    int infoStatus = 200,
    Object? infoBody,
    String appName = 'Angkor Stay API',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <HttpRequest>[];
    final fake = _FakeServer._(server, requests);
    server.listen((request) async {
      requests.add(request);
      final path = request.uri.path;
      if (path == '/api/health') {
        request.response.statusCode = healthStatus;
        request.response.write(jsonEncode({'app': appName, 'status': 'ok'}));
      } else if (path == '/api/server-info') {
        request.response.statusCode = infoStatus;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(infoBody ?? {}));
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    return fake;
  }

  Future<void> stop() => _server.close(force: true);
}

/// An address where nothing listens: connecting is refused at once.
Future<String> _deadUrl() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final url = 'http://127.0.0.1:${server.port}/api';
  await server.close(force: true);
  return url;
}

void main() {
  final toStop = <_FakeServer>[];

  Future<_FakeServer> serve({
    int healthStatus = 200,
    int infoStatus = 200,
    Object? infoBody,
    String appName = 'Angkor Stay API',
  }) async {
    final s = await _FakeServer.start(
      healthStatus: healthStatus,
      infoStatus: infoStatus,
      infoBody: infoBody,
      appName: appName,
    );
    toStop.add(s);
    return s;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() async {
    for (final s in toStop) {
      await s.stop();
    }
    toStop.clear();
  });

  group('fetchLanUrlFromTunnel', () {
    test('returns the Wi-Fi address and sends the secret key', () async {
      final tunnel = await serve(
        infoBody: {
          'lan_ip': '10.0.0.46',
          'lan_url': 'http://10.0.0.46:8000/api',
        },
      );

      final url = await fetchLanUrlFromTunnel(
        tunnelUrl: tunnel.url,
        infoKey: 'secret-key',
      );

      expect(url, 'http://10.0.0.46:8000/api');
      final sent = tunnel.requests.single;
      expect(sent.headers.value('X-Server-Key'), 'secret-key');
    });

    test(
      'does not call the server when there is no key or no tunnel',
      () async {
        final tunnel = await serve(
          infoBody: {'lan_url': 'http://10.0.0.5:8000/api'},
        );

        expect(
          await fetchLanUrlFromTunnel(tunnelUrl: tunnel.url, infoKey: ''),
          isNull,
        );
        expect(
          await fetchLanUrlFromTunnel(tunnelUrl: '', infoKey: 'secret-key'),
          isNull,
        );
        expect(tunnel.requests, isEmpty);
      },
    );

    test(
      'returns null when the server says 404 (wrong key or switched off)',
      () async {
        final tunnel = await serve(
          infoStatus: 404,
          infoBody: {'message': 'Not found.'},
        );

        expect(
          await fetchLanUrlFromTunnel(tunnelUrl: tunnel.url, infoKey: 'wrong'),
          isNull,
        );
      },
    );

    test('returns null when lan_url is missing or null', () async {
      final noUrl = await serve(infoBody: {'lan_ip': null, 'lan_url': null});
      final empty = await serve(infoBody: <String, dynamic>{});

      expect(
        await fetchLanUrlFromTunnel(tunnelUrl: noUrl.url, infoKey: 'k'),
        isNull,
      );
      expect(
        await fetchLanUrlFromTunnel(tunnelUrl: empty.url, infoKey: 'k'),
        isNull,
      );
    });

    test('returns null when the tunnel cannot be reached', () async {
      expect(
        await fetchLanUrlFromTunnel(tunnelUrl: await _deadUrl(), infoKey: 'k'),
        isNull,
      );
    });
  });

  group('detectBestServer', () {
    test(
      'uses the saved Wi-Fi address when it answers, without the tunnel',
      () async {
        final lan = await serve();
        final tunnel = await serve(
          infoBody: {'lan_url': 'http://10.0.0.9:8000/api'},
        );
        SharedPreferences.setMockInitialValues({'lan_base_url': lan.url});

        final best = await detectBestServer(
          scanHosts: const [],
          tunnelUrl: tunnel.url,
          infoKey: 'k',
        );

        expect(best, lan.url);
        expect(tunnel.requests, isEmpty);
      },
    );

    test('learns the new Wi-Fi address from the tunnel and saves it', () async {
      // The PC got a new IP: the saved address is dead, the new one answers.
      final newLan = await serve();
      final tunnel = await serve(
        infoBody: {'lan_ip': '127.0.0.1', 'lan_url': newLan.url},
      );
      SharedPreferences.setMockInitialValues({
        'lan_base_url': await _deadUrl(),
      });

      final best = await detectBestServer(
        scanHosts: const [],
        tunnelUrl: tunnel.url,
        infoKey: 'k',
      );

      expect(best, newLan.url);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lan_base_url'), newLan.url);
      expect(savedLanUrl(prefs), newLan.url);
    });

    test(
      'stays on the tunnel when the new Wi-Fi address is not reachable',
      () async {
        // The phone is on another network: the tunnel works, the Wi-Fi address does not.
        final tunnel = await serve(infoBody: {'lan_url': await _deadUrl()});
        final oldLan = await _deadUrl();
        SharedPreferences.setMockInitialValues({'lan_base_url': oldLan});

        final best = await detectBestServer(
          scanHosts: const [],
          tunnelUrl: tunnel.url,
          infoKey: 'k',
        );

        expect(best, tunnel.url);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('lan_base_url'), oldLan);
      },
    );

    test(
      'stays on the tunnel when the tunnel gives no Wi-Fi address',
      () async {
        final tunnel = await serve(
          infoStatus: 404,
          infoBody: {'message': 'Not found.'},
        );
        SharedPreferences.setMockInitialValues({
          'lan_base_url': await _deadUrl(),
        });

        final best = await detectBestServer(
          scanHosts: const [],
          tunnelUrl: tunnel.url,
          infoKey: 'wrong',
        );

        expect(best, tunnel.url);
      },
    );

    test(
      'stays on the tunnel when the tunnel returns the same dead address',
      () async {
        // The tunnel only repeats the saved address, which is dead: nothing new to try.
        final dead = await _deadUrl();
        final tunnel = await serve(infoBody: {'lan_url': dead});
        SharedPreferences.setMockInitialValues({'lan_base_url': dead});

        final best = await detectBestServer(
          scanHosts: const [],
          tunnelUrl: tunnel.url,
          infoKey: 'k',
        );

        expect(best, tunnel.url);
      },
    );

    test(
      'with no tunnel and nothing alive it returns the saved Wi-Fi address',
      () async {
        final dead = await _deadUrl();
        SharedPreferences.setMockInitialValues({'lan_base_url': dead});

        final best = await detectBestServer(
          scanHosts: const [],
          tunnelUrl: '',
          infoKey: '',
        );

        expect(best, dead);
      },
    );

    test('uses the built-in first guess when nothing was saved yet', () async {
      final best = await detectBestServer(
        scanHosts: const [],
        tunnelUrl: '',
        infoKey: '',
      );

      expect(best, defaultBaseUrl);
    });
  });

  group('scanning the Wi-Fi', () {
    test('subnetHosts lists the 254 neighbours of the phone', () {
      final hosts = subnetHosts('10.0.0.58');

      expect(hosts, hasLength(254));
      expect(hosts.first, '10.0.0.1');
      expect(hosts.last, '10.0.0.254');
    });

    test('isPrivateIPv4 accepts Wi-Fi ranges only', () {
      expect(isPrivateIPv4('10.0.0.5'), isTrue);
      expect(isPrivateIPv4('192.168.0.20'), isTrue);
      expect(isPrivateIPv4('172.16.4.4'), isTrue);
      expect(isPrivateIPv4('172.32.0.1'), isFalse);
      expect(isPrivateIPv4('8.8.8.8'), isFalse);
      expect(isPrivateIPv4('127.0.0.1'), isFalse);
      expect(isPrivateIPv4('not an ip'), isFalse);
    });

    test('isWifiInterface accepts Wi-Fi cards but not mobile data', () {
      expect(isWifiInterface('wlan0'), isTrue);
      expect(isWifiInterface('en0'), isTrue);
      expect(isWifiInterface('Wi-Fi'), isTrue);
      expect(isWifiInterface('rmnet_data1'), isFalse);
      expect(isWifiInterface('pdp_ip0'), isFalse);
      expect(isWifiInterface('lo'), isFalse);
    });

    test('finds our server among other addresses', () async {
      final ours = await serve();

      final found = await scanForServer(
        hosts: const ['127.0.0.2', '127.0.0.1', '127.0.0.3'],
        port: ours.port,
        timeout: const Duration(milliseconds: 300),
      );

      expect(found, ours.url);
    });

    test('ignores another web server that is not ours', () async {
      final stranger = await serve(appName: 'Some Other App');

      final found = await scanForServer(
        hosts: const ['127.0.0.1'],
        port: stranger.port,
        timeout: const Duration(milliseconds: 300),
      );

      expect(found, isNull);
    });

    test('returns null when nothing answers', () async {
      final dead = Uri.parse(await _deadUrl()).port;

      final found = await scanForServer(
        hosts: const ['127.0.0.1'],
        port: dead,
        timeout: const Duration(milliseconds: 300),
      );

      expect(found, isNull);
    });

    test('detectBestServer finds a new Wi-Fi address by scanning, without the tunnel', () async {
      final newLan = await serve();
      final tunnel = await serve(
        infoBody: {'lan_url': 'http://10.0.0.9:8000/api'},
      );
      SharedPreferences.setMockInitialValues({
        'lan_base_url': await _deadUrl(),
      });

      final best = await detectBestServer(
        scanHosts: const ['127.0.0.1'],
        scanPort: newLan.port,
        tunnelUrl: tunnel.url,
        infoKey: 'k',
      );

      expect(best, newLan.url);
      expect(tunnel.requests, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('lan_base_url'), newLan.url);
    });

    test('detectBestServer works with no tunnel at all', () async {
      final newLan = await serve();
      SharedPreferences.setMockInitialValues({
        'lan_base_url': await _deadUrl(),
      });

      final best = await detectBestServer(
        scanHosts: const ['127.0.0.1'],
        scanPort: newLan.port,
        tunnelUrl: '',
        infoKey: '',
      );

      expect(best, newLan.url);
    });

    test(
      'detectBestServer goes on to the tunnel when the scan finds nothing',
      () async {
        final tunnel = await serve(infoStatus: 404, infoBody: {});
        SharedPreferences.setMockInitialValues({
          'lan_base_url': await _deadUrl(),
        });

        final best = await detectBestServer(
          scanHosts: const ['127.0.0.1'],
          scanPort: Uri.parse(await _deadUrl()).port,
          tunnelUrl: tunnel.url,
          infoKey: 'k',
        );

        expect(best, tunnel.url);
      },
    );
  });
}
