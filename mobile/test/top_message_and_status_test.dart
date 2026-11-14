import 'package:angkor_stay/core/format.dart';
import 'package:angkor_stay/core/theme.dart';
import 'package:angkor_stay/widgets/status_chip.dart';
import 'package:angkor_stay/widgets/top_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _app(
  WidgetTester tester,
  void Function(BuildContext context) onTap,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: buildAngkorTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('go'),
              onPressed: () => onTap(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('messages at the top', () {
    testWidgets(
      'a message shows near the TOP of the screen, not at the bottom',
      (tester) async {
        await _app(tester, (c) => TopMessage.of(c).show('Settings saved.'));

        await tester.tap(find.byKey(const Key('go')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Settings saved.'), findsOneWidget);
        final centre = tester.getCenter(find.byKey(const Key('top-message')));
        expect(centre.dy, lessThan(200)); // the screen is 1600 high
        expect(find.byType(SnackBar), findsNothing);

        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('it goes away by itself after a few seconds', (tester) async {
      await _app(tester, (c) => TopMessage.of(c).show('Done.'));

      await tester.tap(find.byKey(const Key('go')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Done.'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Done.'), findsNothing);
    });

    testWidgets('a problem message stays longer than a good one', (
      tester,
    ) async {
      await _app(
        tester,
        (c) => TopMessage.of(c).show('Cannot save.', error: true),
      );

      await tester.tap(find.byKey(const Key('go')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.text('Cannot save.'),
        findsOneWidget,
      ); // still there after 3 s

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cannot save.'), findsNothing);
    });

    testWidgets('a new message replaces the old one', (tester) async {
      var n = 0;
      await _app(tester, (c) => TopMessage.of(c).show('Message ${++n}'));

      await tester.tap(find.byKey(const Key('go')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('go')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Message 1'), findsNothing);
      expect(find.text('Message 2'), findsOneWidget);
      expect(find.byKey(const Key('top-message')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tapping it closes it', (tester) async {
      await _app(tester, (c) => TopMessage.of(c).show('Tap me'));

      await tester.tap(find.byKey(const Key('go')));
      await tester.pump(); // the message is built, its slide-in starts
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Tap me'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('Tap me'), findsNothing);
    });

    testWidgets(
      'it still shows after the screen that asked for it was closed',
      (tester) async {
        // Like "The room was released.": the screen is popped first, then the message appears.
        await _app(tester, (c) {
          Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) => Builder(
                builder: (inner) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      key: const Key('inner'),
                      onPressed: () {
                        final top = TopMessage.of(inner);
                        Navigator.of(inner).pop();
                        top.show('Back on the list.');
                      },
                      child: const Text('inner'),
                    ),
                  ),
                ),
              ),
            ),
          );
        });

        await tester.tap(find.byKey(const Key('go')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('inner')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Back on the list.'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
      },
    );
  });

  group('booking status words', () {
    test('a confirmed booking says Paid or Pay at hotel; the other states keep their words', () {
      expect(bookingStatusLabel('confirmed', paid: true), 'Paid');
      expect(bookingStatusLabel('confirmed', paid: false), 'Pay at hotel');
      expect(bookingStatusLabel('checked_in', paid: true), 'Checked in');
      expect(bookingStatusLabel('checked_out', paid: true), 'Checked out');
      expect(bookingStatusLabel('pending', paid: false), 'Waiting for payment');
      expect(bookingStatusLabel('cancelled', paid: false), 'Cancelled');
      expect(bookingStatusLabel('no_show', paid: false), 'No-show');
    });

    Future<void> chip(WidgetTester tester, StatusChip c) => tester.pumpWidget(
      MaterialApp(
        theme: buildAngkorTheme(),
        home: Scaffold(body: Center(child: c)),
      ),
    );

    testWidgets('the chip shows Paid, Checked in and Checked out', (
      tester,
    ) async {
      await chip(tester, const StatusChip('confirmed', paid: true));
      expect(find.text('Paid'), findsOneWidget);

      await chip(tester, const StatusChip('confirmed', paid: false));
      expect(find.text('Pay at hotel'), findsOneWidget);

      await chip(tester, const StatusChip('checked_in', paid: true));
      expect(find.text('Checked in'), findsOneWidget);

      await chip(tester, const StatusChip('checked_out', paid: true));
      expect(find.text('Checked out'), findsOneWidget);
    });

    testWidgets('without the paid flag the chip keeps the plain words', (
      tester,
    ) async {
      await chip(tester, const StatusChip('confirmed'));
      expect(find.text('Confirmed'), findsOneWidget);
    });

    testWidgets('the Paid chip also works in dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAngkorTheme(Brightness.dark),
          home: const Scaffold(
            body: Center(child: StatusChip('confirmed', paid: true)),
          ),
        ),
      );
      expect(find.text('Paid'), findsOneWidget);
    });
  });
}
