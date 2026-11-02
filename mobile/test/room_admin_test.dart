import 'package:angkor_stay/admin/admin_repository.dart';
import 'package:angkor_stay/core/api_error.dart';
import 'package:angkor_stay/models/admin_room.dart';
import 'package:angkor_stay/screens/admin/room_types_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fake extends AdminRepository {
  _Fake() : super(Dio());

  List<AdminRoomType> types = [
    const AdminRoomType(
      id: 1,
      name: 'Single',
      description: 'Small',
      pricePerNight: 15,
      capacity: 2,
      images: ['https://example.com/a.jpg'],
      rooms: [
        AdminRoom(id: 10, roomNumber: '101', floor: 1, status: 'available'),
        AdminRoom(id: 11, roomNumber: '102', floor: 1, status: 'maintenance'),
      ],
    ),
  ];

  ApiError? error;
  final saved = <Map<String, Object?>>[];
  final added = <String>[];
  final toggled = <int>[];
  final deletedRooms = <int>[];
  final deletedTypes = <int>[];

  void _fail() {
    final e = error;
    if (e != null) {
      error = null;
      throw e;
    }
  }

  @override
  Future<List<AdminRoomType>> roomTypes() async => List.of(types);

  @override
  Future<AdminRoomType> saveRoomType({
    int? id,
    required String name,
    required String description,
    required double price,
    required int capacity,
    required List<String> images,
  }) async {
    _fail();
    saved.add({'id': id, 'name': name, 'price': price, 'capacity': capacity, 'images': images});
    final t = AdminRoomType(
        id: id ?? 99, name: name, description: description, pricePerNight: price, capacity: capacity, images: images, rooms: const []);
    types = id == null ? [...types, t] : [for (final x in types) x.id == id ? t : x];
    return t;
  }

  @override
  Future<void> addRoom({required int roomTypeId, required String roomNumber, required int floor}) async {
    _fail();
    added.add('$roomNumber@$floor');
    final t = types.first;
    types = [
      AdminRoomType(
        id: t.id,
        name: t.name,
        description: t.description,
        pricePerNight: t.pricePerNight,
        capacity: t.capacity,
        images: t.images,
        rooms: [...t.rooms, AdminRoom(id: 50, roomNumber: roomNumber, floor: floor, status: 'available')],
      )
    ];
  }

  @override
  Future<void> setRoomStatus(int roomId, {required bool maintenance}) async {
    _fail();
    toggled.add(roomId);
  }

  @override
  Future<void> deleteRoom(int roomId) async {
    _fail();
    deletedRooms.add(roomId);
  }

  @override
  Future<void> deleteRoomType(int id) async {
    _fail();
    deletedTypes.add(id);
  }
}

Future<void> _pump(WidgetTester tester, Widget home, _Fake fake) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    retry: (c, e) => null,
    overrides: [adminRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(home: home),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the list shows price, size and how many rooms are in maintenance', (tester) async {
    await _pump(tester, const RoomTypesScreen(), _Fake());
    expect(find.text('Single'), findsOneWidget);
    expect(find.textContaining('\$15 per night · up to 2 guests'), findsOneWidget);
    expect(find.textContaining('2 rooms (1 in maintenance)'), findsOneWidget);
  });

  testWidgets('tapping a type opens its form with the saved values', (tester) async {
    await _pump(tester, const RoomTypesScreen(), _Fake());
    await tester.tap(find.byKey(const Key('type-1')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byKey(const Key('type-name'))).controller!.text, 'Single');
    expect(tester.widget<TextField>(find.byKey(const Key('type-price'))).controller!.text, '15.00');
    expect(find.text('Room 101'), findsOneWidget);
    expect(find.text('Room 102'), findsOneWidget);
  });

  testWidgets('a new price is sent to the server', (tester) async {
    final fake = _Fake();
    await _pump(tester, RoomTypeFormScreen(type: fake.types.first), fake);

    await tester.enterText(find.byKey(const Key('type-price')), '22.5');
    await tester.tap(find.byKey(const Key('save-type')));
    await tester.pumpAndSettle();

    expect(fake.saved.single['id'], 1);
    expect(fake.saved.single['price'], 22.5);
    expect(fake.saved.single['images'], ['https://example.com/a.jpg']);
    expect(find.textContaining('old bookings keep theirs'), findsOneWidget);
  });

  testWidgets('a wrong price shows a message and sends nothing', (tester) async {
    final fake = _Fake();
    await _pump(tester, RoomTypeFormScreen(type: fake.types.first), fake);

    await tester.enterText(find.byKey(const Key('type-price')), 'abc');
    await tester.tap(find.byKey(const Key('save-type')));
    await tester.pumpAndSettle();

    expect(find.text('Price and guests must be numbers.'), findsOneWidget);
    expect(fake.saved, isEmpty);
  });

  testWidgets('a new type is created when there is none yet', (tester) async {
    final fake = _Fake();
    await _pump(tester, const RoomTypeFormScreen(), fake);

    await tester.enterText(find.byKey(const Key('type-name')), 'Suite');
    await tester.enterText(find.byKey(const Key('type-price')), '80');
    await tester.enterText(find.byKey(const Key('type-capacity')), '6');
    await tester.tap(find.byKey(const Key('save-type')));
    await tester.pumpAndSettle();

    expect(fake.saved.single['id'], isNull);
    expect(fake.saved.single['name'], 'Suite');
    expect(find.text('Delete this room type'), findsOneWidget); // now it is a saved type
  });

  testWidgets('adding a room shows it in the list', (tester) async {
    final fake = _Fake();
    await _pump(tester, RoomTypeFormScreen(type: fake.types.first), fake);

    await tester.enterText(find.byKey(const Key('new-room-number')), '106');
    await tester.ensureVisible(find.byKey(const Key('add-room')));
    await tester.tap(find.byKey(const Key('add-room')));
    await tester.pumpAndSettle();

    expect(fake.added, ['106@1']);
    expect(find.text('Room 106'), findsOneWidget);
  });

  testWidgets('the server refusing a delete is shown, and the room stays', (tester) async {
    final fake = _Fake()..error = const ApiError('This room has bookings, so it cannot be deleted.', statusCode: 409);
    await _pump(tester, RoomTypeFormScreen(type: fake.types.first), fake);

    await tester.tap(find.byKey(const Key('delete-101')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, delete'));
    await tester.pumpAndSettle();

    expect(find.textContaining('has bookings'), findsOneWidget);
    expect(find.text('Room 101'), findsOneWidget);
  });

  testWidgets('maintenance toggle and room delete reach the server', (tester) async {
    final fake = _Fake();
    await _pump(tester, RoomTypeFormScreen(type: fake.types.first), fake);

    await tester.tap(find.byKey(const Key('toggle-101')));
    await tester.pumpAndSettle();
    expect(fake.toggled, [10]);

    await tester.tap(find.byKey(const Key('delete-102')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, delete'));
    await tester.pumpAndSettle();
    expect(fake.deletedRooms, [11]);
  });
}
