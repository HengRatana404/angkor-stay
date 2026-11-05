import 'package:angkor_stay/admin/admin_repository.dart';
import 'package:angkor_stay/auth/auth_provider.dart';
import 'package:angkor_stay/core/api_client.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/main.dart';
import 'package:angkor_stay/models/app_user.dart';
import 'package:angkor_stay/models/dashboard.dart';
import 'package:angkor_stay/models/hotel_settings.dart';
import 'package:angkor_stay/models/staff_member.dart';
import 'package:angkor_stay/screens/admin/settings_screen.dart';
import 'package:angkor_stay/screens/admin/staff_list_screen.dart';
import 'package:angkor_stay/screens/profile_screen.dart';
import 'package:angkor_stay/screens/staff_home_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _admin = AppUser(id: 1, name: 'Hotel Admin', email: 'admin@angkorstay.test', phone: '085000001', role: 'admin');
const _staff = AppUser(id: 2, name: 'Front Desk', email: 'staff@angkorstay.test', phone: '085000002', role: 'staff');

const _startSettings = HotelSettings(
  onlineDiscountPercent: 15,
  checkInTime: '14:00',
  checkOutTime: '12:00',
  staffLoginRestricted: true,
  allowedNetworks: ['127.0.0.1/32', '192.168.0.0/16'],
);

/// An admin server that answers from memory and remembers what it was asked.
class _FakeAdmin extends AdminRepository {
  _FakeAdmin() : super(Dio());

  List<StaffMember> members = [
    const StaffMember(id: 10, name: 'Dara', email: 'dara@example.com', phone: '012111222', isActive: true),
    const StaffMember(id: 11, name: 'Sophea', email: 'sophea@example.com', phone: '012333444', isActive: false),
  ];
  SettingsResult current = const SettingsResult(_startSettings, '192.168.123.6');

  ApiError? error; // thrown by the next change, then cleared
  ApiError? listError;
  ApiError? settingsLoadError;

  final updates = <Map<String, dynamic>>[];
  final created = <Map<String, String>>[];
  HotelSettings? savedSettings;

  void _failIfAsked() {
    final e = error;
    if (e != null) {
      error = null;
      throw e;
    }
  }

  int cleanupRuns = 0;

  @override
  Future<CleanupResult> runCleanup() async {
    cleanupRuns++;
    return const CleanupResult(expiredHolds: 2, noShows: 1, refunded: 21.25, failed: 0);
  }

  @override
  Future<Dashboard> dashboard() async {
    return const Dashboard(
      checkIns: 3,
      checkedInSoFar: 1,
      checkOuts: 2,
      checkedOutSoFar: 2,
      roomsTotal: 15,
      roomsOccupied: 4,
      roomsFree: 10,
      roomsMaintenance: 1,
      moneyToday: 55.5,
      moneyMonth: 410.25,
      moneyMonthOnline: 250.25,
      moneyMonthHotel: 160.0,
      moneyMonthRefunded: 21.25,
      pendingCount: 0,
      pending: [],
      days: [],
    );
  }

  @override
  Future<List<StaffMember>> staff() async {
    if (listError != null) throw listError!;
    return List.of(members);
  }

  @override
  Future<StaffMember> createStaff({
    required String name,
    required String email,
    required String phone,
    required String password,
  }) async {
    _failIfAsked();
    created.add({'name': name, 'email': email, 'phone': phone, 'password': password});
    final m = StaffMember(id: 100 + created.length, name: name, email: email, phone: phone, isActive: true);
    members = [...members, m];
    return m;
  }

  @override
  Future<StaffMember> updateStaff(int id, {String? name, String? phone, bool? isActive, String? password}) async {
    _failIfAsked();
    updates.add({'id': id, 'name': name, 'phone': phone, 'isActive': isActive, 'password': password});
    final old = members.firstWhere((m) => m.id == id);
    final changed = StaffMember(
      id: id,
      name: name ?? old.name,
      email: old.email,
      phone: phone ?? old.phone,
      isActive: isActive ?? old.isActive,
    );
    members = [for (final m in members) m.id == id ? changed : m];
    return changed;
  }

  @override
  Future<SettingsResult> settings() async {
    if (settingsLoadError != null) throw settingsLoadError!;
    return current;
  }

  @override
  Future<SettingsResult> saveSettings(HotelSettings settings) async {
    _failIfAsked();
    savedSettings = settings;
    current = SettingsResult(settings, current.yourIp);
    return current;
  }
}

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

class _FakeAuth extends AuthNotifier {
  final AppUser user;
  _FakeAuth(this.user);

  @override
  Future<AppUser?> build() async => user;
}

class _BrokenAuth extends AuthNotifier {
  @override
  Future<AppUser?> build() async =>
      throw const ApiError('Staff and admin can only use the app on the hotel network.', statusCode: 403);
}

Future<List<Override>> _baseOverrides(_FakeAdmin admin) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
    adminRepositoryProvider.overrideWithValue(admin),
    healthProvider.overrideWith((ref) async => const HealthStatus(true, 'API connected')),
  ];
}

/// The whole app, logged in as [user].
Future<Widget> _appAs(AppUser user, _FakeAdmin admin) async => ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [...await _baseOverrides(admin), authProvider.overrideWith(() => _FakeAuth(user))],
      child: const AngkorStayApp(),
    );

/// One screen on its own.
Future<Widget> _screen(Widget screen, _FakeAdmin admin, [AppUser? user]) async => ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        ...await _baseOverrides(admin),
        if (user != null) authProvider.overrideWith(() => _FakeAuth(user)),
      ],
      child: MaterialApp(home: screen),
    );

String _fieldText(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;

void main() {
  // ------------------------------------------------------------ home pages

  group('home page by role', () {
    testWidgets('the admin sees the staff and settings tiles', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(await _appAs(_admin, _FakeAdmin()));
      await tester.pumpAndSettle();

      expect(find.byType(StaffHomeScreen), findsOneWidget);
      expect(find.text('Hello, Hotel Admin'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget); // the role label
      expect(find.byKey(const Key('tile-staff')), findsOneWidget);
      expect(find.byKey(const Key('tile-settings')), findsOneWidget);
      expect(find.text('Our rooms'), findsNothing);
      expect(find.byKey(const Key('staff-home-scan-fab')), findsNothing);
      expect(find.text('Scan Guest QR'), findsNothing);
      expect(find.text('Front desk'), findsNothing);
    });

    testWidgets('staff do not get the admin tiles', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(await _appAs(_staff, _FakeAdmin()));
      await tester.pumpAndSettle();

      expect(find.byType(StaffHomeScreen), findsOneWidget);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.byKey(const Key('tile-staff')), findsNothing);
      expect(find.byKey(const Key('tile-settings')), findsNothing);
      expect(find.byKey(const Key('tile-cleanup')), findsNothing);
      expect(find.text('Staff accounts'), findsNothing);
      expect(find.text('Hotel settings'), findsNothing);
      expect(find.byKey(const Key('staff-home-scan-fab')), findsOneWidget);
      expect(find.text('Scan guest QR'), findsOneWidget);
      expect(find.text('Front desk'), findsOneWidget);
    });

    testWidgets('staff open their profile: no name or phone to edit, only the password', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(await _appAs(_staff, _FakeAdmin()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('My profile'));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byKey(const Key('staff-name')), findsOneWidget);
      expect(find.text('Name'), findsNothing);
      expect(find.text('Phone'), findsNothing);
      expect(find.text('Save profile'), findsNothing);
      expect(find.text('Current password'), findsOneWidget);
      expect(find.byKey(const Key('staff-forgot-note')), findsOneWidget);
    });

    testWidgets('a guest still edits name and phone in the profile', (tester) async {
      _tallScreen(tester);
      const guest = AppUser(id: 9, name: 'Sok Dara', email: 'dara@example.com', phone: '012345678', role: 'customer');
      await tester.pumpWidget(await _screen(const ProfileScreen(), _FakeAdmin(), guest));
      await tester.pumpAndSettle();

      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Save profile'), findsOneWidget);
      expect(find.byKey(const Key('staff-forgot-note')), findsNothing);
    });

    testWidgets('the admin can run the clean-up and sees what it did', (tester) async {
      _tallScreen(tester);
      final fake = _FakeAdmin();
      await tester.pumpWidget(await _appAs(_admin, fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tile-cleanup')));
      await tester.pumpAndSettle();

      // It asks first. "Not now" runs nothing.
      expect(find.text('Release unpaid holds?'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(fake.cleanupRuns, 0);

      await tester.tap(find.byKey(const Key('tile-cleanup')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-cleanup')));
      await tester.pumpAndSettle();

      expect(fake.cleanupRuns, 1);
      expect(find.textContaining('2 old holds tidied up, 1 no-show marked (\$21.25 refunded).'), findsOneWidget);
    });

    testWidgets('the admin tiles open the staff list and the settings', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(await _appAs(_admin, _FakeAdmin()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tile-staff')));
      await tester.pumpAndSettle();
      expect(find.byType(StaffListScreen), findsOneWidget);
      expect(find.text('Dara'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tile-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('Save settings'), findsOneWidget);
    });

    testWidgets('outside the hotel network the staff member can log out on the phone', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          authProvider.overrideWith(_BrokenAuth.new),
        ],
        child: const AngkorStayApp(),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('hotel network'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Log out on this phone'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome back'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------ staff list

  group('staff list', () {
    testWidgets('shows every staff member and whether the account is on', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(await _screen(const StaffListScreen(), _FakeAdmin()));
      await tester.pumpAndSettle();

      expect(find.text('Dara'), findsOneWidget);
      expect(find.textContaining('dara@example.com'), findsOneWidget);
      expect(find.text('Sophea'), findsOneWidget);
      expect(find.textContaining('Active'), findsOneWidget);
      expect(find.textContaining('Turned off'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('switch-10'))).value, isTrue);
      expect(tester.widget<Switch>(find.byKey(const Key('switch-11'))).value, isFalse);
    });

    testWidgets('an empty list tells the admin what to do', (tester) async {
      final admin = _FakeAdmin()..members = [];
      await tester.pumpWidget(await _screen(const StaffListScreen(), admin));
      await tester.pumpAndSettle();

      expect(find.textContaining('No staff yet'), findsOneWidget);
    });

    testWidgets('turning a switch off tells the server and shows the new state', (tester) async {
      _tallScreen(tester);
      final admin = _FakeAdmin();
      await tester.pumpWidget(await _screen(const StaffListScreen(), admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('switch-10')));
      await tester.pumpAndSettle();

      expect(admin.updates, hasLength(1));
      expect(admin.updates.single['id'], 10);
      expect(admin.updates.single['isActive'], false);
      expect(admin.updates.single['password'], isNull);
      expect(tester.widget<Switch>(find.byKey(const Key('switch-10'))).value, isFalse);
      expect(find.text('Dara is turned off and logged out.'), findsOneWidget);
    });

    testWidgets('turning a switch on says the person can log in again', (tester) async {
      _tallScreen(tester);
      final admin = _FakeAdmin();
      await tester.pumpWidget(await _screen(const StaffListScreen(), admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('switch-11')));
      await tester.pumpAndSettle();

      expect(admin.updates.single['isActive'], true);
      expect(find.text('Sophea can log in again.'), findsOneWidget);
    });

    testWidgets('a failed change shows the message and keeps the old state', (tester) async {
      _tallScreen(tester);
      final admin = _FakeAdmin()..error = const ApiError('Server is busy.', statusCode: 500);
      await tester.pumpWidget(await _screen(const StaffListScreen(), admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('switch-10')));
      await tester.pumpAndSettle();

      expect(find.text('Server is busy.'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const Key('switch-10'))).value, isTrue);
    });

    testWidgets('a list that cannot load shows the error and Retry', (tester) async {
      final admin = _FakeAdmin()
        ..listError = const ApiError('Staff and admin can only use the app on the hotel network.', statusCode: 403);
      await tester.pumpWidget(await _screen(const StaffListScreen(), admin));
      await tester.pumpAndSettle();

      expect(find.textContaining('hotel network'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      admin.listError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Dara'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------ staff form

  group('add and change staff', () {
    testWidgets('an empty form shows what is missing and sends nothing', (tester) async {
      _tallScreen(tester);
      final admin = _FakeAdmin();
      await tester.pumpWidget(await _screen(const StaffListScreen(), admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-staff')));
      await tester.pumpAndSettle();
      expect(find.text('Add staff'), findsWidgets);

      await tester.tap(find.byKey(const Key('staff-save')));
      await tester.pump();

      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('Enter a phone number'), findsOneWidget);
      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(admin.created, isEmpty);
    });

    testWidgets('a new staff member is created and appears in the list', (tester) async {
      _tallScreen(tester);
      final admin = _FakeAdmin();
      await tester.pumpWidget(await _screen(const StaffListScreen(), admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-staff')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('staff-name')), '  Vanna  ');
      await tester.enterText(find.byKey(const Key('staff-email')), 'vanna@example.com');
      await tester.enterText(find.byKey(const Key('staff-phone')), '012999000');
      await tester.enterText(find.byKey(const Key('staff-password')), 'desk-pass-1');
      await tester.tap(find.byKey(const Key('staff-save')));
      await tester.pumpAndSettle();

      expect(admin.created, [
        {'name': 'Vanna', 'email': 'vanna@example.com', 'phone': '012999000', 'password': 'desk-pass-1'},
      ]);
      expect(find.byType(StaffListScreen), findsOneWidget);
      expect(find.text('Vanna'), findsOneWidget);
      expect(find.text('Staff account made. They can log in now.'), findsOneWidget);
    });

    testWidgets('a message from the server shows under the right field and the form stays', (tester) async {
      _tallScreen(tester);
      final admin = _FakeAdmin()
        ..error = const ApiError(
          'The given data was invalid.',
          statusCode: 422,
          fieldErrors: {'email': 'Another account already uses this email.'},
        );
      await tester.pumpWidget(await _screen(const StaffListScreen(), admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add-staff')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('staff-name')), 'Vanna');
      await tester.enterText(find.byKey(const Key('staff-email')), 'dara@example.com');
      await tester.enterText(find.byKey(const Key('staff-phone')), '012999000');
      await tester.enterText(find.byKey(const Key('staff-password')), 'desk-pass-1');
      await tester.tap(find.byKey(const Key('staff-save')));
      await tester.pumpAndSettle();

      expect(find.text('Another account already uses this email.'), findsOneWidget);
      expect(find.byKey(const Key('staff-save')), findsOneWidget);
      expect(admin.created, isEmpty);
    });

    testWidgets('changing a member keeps the email fixed and the password optional', (tester) async {
      _tallScreen(tester);
      final admin = _FakeAdmin();
      await tester.pumpWidget(await _screen(const StaffListScreen(), admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('staff-10')));
      await tester.pumpAndSettle();

      expect(_fieldText(tester, 'staff-name'), 'Dara');
      expect(_fieldText(tester, 'staff-email'), 'dara@example.com');
      expect(tester.widget<TextFormField>(find.byKey(const Key('staff-email'))).enabled, isFalse);

      await tester.enterText(find.byKey(const Key('staff-name')), 'Dara Sok');
      await tester.tap(find.byKey(const Key('staff-save')));
      await tester.pumpAndSettle();

      expect(admin.updates.single['name'], 'Dara Sok');
      expect(admin.updates.single['password'], isNull); // left empty: not sent
      expect(find.text('Dara Sok'), findsOneWidget);
      expect(find.text('Staff account saved.'), findsOneWidget);
    });

    testWidgets('a new password for a member is sent, and a short one is refused', (tester) async {
      _tallScreen(tester);
      final admin = _FakeAdmin();
      await tester.pumpWidget(await _screen(const StaffListScreen(), admin));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('staff-10')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('staff-password')), 'short');
      await tester.tap(find.byKey(const Key('staff-save')));
      await tester.pump();
      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(admin.updates, isEmpty);

      await tester.enterText(find.byKey(const Key('staff-password')), 'brand-new-pass-9');
      await tester.tap(find.byKey(const Key('staff-save')));
      await tester.pumpAndSettle();

      expect(admin.updates.single['password'], 'brand-new-pass-9');
    });
  });

  // -------------------------------------------------------------- settings

  group('hotel settings', () {
    Future<_FakeAdmin> openSettings(WidgetTester tester, {_FakeAdmin? admin}) async {
      _tallScreen(tester);
      final fake = admin ?? _FakeAdmin();
      await tester.pumpWidget(await _screen(const SettingsScreen(), fake));
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('shows the current values', (tester) async {
      await openSettings(tester);

      expect(_fieldText(tester, 'discount'), '15');
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('12:00'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('restricted'))).value, isTrue);
      expect(_fieldText(tester, 'networks'), '127.0.0.1/32\n192.168.0.0/16');
      expect(find.text('This device connects from 192.168.123.6'), findsOneWidget);
    });

    testWidgets('"add this device\'s network" adds the /24 once, not twice', (tester) async {
      await openSettings(tester);

      expect(find.textContaining('192.168.123.0/24'), findsOneWidget); // on the button

      await tester.tap(find.byKey(const Key('add-this-device')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add-this-device')));
      await tester.pump();

      expect(_fieldText(tester, 'networks'), '127.0.0.1/32\n192.168.0.0/16\n192.168.123.0/24');
    });

    testWidgets('a device on this very PC is added as one address', (tester) async {
      final admin = _FakeAdmin()
        ..current = const SettingsResult(
          HotelSettings(
            onlineDiscountPercent: 15,
            checkInTime: '14:00',
            checkOutTime: '12:00',
            staffLoginRestricted: true,
            allowedNetworks: ['10.0.0.0/8'],
          ),
          '127.0.0.1',
        );
      await openSettings(tester, admin: admin);

      await tester.tap(find.byKey(const Key('add-this-device')));
      await tester.pump();

      expect(_fieldText(tester, 'networks'), '10.0.0.0/8\n127.0.0.1/32');
    });

    testWidgets('saving sends every value, with the networks as a clean list', (tester) async {
      final admin = await openSettings(tester);

      await tester.enterText(find.byKey(const Key('discount')), '20');
      await tester.enterText(find.byKey(const Key('networks')), ' 192.168.5.0/24 \n\n10.0.0.7, 10.1.0.0/16\n');
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      final saved = admin.savedSettings!;
      expect(saved.onlineDiscountPercent, 20);
      expect(saved.checkInTime, '14:00');
      expect(saved.checkOutTime, '12:00');
      expect(saved.staffLoginRestricted, isTrue);
      expect(saved.allowedNetworks, ['192.168.5.0/24', '10.0.0.7', '10.1.0.0/16']);
      expect(find.text('Settings saved.'), findsOneWidget);
    });

    testWidgets('a discount outside 0 to 50 is refused before anything is sent', (tester) async {
      final admin = await openSettings(tester);

      for (final bad in ['60', '-1', 'abc', '', '12.5']) {
        await tester.enterText(find.byKey(const Key('discount')), bad);
        await tester.tap(find.byKey(const Key('settings-save')));
        await tester.pump();
        expect(find.text('Enter a whole number from 0 to 50'), findsOneWidget, reason: "'$bad'");
      }

      expect(admin.savedSettings, isNull);

      await tester.enterText(find.byKey(const Key('discount')), '50');
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(admin.savedSettings!.onlineDiscountPercent, 50);
    });

    testWidgets('switching the network rule off hides the list and saves it as off', (tester) async {
      final admin = await openSettings(tester);

      await tester.tap(find.byKey(const Key('restricted')));
      await tester.pump();

      expect(find.byKey(const Key('networks')), findsNothing);
      expect(find.byKey(const Key('add-this-device')), findsNothing);

      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      expect(admin.savedSettings!.staffLoginRestricted, isFalse);
    });

    testWidgets('an empty network list is refused when the rule is on', (tester) async {
      final admin = await openSettings(tester);

      await tester.enterText(find.byKey(const Key('networks')), '  \n ');
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pump();

      expect(find.text('Add at least one network'), findsOneWidget);
      expect(admin.savedSettings, isNull);
    });

    testWidgets('the lock-out warning from the server shows under the networks', (tester) async {
      final admin = _FakeAdmin()
        ..error = const ApiError(
          'The given data was invalid.',
          statusCode: 422,
          fieldErrors: {'allowed_networks': 'These networks do not include the device you are using now, so you would lock yourself out.'},
        );
      await openSettings(tester, admin: admin);

      await tester.enterText(find.byKey(const Key('networks')), '192.168.5.0/24');
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      expect(find.textContaining('lock yourself out'), findsOneWidget);
      expect(admin.savedSettings, isNull);
      expect(find.text('Settings saved.'), findsNothing);

      // And the admin can fix it and save again.
      admin.error = null;
      await tester.tap(find.byKey(const Key('add-this-device')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(admin.savedSettings, isNotNull);
    });

    testWidgets('a general server error shows in a banner', (tester) async {
      final admin = _FakeAdmin()..error = const ApiError('Server is busy.', statusCode: 500);
      await openSettings(tester, admin: admin);

      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      expect(find.text('Server is busy.'), findsOneWidget);
    });

    testWidgets('settings that cannot load show the error and Retry', (tester) async {
      final admin = _FakeAdmin()
        ..settingsLoadError = const ApiError('This account is not allowed to do that.', statusCode: 403, code: 'forbidden_role');
      await openSettings(tester, admin: admin);

      expect(find.text('This account is not allowed to do that.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Save settings'), findsNothing);
    });
  });

  // ---------------------------------------------------------------- models

  group('models', () {
    test('networkForIp', () {
      expect(networkForIp('192.168.123.6'), '192.168.123.0/24');
      expect(networkForIp('10.4.5.200'), '10.4.5.0/24');
      expect(networkForIp('127.0.0.1'), '127.0.0.1/32');
      expect(networkForIp('::1'), '::1/128');
      expect(networkForIp('not-an-ip'), 'not-an-ip/32');
    });

    test('HotelSettings reads and writes the API json', () {
      final json = {
        'online_discount_percent': 15,
        'check_in_time': '14:00',
        'check_out_time': '12:00',
        'staff_login_restricted': true,
        'allowed_networks': ['10.0.0.0/8'],
      };

      final settings = HotelSettings.fromJson(json);

      expect(settings.onlineDiscountPercent, 15);
      expect(settings.allowedNetworks, ['10.0.0.0/8']);
      expect(settings.toJson(), json);
    });

    test('StaffMember reads the API json', () {
      final m = StaffMember.fromJson({
        'id': 3,
        'name': 'Dara',
        'email': 'dara@example.com',
        'phone': null,
        'role': 'staff',
        'is_active': false,
        'created_at': '2026-11-02T10:00:00+07:00',
      });

      expect(m.name, 'Dara');
      expect(m.phone, isNull);
      expect(m.isActive, isFalse);
    });

    test('AppUser knows its role', () {
      expect(_admin.isAdmin, isTrue);
      expect(_admin.isCustomer, isFalse);
      expect(_staff.isStaff, isTrue);
      expect(_staff.isAdmin, isFalse);
    });
  });
}
