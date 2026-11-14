import 'package:angkor_stay/auth/auth_provider.dart';
import 'package:angkor_stay/core/api_client.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/main.dart';
import 'package:angkor_stay/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A server that can be switched off and on, like the real one.
class _Server {
  bool down = true;
  String downMessage = 'Server not reachable. The tunnel or the server may be off. Try again in a moment.';
  int asked = 0; // how many times the app asked "who am I?"
  Duration delay = Duration.zero; // how long the server takes to answer
}

class _FlakyAuth extends AuthNotifier {
  final _Server server;
  _FlakyAuth(this.server);

  @override
  Future<AppUser?> build() async {
    server.asked++;
    if (server.delay > Duration.zero) await Future<void>.delayed(server.delay);
    if (server.down) throw ApiError(server.downMessage);
    return null; // server is back and nobody is logged in: the login screen shows
  }
}

Future<void> _open(WidgetTester tester, _Server server, {String theme = 'light'}) async {
  SharedPreferences.setMockInitialValues({'theme_mode': theme});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        authProvider.overrideWith(() => _FlakyAuth(server)),
      ],
      child: const AngkorStayApp(),
    ),
  );
  await tester.pumpAndSettle();
}

// ------------------------------------------------------------------ colour helpers

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// The colour a Text really paints with (its own colour, or the one it inherits).
Color _textColor(WidgetTester tester, Finder finder) {
  final element = tester.element(finder);
  final widget = tester.widget<Text>(finder);
  return DefaultTextStyle.of(element).style.merge(widget.style).color!;
}

Color _pageColor(WidgetTester tester) {
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
  return scaffold.backgroundColor ?? Theme.of(tester.element(find.byType(Scaffold).first)).scaffoldBackgroundColor;
}

/// The colour of the app bar itself (the title sits on it, not on the page).
Color _appBarColor(WidgetTester tester) {
  final bar = tester.widget<AppBar>(find.byType(AppBar));
  return bar.backgroundColor ?? Theme.of(tester.element(find.byType(AppBar))).appBarTheme.backgroundColor!;
}

/// The fill of a FilledButton, as painted.
Color _buttonFill(WidgetTester tester, Finder button) {
  final material = tester.widget<Material>(find.descendant(of: button, matching: find.byType(Material)).first);
  return material.color!;
}

void main() {
  for (final theme in ['light', 'dark']) {
    group('Connection Issue screen is readable in $theme mode', () {
      testWidgets('the title, the app bar name and the message can be read on the page', (tester) async {
        await _open(tester, _Server(), theme: theme);
        final page = _pageColor(tester);

        expect(_contrast(_textColor(tester, find.text('Connection Issue')), page), greaterThanOrEqualTo(4.5), reason: 'title');
        expect(
          _contrast(_textColor(tester, find.text('Angkor Stay')), _appBarColor(tester)),
          greaterThanOrEqualTo(4.5),
          reason: 'app bar name on the app bar',
        );
        expect(
          _contrast(_textColor(tester, find.textContaining('Server not reachable')), page),
          greaterThanOrEqualTo(3.0),
          reason: 'message',
        );
      });

      testWidgets('the "Auto-Detect Server & Reconnect" text can be read on its button', (tester) async {
        await _open(tester, _Server(), theme: theme);
        final button = find.widgetWithText(FilledButton, 'Auto-Detect Server & Reconnect');
        expect(button, findsOneWidget);

        final fill = _buttonFill(tester, button);
        final label = _textColor(tester, find.text('Auto-Detect Server & Reconnect'));
        expect(_contrast(label, fill), greaterThanOrEqualTo(4.5), reason: 'button text on button fill');
        expect(_contrast(fill, _pageColor(tester)), greaterThanOrEqualTo(1.5), reason: 'button stands out from the page');
      });
    });
  }

  group('no settings gear', () {
    for (final message in [
      'Server not reachable. The tunnel or the server may be off. Try again in a moment.',
      'Staff and admin can only use the app on the hotel network.',
    ]) {
      testWidgets('the Connection Issue screen has no gear for "$message"', (tester) async {
        await _open(tester, _Server()..downMessage = message);

        expect(find.byIcon(Icons.settings_outlined), findsNothing);
        expect(find.byTooltip('Server Address'), findsNothing);
        expect(find.byType(IconButton), findsNothing); // nothing else in the app bar either
        // the buttons that matter are still there
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Log out on this phone'), findsOneWidget);
      });
    }
  });

  group('when the server comes back', () {
    testWidgets('the screen reconnects by itself, without closing the app', (tester) async {
      final server = _Server();
      await _open(tester, server);
      expect(find.text('Connection Issue'), findsOneWidget);

      server.down = false; // the server is started again
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.text('Connection Issue'), findsNothing);
      expect(find.text('Welcome back'), findsOneWidget); // the app is working again
    });

    testWidgets('while the server is still off it keeps trying and keeps the screen', (tester) async {
      final server = _Server();
      await _open(tester, server);
      final first = server.asked;

      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(server.asked, greaterThan(first));
      expect(find.text('Connection Issue'), findsOneWidget);
      expect(find.textContaining('Server not reachable'), findsOneWidget);
    });

    test('which errors count as "the server is down" (and so are retried)', () {
      // down: the app should keep asking until the server answers
      expect(isServerDownError(const ApiError('Server not reachable. The tunnel or the server may be off.')), isTrue);
      expect(isServerDownError(const ApiError('Cannot reach the server. Check the address and try again.')), isTrue);
      expect(isServerDownError('The request timed out'), isTrue);
      expect(isServerDownError('SocketException: connection refused'), isTrue);
      // not down: asking again would give the same answer
      expect(isServerDownError(const ApiError('Staff and admin can only use the app on the hotel network.')), isFalse);
      expect(isServerDownError(const ApiError('Booking not found.')), isFalse);
      expect(isServerDownError(const ApiError('Too many tries. Please wait a moment.')), isFalse);
    });

    testWidgets('while it asks again, the Connection Issue screen stays (no flashing spinner)', (tester) async {
      final server = _Server();
      await _open(tester, server);
      server.delay = const Duration(seconds: 3); // the next answer is slow

      await tester.pump(const Duration(seconds: 5)); // the retry starts
      await tester.pump(const Duration(milliseconds: 500)); // ...and is still waiting for the server

      expect(find.text('Connection Issue'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Connection Issue'), findsOneWidget);

      // finish cleanly: no slow answer left waiting when the test ends
      server.delay = Duration.zero;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('once it is back it stops asking', (tester) async {
      final server = _Server();
      await _open(tester, server);

      server.down = false;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      final afterRecovery = server.asked;

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      expect(server.asked, afterRecovery);
    });

    testWidgets('staff outside the hotel network are NOT retried again and again', (tester) async {
      final server = _Server()..downMessage = 'Staff and admin can only use the app on the hotel network.';
      await _open(tester, server);
      expect(find.text('Hotel Wi-Fi Required'), findsOneWidget);
      final first = server.asked;

      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();

      expect(server.asked, first);
    });
  });
}
