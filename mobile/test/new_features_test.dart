import 'package:angkor_stay/booking/stay_provider.dart';
import 'package:angkor_stay/core/api_client.dart';
import 'package:angkor_stay/core/format.dart';
import 'package:angkor_stay/core/theme_mode_provider.dart';
import 'package:angkor_stay/models/booking.dart';
import 'package:angkor_stay/screens/my_bookings_screen.dart';
import 'package:angkor_stay/widgets/notifications_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Booking _b({
  int id = 1,
  String status = 'confirmed',
  bool paid = false,
  String? method,
  String? detail,
  double refunded = 0,
  String? choice,
  int? holdSeconds,
}) => Booking(
  id: id,
  code: 'AS-000$id',
  status: status,
  roomNumber: '101',
  roomTypeName: 'Single',
  coverImage: null,
  checkIn: DateTime.utc(2026, 11, 10),
  checkOut: DateTime.utc(2026, 11, 12),
  nights: 2,
  guests: 1,
  pricePerNight: 15,
  totalPrice: 30,
  holdSecondsLeft: holdSeconds,
  paid: paid,
  paymentMethod: method,
  paymentDetail: detail,
  paymentChoice: choice,
  refundedAmount: refunded,
);

Future<ProviderContainer> _container([
  Map<String, Object> saved = const {},
]) async {
  SharedPreferences.setMockInitialValues(saved);
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('payment text follows the real payment', () {
    test('paid by KHQR at the desk, even if the guest never came', () {
      expect(
        bookingPayText(_b(status: 'no_show', paid: true, method: 'khqr')),
        'Paid \$30 (KHQR)',
      );
    });

    test('paid online shows the card detail', () {
      expect(
        bookingPayText(
          _b(paid: true, method: 'online', detail: 'Visa ending 4242'),
        ),
        'Paid \$30 (Visa ending 4242)',
      );
    });

    test('refunded money is shown as refunded', () {
      expect(
        bookingPayText(_b(status: 'cancelled', refunded: 25.5)),
        'Refunded \$25.50',
      );
    });

    test('a cancelled or no-show booking that was never paid says so', () {
      expect(bookingPayText(_b(status: 'cancelled')), 'No payment taken');
      expect(bookingPayText(_b(status: 'no_show')), 'No payment taken');
    });

    test('a running booking that is not paid yet', () {
      expect(bookingPayText(_b(status: 'pending')), 'Not paid yet');
    });
  });

  group('notifications built from bookings', () {
    test('a paid no-show says the payment was not refunded', () {
      final n = buildNotifications([_b(status: 'no_show', paid: true)]).single;
      expect(n.title, 'Marked as a no-show');
      expect(n.text, contains('not refunded'));
      expect(n.needsAction, isFalse);
    });

    test('a refunded cancellation says the money was sent back', () {
      final n = buildNotifications([_b(status: 'cancelled', refunded: 30)])
          .single;
      expect(n.text, contains('sent back'));
    });

    test('a confirmed booking and a kept room need the guest to act', () {
      final list = buildNotifications([
        _b(id: 1),
        _b(id: 2, status: 'pending', choice: 'hotel'),
        _b(id: 3, status: 'pending', holdSeconds: 120),
      ]);
      expect(list.length, 3);
      expect(list.every((n) => n.needsAction), isTrue);
    });

    test('no bookings, no notifications', () {
      expect(buildNotifications(const []), isEmpty);
    });
  });

  group('stay dates', () {
    test('old dates move to today and keep the number of nights', () async {
      final c = await _container();
      final today = dateOnly(DateTime.now());
      final n = c.read(stayProvider.notifier);
      n.setDates(
        today.subtract(const Duration(days: 4)),
        today.subtract(const Duration(days: 1)),
      );
      expect(c.read(stayProvider).nights, 3);

      n.refreshIfStale();

      expect(c.read(stayProvider).checkIn, today);
      expect(c.read(stayProvider).nights, 3);
    });

    test('dates that are still good are left alone', () async {
      final c = await _container();
      final today = dateOnly(DateTime.now());
      final n = c.read(stayProvider.notifier);
      n.setDates(
        today.add(const Duration(days: 2)),
        today.add(const Duration(days: 4)),
      );

      n.refreshIfStale();

      expect(c.read(stayProvider).checkIn, today.add(const Duration(days: 2)));
    });
  });

  group('settings kept on the phone', () {
    test(
      'light, dark or system is remembered; the default is system',
      () async {
        final c = await _container();
        expect(c.read(themeModeProvider), ThemeMode.system);

        c.read(themeModeProvider.notifier).set(ThemeMode.dark);
        expect(c.read(themeModeProvider), ThemeMode.dark);

        final again = await _container({'theme_mode': 'dark'});
        expect(again.read(themeModeProvider), ThemeMode.dark);
      },
    );
  });

  test('role words are shown with a capital letter', () {
    expect(titleCase('admin'), 'Admin');
    expect(titleCase('customer'), 'Customer');
    expect(titleCase(''), '');
  });
}
