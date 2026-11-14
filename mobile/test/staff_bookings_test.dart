import 'package:angkor_stay/auth/auth_provider.dart';
import 'package:angkor_stay/core/api_client.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/main.dart';
import 'package:angkor_stay/models/app_user.dart';
import 'package:angkor_stay/models/staff_booking.dart';
import 'package:angkor_stay/screens/staff/staff_booking_detail_screen.dart';
import 'package:angkor_stay/screens/staff/qr_scanner_screen.dart';
import 'package:angkor_stay/screens/staff/staff_bookings_screen.dart';
import 'package:angkor_stay/screens/staff/take_payment_screen.dart';
import 'package:angkor_stay/staff/staff_booking_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _staffUser = AppUser(
  id: 2,
  name: 'Front Desk',
  email: 'staff@angkorstay.test',
  phone: '085000002',
  role: 'staff',
);
const _adminUser = AppUser(
  id: 1,
  name: 'Hotel Admin',
  email: 'admin@angkorstay.test',
  phone: '085000001',
  role: 'admin',
);
const _frontDesk = Person(2, 'Front Desk');

/// Makes a booking the way the server would describe it.
StaffBooking _booking({
  int id = 1,
  String guest = 'Sok Dara',
  String phone = '012345678',
  String email = 'dara@example.com',
  String room = '101',
  String status = 'pending',
  bool paid = false,
  double total = 30,
  DateTime? checkIn,
  BookingActions? actions,
  List<StaffPayment> payments = const [],
  String? choice = 'hotel',
  int discountPercent = 0,
  double discountAmount = 0,
  Person? checkedInBy,
  Person? checkedOutBy,
}) {
  final inDay = checkIn ?? DateTime.utc(2026, 11, 2);
  return StaffBooking(
    id: id,
    code: 'AS-${id.toString().padLeft(4, '0')}',
    status: status,
    roomNumber: room,
    roomTypeName: 'Single',
    checkIn: inDay,
    checkOut: inDay.add(const Duration(days: 2)),
    nights: 2,
    guestCount: 1,
    pricePerNight: total / 2,
    totalPrice: total,
    paymentChoice: choice,
    discountPercent: discountPercent,
    discountAmount: discountAmount,
    paid: paid,
    holdSecondsLeft: null,
    guest: GuestInfo(id: 50 + id, name: guest, phone: phone, email: email),
    payments: payments,
    checkedInAt: checkedInBy == null ? null : DateTime.utc(2026, 11, 2, 4),
    checkedInBy: checkedInBy,
    checkedOutAt: checkedOutBy == null ? null : DateTime.utc(2026, 11, 3, 4),
    checkedOutBy: checkedOutBy,
    actions:
        actions ??
        const BookingActions(
          canTakePayment: true,
          canCheckIn: false,
          checkInProblem: 'Take payment first.',
          canCheckOut: false,
        ),
  );
}

const _canCheckIn = BookingActions(
  canTakePayment: false,
  canCheckIn: true,
  checkInProblem: null,
  canCheckOut: false,
);
const _canCheckOut = BookingActions(
  canTakePayment: false,
  canCheckIn: false,
  checkInProblem: 'This guest is already checked in.',
  canCheckOut: true,
);
const _nothing = BookingActions(
  canTakePayment: false,
  canCheckIn: false,
  checkInProblem: 'This guest already checked out.',
  canCheckOut: false,
);

/// A server that answers from memory, filters like the real one, and
/// changes the booking like the real one when staff act.
class _FakeStaffBookings extends StaffBookingRepository {
  _FakeStaffBookings(this.items) : super(Dio());

  List<StaffBooking> items;
  ApiError? error; // thrown by the next action, then cleared
  ApiError? listError;
  bool checkInOpensAfterPayment = true;

  final listCalls = <({String search, String? status})>[];
  final payments = <({int id, String method})>[];
  final checkIns = <int>[];
  final checkOuts = <int>[];

  void _failIfAsked() {
    final e = error;
    if (e != null) {
      error = null;
      throw e;
    }
  }

  void _replace(StaffBooking b) =>
      items = [for (final i in items) i.id == b.id ? b : i];

  StaffBooking _find(int id) => items.firstWhere((b) => b.id == id);

  @override
  Future<List<StaffBooking>> list({String search = '', String? status}) async {
    listCalls.add((search: search.trim(), status: status));
    if (listError != null) throw listError!;
    final term = search.trim().toLowerCase();
    return items.where((b) {
      if (status != null && b.status != status) return false;
      if (term.isEmpty) return true;
      return [
        b.code,
        b.guestName,
        b.roomNumber,
        b.guest?.phone ?? '',
        b.guest?.email ?? '',
      ].any((text) => text.toLowerCase().contains(term));
    }).toList();
  }

  @override
  Future<StaffBooking> get(int id) async => _find(id);

  @override
  Future<StaffBooking> takePayment(int id, String method) async {
    _failIfAsked();
    payments.add((id: id, method: method));
    final old = _find(id);
    final paid = _booking(
      id: id,
      guest: old.guestName,
      room: old.roomNumber,
      status: 'confirmed',
      paid: true,
      total: old.totalPrice,
      checkIn: old.checkIn,
      actions: checkInOpensAfterPayment
          ? _canCheckIn
          : const BookingActions(
              canTakePayment: false,
              canCheckIn: false,
              checkInProblem: 'Check-in opens on Mon 9 Nov.',
              canCheckOut: false,
            ),
      payments: [
        StaffPayment(
          id: 1,
          amount: old.totalPrice,
          method: method,
          status: 'paid',
          receivedBy: _frontDesk,
          paidAt: DateTime.utc(2026, 11, 2, 3),
        ),
      ],
    );
    _replace(paid);
    return paid;
  }

  @override
  Future<StaffBooking> checkIn(int id) async {
    _failIfAsked();
    checkIns.add(id);
    final old = _find(id);
    final next = _booking(
      id: id,
      guest: old.guestName,
      room: old.roomNumber,
      status: 'checked_in',
      paid: true,
      total: old.totalPrice,
      checkIn: old.checkIn,
      actions: _canCheckOut,
      payments: old.payments,
      checkedInBy: _frontDesk,
    );
    _replace(next);
    return next;
  }

  @override
  Future<StaffBooking> checkOut(int id) async {
    _failIfAsked();
    checkOuts.add(id);
    final old = _find(id);
    final next = _booking(
      id: id,
      guest: old.guestName,
      room: old.roomNumber,
      status: 'checked_out',
      paid: true,
      total: old.totalPrice,
      checkIn: old.checkIn,
      actions: _nothing,
      payments: old.payments,
      checkedInBy: _frontDesk,
      checkedOutBy: _frontDesk,
    );
    _replace(next);
    return next;
  }
}

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<List<Override>> _overrides(_FakeStaffBookings fake) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
    staffBookingRepositoryProvider.overrideWithValue(fake),
    healthProvider.overrideWith(
      (ref) async => const HealthStatus(true, 'API connected'),
    ),
  ];
}

Future<Widget> _screen(Widget screen, _FakeStaffBookings fake) async =>
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: await _overrides(fake),
      child: MaterialApp(home: screen),
    );

class _FakeAuth extends AuthNotifier {
  final AppUser user;
  _FakeAuth(this.user);

  @override
  Future<AppUser?> build() async => user;
}

Future<Widget> _appAs(AppUser user, _FakeStaffBookings fake) async =>
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        ...await _overrides(fake),
        authProvider.overrideWith(() => _FakeAuth(user)),
      ],
      child: const AngkorStayApp(),
    );

void main() {
  group('home page', () {
    testWidgets('staff and admin both get the Bookings tile', (tester) async {
      for (final user in [_staffUser, _adminUser]) {
        _tallScreen(tester);
        await tester.pumpWidget(
          await _appAs(user, _FakeStaffBookings([_booking()])),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('tile-bookings')),
          findsOneWidget,
          reason: user.role,
        );

        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('staff still get no admin tiles', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(await _appAs(_staffUser, _FakeStaffBookings([])));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tile-staff')), findsNothing);
      expect(find.byKey(const Key('tile-settings')), findsNothing);
    });

    testWidgets('the Bookings tile opens the list', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(
        await _appAs(_staffUser, _FakeStaffBookings([_booking()])),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tile-bookings')));
      await tester.pumpAndSettle();

      expect(find.byType(StaffBookingsScreen), findsOneWidget);
      expect(find.text('AS-0001 · Room 101'), findsOneWidget);
    });
  });

  group('check in and out are by QR scan only', () {
    testWidgets(
      'the list has no check in or check out button, whatever the booking can do',
      (tester) async {
        _tallScreen(tester);
        final fake = _FakeStaffBookings([
          _booking(
            id: 1,
            status: 'confirmed',
            paid: true,
            actions: _canCheckIn,
          ),
          _booking(
            id: 2,
            status: 'checked_in',
            paid: true,
            actions: _canCheckOut,
          ),
        ]);
        await tester.pumpWidget(
          await _screen(const StaffBookingsScreen(), fake),
        );
        await tester.pumpAndSettle();

        for (final id in [1, 2]) {
          expect(find.byKey(Key('quick-check-in-$id')), findsNothing);
          expect(find.byKey(Key('quick-check-out-$id')), findsNothing);
        }
        expect(find.widgetWithText(FilledButton, 'Check in'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Check out'), findsNothing);
        expect(fake.checkIns, isEmpty);
        expect(fake.checkOuts, isEmpty);
      },
    );
  });

  group('booking list', () {
    testWidgets(
      'shows the code, room, guest, dates, status, price and a Paid chip',
      (tester) async {
        _tallScreen(tester);
        final fake = _FakeStaffBookings([
          _booking(id: 1, guest: 'Sok Dara', room: '101'),
          _booking(
            id: 2,
            guest: 'Chan Vanna',
            room: '202',
            status: 'confirmed',
            paid: true,
            actions: _canCheckIn,
          ),
        ]);
        await tester.pumpWidget(
          await _screen(const StaffBookingsScreen(), fake),
        );
        await tester.pumpAndSettle();

        expect(find.text('AS-0001 · Room 101'), findsOneWidget);
        expect(find.text('Sok Dara'), findsOneWidget);
        expect(find.text('Mon 2 Nov → Wed 4 Nov'), findsNWidgets(2));
        expect(
          find.text('Waiting for payment'),
          findsWidgets,
        ); // the chip (the filter chip has the same words)
        expect(find.text('AS-0002 · Room 202'), findsOneWidget);
        expect(find.text('Paid'), findsOneWidget);
        expect(find.text('\$30'), findsNWidgets(2));
      },
    );

    testWidgets(
      'tapping scan opens the QR scanner screen and demo scan works',
      (tester) async {
        _tallScreen(tester);
        final fake = _FakeStaffBookings([
          _booking(id: 6, guest: 'Test Guest', room: '202'),
        ]);
        await tester.pumpWidget(
          await _screen(const StaffBookingsScreen(), fake),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('open-camera-scanner')), findsOneWidget);
        await tester.tap(find.byKey(const Key('open-camera-scanner')));
        await tester.pumpAndSettle();

        expect(find.text('Scan guest QR'), findsOneWidget);
        expect(find.byKey(const Key('demo-scan-button')), findsOneWidget);

        await tester.tap(find.byKey(const Key('demo-scan-button')));
        await tester.pumpAndSettle();

        // The scan shows who it is, in a sheet, with the action for the chosen mode.
        expect(find.byKey(const Key('scan-guest')), findsOneWidget);
        expect(find.text('Test Guest'), findsOneWidget);
      },
    );

    testWidgets('an empty list says so', (tester) async {
      await tester.pumpWidget(
        await _screen(const StaffBookingsScreen(), _FakeStaffBookings([])),
      );
      await tester.pumpAndSettle();

      expect(find.text('No bookings found.'), findsOneWidget);
    });

    testWidgets('a list that cannot load shows the error and Retry', (
      tester,
    ) async {
      final fake = _FakeStaffBookings([_booking()])
        ..listError = const ApiError(
          'Staff and admin can only use the app on the hotel network.',
          statusCode: 403,
        );
      await tester.pumpWidget(await _screen(const StaffBookingsScreen(), fake));
      await tester.pumpAndSettle();

      expect(find.textContaining('hotel network'), findsOneWidget);

      fake.listError = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('AS-0001 · Room 101'), findsOneWidget);
    });

    testWidgets('searching asks the server once, after the typing stops', (
      tester,
    ) async {
      _tallScreen(tester);
      final fake = _FakeStaffBookings([
        _booking(id: 1, guest: 'Sok Dara', room: '101'),
        _booking(
          id: 2,
          guest: 'Chan Vanna',
          room: '202',
          phone: '099888777',
          email: 'vanna@example.org',
        ),
      ]);
      await tester.pumpWidget(await _screen(const StaffBookingsScreen(), fake));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('booking-search')), 'da');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byKey(const Key('booking-search')), 'dara');
      await tester.pump(const Duration(milliseconds: 100));
      expect(fake.listCalls.map((c) => c.search).toList(), [
        '',
      ]); // nothing asked yet

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(fake.listCalls.map((c) => c.search).toList(), ['', 'dara']);
      expect(find.text('AS-0001 · Room 101'), findsOneWidget);
      expect(find.text('AS-0002 · Room 202'), findsNothing);
    });

    testWidgets('a booking code finds the booking', (tester) async {
      _tallScreen(tester);
      final fake = _FakeStaffBookings([
        _booking(id: 1),
        _booking(id: 12, guest: 'Chan Vanna', room: '202'),
      ]);
      await tester.pumpWidget(await _screen(const StaffBookingsScreen(), fake));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('booking-search')),
        'AS-0012',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('AS-0012 · Room 202'), findsOneWidget);
      expect(find.text('AS-0001 · Room 101'), findsNothing);
    });

    testWidgets(
      'the clear button empties the search and shows everything again',
      (tester) async {
        _tallScreen(tester);
        final fake = _FakeStaffBookings([
          _booking(id: 1),
          _booking(id: 2, guest: 'Chan Vanna', room: '202'),
        ]);
        await tester.pumpWidget(
          await _screen(const StaffBookingsScreen(), fake),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('booking-search')),
          'vanna',
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        expect(find.text('AS-0001 · Room 101'), findsNothing);

        await tester.tap(find.byIcon(Icons.clear));
        await tester.pumpAndSettle();

        expect(find.text('AS-0001 · Room 101'), findsOneWidget);
        expect(find.text('AS-0002 · Room 202'), findsOneWidget);
        expect(fake.listCalls.last.search, '');
      },
    );

    testWidgets('a status chip filters, and All shows everything again', (
      tester,
    ) async {
      _tallScreen(tester);
      final fake = _FakeStaffBookings([
        _booking(id: 1, status: 'pending'),
        _booking(
          id: 2,
          guest: 'Chan Vanna',
          room: '202',
          status: 'confirmed',
          paid: true,
          actions: _canCheckIn,
        ),
      ]);
      await tester.pumpWidget(await _screen(const StaffBookingsScreen(), fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter-confirmed')));
      await tester.pumpAndSettle();

      expect(fake.listCalls.last.status, 'confirmed');
      expect(find.text('AS-0002 · Room 202'), findsOneWidget);
      expect(find.text('AS-0001 · Room 101'), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('filter-confirmed')))
            .selected,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('filter-all')));
      await tester.pumpAndSettle();

      expect(fake.listCalls.last.status, isNull);
      expect(find.text('AS-0001 · Room 101'), findsOneWidget);
      expect(
        tester.widget<ChoiceChip>(find.byKey(const Key('filter-all'))).selected,
        isTrue,
      );
    });
  });

  group('booking detail', () {
    Future<_FakeStaffBookings> openDetail(
      WidgetTester tester,
      StaffBooking booking, {
      _FakeStaffBookings? fake,
    }) async {
      _tallScreen(tester);
      final server = fake ?? _FakeStaffBookings([booking]);
      await tester.pumpWidget(
        await _screen(const StaffBookingsScreen(), server),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('booking-${booking.id}')));
      await tester.pumpAndSettle();
      return server;
    }

    testWidgets(
      'an unpaid booking shows the guest, the amount to collect and the payment button only',
      (tester) async {
        await openDetail(tester, _booking());

        expect(find.byType(StaffBookingDetailScreen), findsOneWidget);
        expect(find.byKey(const Key('detail-code')), findsOneWidget);
        expect(find.text('Sok Dara'), findsOneWidget);
        expect(find.text('012345678'), findsOneWidget);
        expect(find.text('dara@example.com'), findsOneWidget);
        expect(find.text('Single · Room 101'), findsOneWidget);
        expect(find.text('Not paid yet. \$30 to collect.'), findsOneWidget);

        expect(find.byKey(const Key('take-payment')), findsOneWidget);
        expect(find.text('Take payment (\$30)'), findsOneWidget);
        expect(find.byKey(const Key('scan-to-check-in')), findsNothing);
        expect(find.byKey(const Key('scan-to-check-out')), findsNothing);
      },
    );

    testWidgets(
      'taking payment: choose a method, confirm, and the booking shows who received the money',
      (tester) async {
        final fake = await openDetail(tester, _booking());

        await tester.tap(find.byKey(const Key('take-payment')));
        await tester.pumpAndSettle();

        expect(find.byType(TakePaymentScreen), findsOneWidget);
        expect(find.byKey(const Key('amount')), findsOneWidget);
        expect(find.text('\$30'), findsWidgets);
        expect(find.textContaining('No discount at the hotel'), findsOneWidget);
        expect(
          find.text('Guest paid \$30 by Cash'),
          findsOneWidget,
        ); // cash is the first choice
        expect(find.byKey(const Key('qr')), findsNothing);

        await tester.tap(find.text('KHQR'));
        await tester.pump();
        expect(find.byKey(const Key('qr')), findsOneWidget);
        expect(find.text('Guest paid \$30 by KHQR'), findsOneWidget);

        await tester.tap(find.text('Card'));
        await tester.pump();
        expect(find.byKey(const Key('qr')), findsNothing);
        expect(find.text('Guest paid \$30 by Card'), findsOneWidget);

        await tester.tap(find.text('KHQR'));
        await tester.pump();
        await tester.tap(find.byKey(const Key('confirm-payment')));
        await tester.pumpAndSettle();

        expect(fake.payments, [(id: 1, method: 'khqr')]);
        expect(find.byType(TakePaymentScreen), findsNothing);
        expect(find.text('Payment of \$30 saved (KHQR).'), findsOneWidget);
        expect(
          find.textContaining('Paid \$30 by KHQR, received by Front Desk'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('take-payment')), findsNothing);
        expect(
          find.byKey(const Key('scan-to-check-in')),
          findsOneWidget,
        ); // now they can check in
      },
    );

    testWidgets(
      'a payment the server refuses shows its message and keeps the screen',
      (tester) async {
        final fake = _FakeStaffBookings([_booking()])
          ..error = const ApiError(
            'This booking is already paid.',
            statusCode: 409,
            code: 'already_paid',
          );
        await openDetail(tester, _booking(), fake: fake);

        await tester.tap(find.byKey(const Key('take-payment')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-payment')));
        await tester.pumpAndSettle();

        expect(find.text('This booking is already paid.'), findsOneWidget);
        expect(find.byType(TakePaymentScreen), findsOneWidget);
        expect(fake.payments, isEmpty);
      },
    );

    testWidgets(
      'a paid booking before its check-in date says when check-in opens',
      (tester) async {
        await openDetail(
          tester,
          _booking(
            status: 'confirmed',
            paid: true,
            checkIn: DateTime.utc(2026, 11, 9),
            actions: const BookingActions(
              canTakePayment: false,
              canCheckIn: false,
              checkInProblem: 'Check-in opens on Mon 9 Nov.',
              canCheckOut: false,
            ),
          ),
        );

        expect(find.byKey(const Key('scan-to-check-in')), findsNothing);
        expect(find.byKey(const Key('check-in-problem')), findsOneWidget);
        expect(find.text('Check-in opens on Mon 9 Nov.'), findsOneWidget);
      },
    );

    testWidgets(
      'a paid booking offers Scan guest QR to check in, never a plain Check in button',
      (tester) async {
        final fake = await openDetail(
          tester,
          _booking(status: 'confirmed', paid: true, actions: _canCheckIn),
        );

        expect(find.byKey(const Key('scan-to-check-in')), findsOneWidget);
        expect(find.text('Scan guest QR to check in'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Check in'), findsNothing);

        await tester.tap(find.byKey(const Key('scan-to-check-in')));
        await tester.pumpAndSettle();

        // The camera screen opens in check-in mode. Nothing is checked in by the tap itself.
        expect(find.byType(QrScannerScreen), findsOneWidget);
        expect(find.text('Scan the guest QR to check in'), findsOneWidget);
        expect(fake.checkIns, isEmpty);
      },
    );

    testWidgets(
      'a checked-in guest offers Scan guest QR to check out, in check-out mode',
      (tester) async {
        final fake = await openDetail(
          tester,
          _booking(
            status: 'checked_in',
            paid: true,
            actions: _canCheckOut,
            checkedInBy: _frontDesk,
          ),
        );

        expect(find.byKey(const Key('scan-to-check-in')), findsNothing);
        expect(find.byKey(const Key('scan-to-check-out')), findsOneWidget);
        expect(find.text('Scan guest QR to check out'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Check out'), findsNothing);
        expect(find.textContaining('Checked in by Front Desk'), findsOneWidget);

        await tester.tap(find.byKey(const Key('scan-to-check-out')));
        await tester.pumpAndSettle();

        expect(find.byType(QrScannerScreen), findsOneWidget);
        expect(find.text('Scan the guest QR to check out'), findsOneWidget);
        expect(fake.checkOuts, isEmpty);
      },
    );

    testWidgets('a finished stay has no buttons at all', (tester) async {
      await openDetail(
        tester,
        _booking(
          status: 'checked_out',
          paid: true,
          actions: _nothing,
          checkedInBy: _frontDesk,
          checkedOutBy: _frontDesk,
        ),
      );

      expect(find.byKey(const Key('take-payment')), findsNothing);
      expect(find.byKey(const Key('scan-to-check-in')), findsNothing);
      expect(find.byKey(const Key('scan-to-check-out')), findsNothing);
      expect(find.textContaining('Checked in by Front Desk'), findsOneWidget);
      expect(find.textContaining('Checked out by Front Desk'), findsOneWidget);
    });

    testWidgets(
      'a booking paid online shows the discount and the payment, with nobody "receiving" it',
      (tester) async {
        await openDetail(
          tester,
          _booking(
            status: 'confirmed',
            paid: true,
            choice: 'online',
            discountPercent: 15,
            discountAmount: 4.5,
            actions: _canCheckIn,
            payments: [
              StaffPayment(
                id: 1,
                amount: 25.5,
                method: 'online',
                status: 'paid',
                receivedBy: null,
                paidAt: DateTime.utc(2026, 11, 2, 3),
              ),
            ],
          ),
        );

        expect(find.text('Online discount 15%: -\$4.50'), findsOneWidget);
        expect(find.textContaining('Paid \$25.50 by Online'), findsOneWidget);
        expect(find.textContaining('received by'), findsNothing);
        expect(find.byKey(const Key('paying-online-note')), findsNothing);
        expect(find.byKey(const Key('take-payment')), findsNothing);
      },
    );

    testWidgets(
      'a guest who started paying online is flagged before staff take the payment',
      (tester) async {
        await openDetail(
          tester,
          _booking(choice: 'online', discountPercent: 15, discountAmount: 4.5),
        );

        expect(find.byKey(const Key('paying-online-note')), findsOneWidget);
        expect(find.textContaining('started paying online'), findsOneWidget);
        expect(find.textContaining('full \$30'), findsOneWidget);
        expect(find.byKey(const Key('take-payment')), findsOneWidget);
      },
    );

    testWidgets(
      'a guest who chose the hotel gets no online note and no discount line',
      (tester) async {
        await openDetail(tester, _booking());

        expect(find.byKey(const Key('paying-online-note')), findsNothing);
        expect(find.byKey(const Key('discount-line')), findsNothing);
      },
    );

    test(
      'StaffBooking reads the discount and knows when a guest is paying online',
      () {
        final base = _booking(
          choice: 'online',
          discountPercent: 15,
          discountAmount: 4.5,
        );

        expect(base.discountPercent, 15);
        expect(base.discountAmount, 4.5);
        expect(base.isPayingOnline, isTrue);

        expect(
          _booking(
            choice: 'online',
            status: 'confirmed',
            paid: true,
          ).isPayingOnline,
          isFalse,
        );
        expect(_booking(choice: 'hotel').isPayingOnline, isFalse);
        expect(_booking(choice: null).isPayingOnline, isFalse);
      },
    );
  });
}
