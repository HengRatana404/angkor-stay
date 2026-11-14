import 'package:angkor_stay/auth/auth_provider.dart';
import 'package:angkor_stay/core/api_client.dart';
import 'package:angkor_stay/main.dart';
import 'package:angkor_stay/models/app_user.dart';
import 'package:angkor_stay/screens/profile_screen.dart';
import 'package:angkor_stay/widgets/angkor_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _admin = AppUser(id: 1, name: 'Hotel Admin', email: 'admin@angkorstay.test', phone: '085000001', role: 'admin');
const _staff = AppUser(id: 2, name: 'Front Desk', email: 'staff@angkorstay.test', phone: '085000002', role: 'staff');
const _guest = AppUser(id: 9, name: 'Sok Dara', email: 'dara@example.com', phone: '012345678', role: 'customer');

class _FakeAuth extends AuthNotifier {
  final AppUser? user;
  _FakeAuth(this.user);

  @override
  Future<AppUser?> build() async => user;
}

Future<void> _show(WidgetTester tester, {required AppUser? loggedIn, bool profileOnly = false}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        authProvider.overrideWith(() => _FakeAuth(loggedIn)),
        healthProvider.overrideWith((ref) async => const HealthStatus(true, 'API connected')),
      ],
      child: profileOnly ? const MaterialApp(home: ProfileScreen()) : const AngkorStayApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Nothing on screen may let a person type or pick a server address.
void _expectNoServerAddressWay(WidgetTester tester) {
  expect(find.text('Server address'), findsNothing);
  expect(find.text('API URL'), findsNothing);
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.text('Network & Server'), findsNothing);
  expect(find.byIcon(Icons.settings_ethernet), findsNothing);
  expect(find.text('Auto-Detect Server (Smart)'), findsNothing);
}

void main() {
  group('login screen', () {
    testWidgets('a long-press on the logo no longer opens the Server address window', (tester) async {
      await _show(tester, loggedIn: null);
      expect(find.text('Welcome back'), findsOneWidget); // the login screen

      await tester.longPress(find.byType(AngkorLogo));
      await tester.pumpAndSettle();

      _expectNoServerAddressWay(tester);
      expect(find.text('Welcome back'), findsOneWidget); // still just the login screen
    });
  });

  group('profile screen', () {
    for (final entry in {'staff': _staff, 'admin': _admin}.entries) {
      testWidgets('${entry.key}: the Network & Server row is gone, Log out is still there', (tester) async {
        await _show(tester, loggedIn: entry.value, profileOnly: true);

        _expectNoServerAddressWay(tester);
        expect(find.text('Log out'), findsOneWidget);
        // the status line that came with the row (and the address under it) is gone too
        expect(find.text('Connected'), findsNothing);
        expect(find.text('Offline'), findsNothing);
      });
    }

    testWidgets('a guest never had it and still does not', (tester) async {
      await _show(tester, loggedIn: _guest, profileOnly: true);

      _expectNoServerAddressWay(tester);
      expect(find.text('Log out'), findsOneWidget);
    });
  });
}
