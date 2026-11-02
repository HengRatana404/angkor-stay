import 'package:angkor_stay/admin/admin_repository.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/models/dashboard.dart';
import 'package:angkor_stay/screens/admin/dashboard_screen.dart';
import 'package:angkor_stay/screens/staff/staff_booking_detail_screen.dart';
import 'package:angkor_stay/staff/staff_booking_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _json({List<Map<String, dynamic>>? pending}) => {
      'today': {'check_ins': 3, 'checked_in_so_far': 1, 'check_outs': 2, 'checked_out_so_far': 2},
      'rooms': {'total': 15, 'occupied': 4, 'maintenance': 1, 'free': 10},
      'money': {'today': 55.5, 'month': 410.25, 'month_online': 250.25, 'month_hotel': 160, 'month_refunded': 21.25},
      'pending': {'count': (pending ?? _pending).length, 'items': pending ?? _pending},
      'last_7_days': [
        for (var i = 0; i < 7; i++)
          {'date': '2026-11-0${i + 1}', 'bookings': i == 3 ? 4 : (i == 6 ? 2 : 0), 'money': 0},
      ],
    };

final _pending = [
  {
    'id': 5,
    'code': 'AS-0005',
    'guest': 'Sokha',
    'room_number': '201',
    'check_in_date': '2026-11-10',
    'check_out_date': '2026-11-12',
    'amount_due': 50,
  },
];

class _Fake extends AdminRepository {
  _Fake(this.body) : super(Dio());
  final Map<String, dynamic> body;
  ApiError? error;

  @override
  Future<Dashboard> dashboard() async {
    if (error != null) throw error!;
    return Dashboard.fromJson(body);
  }
}

Future<void> _open(WidgetTester tester, _Fake fake) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (c, e) => null,
    overrides: [
      adminRepositoryProvider.overrideWithValue(fake),
      // The booking page that opens from the list stays loading: we only check that it opens.
      staffBookingProvider.overrideWith((ref, id) => Future<Never>.delayed(const Duration(days: 1))),
    ],
    child: const MaterialApp(home: DashboardScreen()),
  ));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) {
  final texts = tester
      .widgetList<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)))
      .map((t) => t.data)
      .toList();
  return texts.join('|');
}

void main() {
  testWidgets('the numbers are exactly what the server sent', (tester) async {
    await _open(tester, _Fake(_json()));

    expect(_text(tester, 'stat-checkins'), 'Check-ins|3|1 done');
    expect(_text(tester, 'stat-checkouts'), 'Check-outs|2|2 done');
    expect(_text(tester, 'stat-free'), 'Free rooms|10|of 15');
    expect(_text(tester, 'stat-occupied'), 'Occupied|4|1 in maintenance');
    expect(_text(tester, 'stat-money-today'), 'Today|\$55.50');
    expect(_text(tester, 'stat-money-month'), 'This month|\$410.25');
    expect(_text(tester, 'stat-online'), 'Online (month)|\$250.25');
    expect(_text(tester, 'stat-hotel'), 'At hotel (month)|\$160');
    expect(find.text('Refunded this month: \$21.25'), findsOneWidget);
  });

  testWidgets('the chart has one bar per day and the tallest day is the busiest', (tester) async {
    await _open(tester, _Fake(_json()));

    expect(find.byKey(const Key('bar-2026-11-04')), findsOneWidget);
    expect(find.byKey(const Key('bar-2026-11-01')), findsOneWidget);
    final busy = tester.getSize(find.byKey(const Key('bar-2026-11-04'))).height;
    final half = tester.getSize(find.byKey(const Key('bar-2026-11-07'))).height;
    final none = tester.getSize(find.byKey(const Key('bar-2026-11-02'))).height;
    expect(busy, greaterThan(half));
    expect(half, greaterThan(none));
    expect(tester.widget<Text>(find.byKey(const Key('bar-count-2026-11-04'))).data, '4');
  });

  testWidgets('the waiting list shows the guest and tapping opens that booking', (tester) async {
    await _open(tester, _Fake(_json()));

    expect(find.text('Waiting to be paid (1)'), findsOneWidget);
    expect(find.textContaining('Sokha'), findsOneWidget);
    expect(find.textContaining('AS-0005 · Room 201'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pending-5')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final page = tester.widget<StaffBookingDetailScreen>(find.byType(StaffBookingDetailScreen));
    expect(page.bookingId, 5);
  });

  testWidgets('an empty waiting list says nothing is waiting', (tester) async {
    await _open(tester, _Fake(_json(pending: [])));
    expect(find.text('Nothing is waiting.'), findsOneWidget);
  });

  testWidgets('a server error shows a message and a retry button', (tester) async {
    await _open(tester, _Fake(_json())..error = const ApiError('Server is down.'));
    expect(find.textContaining('Server is down.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
