import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:angkor_stay/auth/auth_provider.dart';
import 'package:angkor_stay/core/api_client.dart';
import 'package:angkor_stay/main.dart';
import 'package:angkor_stay/booking/booking_repository.dart';
import 'package:angkor_stay/booking/stay_provider.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/core/format.dart';
import 'package:angkor_stay/core/public_settings_provider.dart';
import 'package:angkor_stay/models/public_settings.dart';
import 'package:angkor_stay/models/app_user.dart';
import 'package:angkor_stay/models/booking.dart';
import 'package:angkor_stay/screens/booking_hold_screen.dart';
import 'package:angkor_stay/models/room_type.dart';
import 'package:angkor_stay/rooms/room_types_provider.dart';
import 'package:angkor_stay/screens/room_type_detail_screen.dart';
import 'package:angkor_stay/screens/home_screen.dart';
import 'package:angkor_stay/screens/new_password_screen.dart';
import 'package:angkor_stay/screens/reset_code_screen.dart';

const _sampleRooms = [
  RoomType(
    id: 1,
    name: 'Single',
    description: 'A bright, quiet room with one comfortable bed.',
    pricePerNight: 15,
    capacity: 2,
    totalRooms: 5,
    availableRooms: 5,
    coverImage: 'https://example.com/single.jpg',
    images: ['https://example.com/single.jpg', 'https://example.com/single2.jpg'],
  ),
  RoomType(
    id: 2,
    name: 'Double',
    description: 'A roomy room for families.',
    pricePerNight: 25,
    capacity: 4,
    totalRooms: 5,
    availableRooms: 0,
    coverImage: null,
    images: [],
  ),
  RoomType(
    id: 3,
    name: 'VIP',
    description: 'Our best suite.',
    pricePerNight: 50,
    capacity: 6,
    totalRooms: 5,
    availableRooms: 1,
    coverImage: null,
    images: [],
  ),
];

final _sampleBooking = Booking(
  id: 7,
  status: 'pending',
  roomNumber: '101',
  roomTypeName: 'Single',
  coverImage: null,
  checkIn: DateTime.utc(2026, 11, 10),
  checkOut: DateTime.utc(2026, 11, 12),
  nights: 2,
  guests: 1,
  pricePerNight: 15,
  totalPrice: 30,
  holdSecondsLeft: 300,
);

/// A booking server that answers from memory.
class _FakeBookings extends BookingRepository {
  _FakeBookings() : super(Dio());

  ApiError? error;
  final created = <Stay>[];
  final released = <int>[];

  @override
  Future<Booking> create({required int roomTypeId, required Stay stay}) async {
    if (error != null) throw error!;
    created.add(stay);
    return _sampleBooking;
  }

  @override
  Future<void> release(int bookingId) async => released.add(bookingId);
}

/// A tall screen, so every card is on screen without scrolling.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<Widget> _app({AppUser? loggedIn, BookingRepository? bookings}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      roomTypesProvider.overrideWith((ref) async => _sampleRooms),
      publicSettingsProvider.overrideWith(
        (ref) async => const PublicSettings(onlineDiscountPercent: 15, checkInTime: '14:00', checkOutTime: '12:00'),
      ),
      if (bookings != null) bookingRepositoryProvider.overrideWithValue(bookings),
      if (loggedIn != null) authProvider.overrideWith(() => _FakeAuth(loggedIn)),
    ],
    child: const AngkorStayApp(),
  );
}

class _FakeAuth extends AuthNotifier {
  final AppUser? user;
  _FakeAuth(this.user);

  @override
  Future<AppUser?> build() async => user;
}

void main() {
  testWidgets('logged out user sees the login screen', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Angkor Stay'), findsOneWidget);
  });

  testWidgets('login form asks for email and password', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log in'));
    await tester.pump();

    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('register form checks passwords match', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    await tester.tap(find.text("Don't have an account? Register"));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret1234');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'different1');
    await tester.ensureVisible(find.text('Register'));
    await tester.tap(find.text('Register'));
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('forgot password link opens the email screen and checks the email', (tester) async {
    await tester.pumpWidget(await _app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Send code'), findsOneWidget);

    await tester.tap(find.text('Send code'));
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);
  });

  testWidgets('reset code screen needs a full 6-digit code', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        ],
        child: const MaterialApp(home: ResetCodeScreen(email: 'dara@example.com')),
      ),
    );

    await tester.enterText(find.byType(TextField), '123');
    await tester.tap(find.text('Verify code'));
    await tester.pump();

    expect(find.text('Enter the 6-digit code from your email.'), findsOneWidget);

    // Stop the resend countdown timer before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new password screen checks length and matching', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        ],
        child: const MaterialApp(
          home: NewPasswordScreen(email: 'dara@example.com', code: '123456'),
        ),
      ),
    );

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'short');
    await tester.tap(find.text('Change password'));
    await tester.pump();
    expect(find.text('At least 8 characters'), findsWidgets);

    await tester.enterText(find.widgetWithText(TextFormField, 'New password'), 'long-enough-1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm new password'), 'different-2');
    await tester.tap(find.text('Change password'));
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('logged in user sees the home screen with their role', (tester) async {
    const user = AppUser(
      id: 1,
      name: 'Sok Dara',
      email: 'dara@example.com',
      phone: '012345678',
      role: 'customer',
    );

    await tester.pumpWidget(await _app(loggedIn: user));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // the opening splash plays first
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Hello, Sok Dara'), findsOneWidget);
    expect(find.text('Customer'), findsNothing); // guests do not need a role badge

    // Let the health request finish (it fails in tests, that is fine).
    await tester.pumpAndSettle(const Duration(seconds: 7));
  });

  const customer = AppUser(
    id: 1,
    name: 'Sok Dara',
    email: 'dara@example.com',
    phone: '012345678',
    role: 'customer',
  );

  testWidgets('home lists the room types with price and guests', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(await _app(loggedIn: customer));
    await tester.pumpAndSettle(const Duration(seconds: 7));

    expect(find.text('Our rooms'), findsOneWidget);
    expect(find.text('Single'), findsOneWidget);
    expect(find.text('\$15'), findsOneWidget);
    expect(find.text('Up to 2 guests'), findsOneWidget);
    expect(find.text('VIP'), findsOneWidget);
    expect(find.text('\$50'), findsOneWidget);
    expect(find.text('Up to 6 guests'), findsOneWidget);
  });

  testWidgets('tapping a room opens its details with description and rooms', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(await _app(loggedIn: customer));
    await tester.pumpAndSettle(const Duration(seconds: 7));

    await tester.tap(find.text('Single'));
    await tester.pumpAndSettle();

    expect(find.byType(RoomTypeDetailScreen), findsOneWidget);
    expect(find.text('Single room'), findsOneWidget);
    expect(find.text('A bright, quiet room with one comfortable bed.'), findsOneWidget);
    expect(find.text('5 rooms'), findsOneWidget);
    expect(find.text('Up to 2 guests'), findsOneWidget);
  });

  testWidgets('room list shows an error and Retry when the server fails', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        retry: (retryCount, error) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
          authProvider.overrideWith(() => _FakeAuth(customer)),
          roomTypesProvider.overrideWith((ref) async => throw Exception('server is down')),
        ],
        child: const AngkorStayApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 7));

    expect(find.textContaining('server is down'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  // ------------------------------------------------------------ ticket 05

  testWidgets('home shows a chip with rooms left on each card, tapping opens booking screen with stay card', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(await _app(loggedIn: customer));
    await tester.pumpAndSettle(const Duration(seconds: 7));

    expect(find.text('5 rooms left'), findsOneWidget); // Single
    expect(find.text('No room left'), findsOneWidget); // Double
    expect(find.text('Only 1 left'), findsOneWidget); // VIP

    await tester.tap(find.text('Single'));
    await tester.pumpAndSettle();

    expect(find.text('Your stay'), findsOneWidget);
    expect(find.text('1 night'), findsOneWidget);
  });

  testWidgets('changing guests updates the stay and warns when a room is too small', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(await _app(loggedIn: customer));
    await tester.pumpAndSettle(const Duration(seconds: 7));

    await tester.tap(find.text('Single'));
    await tester.pumpAndSettle();

    expect(find.textContaining('fits up to 2 guests'), findsNothing);

    await tester.tap(find.byKey(const Key('guests-plus')));
    await tester.tap(find.byKey(const Key('guests-plus')));
    await tester.pump();

    expect(find.text('3'), findsOneWidget);
    // Single holds 2 guests, so with 3 guests it cannot be booked.
    expect(find.textContaining('fits up to 2 guests'), findsWidgets);
  });

  testWidgets('guests cannot go below 1 or above 6', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(await _app(loggedIn: customer));
    await tester.pumpAndSettle(const Duration(seconds: 7));

    await tester.tap(find.text('Single'));
    await tester.pumpAndSettle();

    final minus = tester.widget<IconButton>(find.byKey(const Key('guests-minus')));
    expect(minus.onPressed, isNull);

    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byKey(const Key('guests-plus')));
      await tester.pump();
    }
    expect(find.text('6'), findsOneWidget);
    final plus = tester.widget<IconButton>(find.byKey(const Key('guests-plus')));
    expect(plus.onPressed, isNull);
  });

  testWidgets('a room type with no room left cannot be booked', (tester) async {
    _tallScreen(tester);
    final bookings = _FakeBookings();
    await tester.pumpWidget(await _app(loggedIn: customer, bookings: bookings));
    await tester.pumpAndSettle(const Duration(seconds: 7));

    await tester.tap(find.text('Double'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byKey(const Key('book-button')));
    expect(button.onPressed, isNull);
    expect(find.textContaining('No Double room left'), findsOneWidget);
    expect(bookings.created, isEmpty);
  });

  testWidgets('a room that is too small for the guests cannot be booked', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(await _app(loggedIn: customer));
    await tester.pumpAndSettle(const Duration(seconds: 7));

    await tester.tap(find.text('Single'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('guests-plus')));
    await tester.tap(find.byKey(const Key('guests-plus')));
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byKey(const Key('book-button')));
    expect(button.onPressed, isNull);
    expect(find.textContaining('fits up to 2 guests'), findsOneWidget);
  });

  testWidgets('booking sends the stay and shows the held room with a countdown', (tester) async {
    _tallScreen(tester);
    final bookings = _FakeBookings();
    await tester.pumpWidget(await _app(loggedIn: customer, bookings: bookings));
    await tester.pumpAndSettle(const Duration(seconds: 7));

    await tester.tap(find.text('Single'));
    await tester.pumpAndSettle();
    expect(find.text('Book for \$15'), findsOneWidget); // 1 night x $15

    await tester.tap(find.byKey(const Key('book-button')));
    await tester.pumpAndSettle();

    expect(bookings.created, hasLength(1));
    expect(bookings.created.single.guests, 1);
    expect(find.byType(BookingHoldScreen), findsOneWidget);
    expect(find.text('Single · Room 101'), findsOneWidget);
    expect(find.text('5:00'), findsOneWidget);
    expect(find.text('\$30'), findsOneWidget); // saved total price
    expect(find.text('\$15 × 2 nights'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // stop the countdown timer
  });

  testWidgets('"No room left" from the server shows as a message and nothing is held', (tester) async {
    _tallScreen(tester);
    final bookings = _FakeBookings()
      ..error = const ApiError('No Single room left for these dates.', statusCode: 409, code: 'no_room_left');
    await tester.pumpWidget(await _app(loggedIn: customer, bookings: bookings));
    await tester.pumpAndSettle(const Duration(seconds: 7));

    await tester.tap(find.text('Single'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-button')));
    await tester.pumpAndSettle();

    expect(find.text('No Single room left for these dates.'), findsOneWidget);
    expect(find.byType(BookingHoldScreen), findsNothing);
  });

  testWidgets('the hold countdown goes down every second and then says the hold ran out', (tester) async {
    _tallScreen(tester);
    final bookings = _FakeBookings();
    await tester.pumpWidget(await _app(loggedIn: customer, bookings: bookings));
    await tester.pumpAndSettle(const Duration(seconds: 7));
    await tester.tap(find.text('Single'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-button')));
    await tester.pumpAndSettle();

    expect(find.text('5:00'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('4:59'), findsOneWidget);

    await tester.pump(const Duration(seconds: 60));
    expect(find.text('3:59'), findsOneWidget);

    await tester.pump(const Duration(seconds: 239));
    expect(find.text('Hold ran out'), findsOneWidget);
    expect(find.text('Back to rooms'), findsOneWidget);
    expect(find.text('Release this room'), findsNothing);

    await tester.tap(find.text('Back to rooms'));
    await tester.pumpAndSettle();
    expect(find.byType(BookingHoldScreen), findsNothing);
    expect(find.text('Our rooms'), findsOneWidget);
  });

  testWidgets('releasing the room tells the server and goes back to the list', (tester) async {
    _tallScreen(tester);
    final bookings = _FakeBookings();
    await tester.pumpWidget(await _app(loggedIn: customer, bookings: bookings));
    await tester.pumpAndSettle(const Duration(seconds: 7));
    await tester.tap(find.text('Single'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Release this room'));
    await tester.pumpAndSettle();

    expect(bookings.released, [7]);
    expect(find.byType(BookingHoldScreen), findsNothing);
    expect(find.text('The room was released.'), findsOneWidget);
  });

  test('stay: one night and one guest by default', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final stay = container.read(stayProvider);
    expect(stay.nights, 1);
    expect(stay.guests, 1);
    expect(stay.checkOut.difference(stay.checkIn).inDays, 1);
  });

  test('stay: picking the same day counts as one night', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final error = container
        .read(stayProvider.notifier)
        .setDates(DateTime(2026, 11, 20), DateTime(2026, 11, 20));

    expect(error, isNull);
    expect(container.read(stayProvider).nights, 1);
    expect(container.read(stayProvider).checkInText, '2026-11-20');
    expect(container.read(stayProvider).checkOutText, '2026-11-21');
  });

  test('stay: 30 nights is allowed, 31 is refused and changes nothing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(stayProvider.notifier);

    expect(notifier.setDates(DateTime(2026, 11, 1), DateTime(2026, 12, 1)), isNull);
    expect(container.read(stayProvider).nights, 30);

    final error = notifier.setDates(DateTime(2026, 11, 1), DateTime(2026, 12, 2));
    expect(error, 'You can stay up to 30 nights in one booking.');
    expect(container.read(stayProvider).nights, 30);
  });

  test('stay: guests stay between 1 and 6', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(stayProvider.notifier);

    notifier.setGuests(0);
    expect(container.read(stayProvider).guests, 1);
    notifier.setGuests(99);
    expect(container.read(stayProvider).guests, 6);
    notifier.setGuests(4);
    expect(container.read(stayProvider).guests, 4);
  });

  test('format helpers', () {
    expect(formatCountdown(300), '5:00');
    expect(formatCountdown(275), '4:35');
    expect(formatCountdown(9), '0:09');
    expect(formatCountdown(0), '0:00');
    expect(formatCountdown(-5), '0:00');
    expect(nightsText(1), '1 night');
    expect(nightsText(3), '3 nights');
    expect(formatMoney(75), '\$75');
    expect(formatMoney(12.5), '\$12.50');
    expect(isoDate(DateTime.utc(2026, 3, 5)), '2026-03-05');
    expect(parseDate('2026-11-05'), DateTime.utc(2026, 11, 5));
    expect(formatShortDate(DateTime.utc(2026, 11, 5)), 'Thu 5 Nov');
  });

  test('Booking reads the API json', () {
    final booking = Booking.fromJson({
      'id': 9,
      'status': 'pending',
      'room_number': '301',
      'room_type': {'id': 3, 'name': 'VIP', 'cover_image': 'https://example.com/v.jpg'},
      'check_in_date': '2026-11-10',
      'check_out_date': '2026-11-12',
      'nights': 2,
      'guests': 2,
      'price_per_night': 50,
      'total_price': 100,
      'hold_seconds_left': 299,
    });

    expect(booking.roomNumber, '301');
    expect(booking.roomTypeName, 'VIP');
    expect(booking.checkIn, DateTime.utc(2026, 11, 10));
    expect(booking.totalPrice, 100);
    expect(booking.holdSecondsLeft, 299);
  });

  test('RoomType.canBook needs a free room and enough space', () {
    RoomType make(int? left) => RoomType(
          id: 1,
          name: 'Double',
          description: '',
          pricePerNight: 25,
          capacity: 4,
          totalRooms: 5,
          availableRooms: left,
          coverImage: null,
          images: const [],
        );

    expect(make(3).canBook(4), isTrue);
    expect(make(3).canBook(5), isFalse);
    expect(make(0).canBook(1), isFalse);
    expect(make(null).canBook(1), isTrue); // no dates yet: not blocked
  });

  test('RoomType reads the API json and formats the price', () {
    final type = RoomType.fromJson({
      'id': 2,
      'name': 'Double',
      'description': 'Roomy',
      'price_per_night': 25,
      'capacity': 4,
      'total_rooms': 5,
      'cover_image': 'https://example.com/a.jpg',
      'images': ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
    });

    expect(type.priceText, '\$25');
    expect(type.guestsText, 'Up to 4 guests');
    expect(type.images, hasLength(2));
    expect(type.coverImage, 'https://example.com/a.jpg');

    final cents = RoomType.fromJson({
      'id': 4,
      'name': 'Deluxe',
      'description': 'x',
      'price_per_night': 12.5,
      'capacity': 1,
      'cover_image': null,
      'images': <String>[],
    });
    expect(cents.priceText, '\$12.50');
    expect(cents.guestsText, '1 guest');
    expect(cents.totalRooms, 0);
  });
}
