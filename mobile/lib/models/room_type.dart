import '../core/format.dart';

class RoomType {
  final int id;
  final String name;
  final String description;
  final double pricePerNight;
  final int capacity;
  final int totalRooms;

  /// Rooms free for the chosen nights. Null when no dates were sent.
  final int? availableRooms;
  final String? coverImage;
  final List<String> images;

  const RoomType({
    required this.id,
    required this.name,
    required this.description,
    required this.pricePerNight,
    required this.capacity,
    required this.totalRooms,
    required this.coverImage,
    required this.images,
    this.availableRooms,
  });

  factory RoomType.fromJson(Map<String, dynamic> json) => RoomType(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String,
        pricePerNight: (json['price_per_night'] as num).toDouble(),
        capacity: json['capacity'] as int,
        totalRooms: (json['total_rooms'] as num?)?.toInt() ?? 0,
        availableRooms: (json['available_rooms'] as num?)?.toInt(),
        coverImage: json['cover_image'] as String?,
        images: ((json['images'] as List?) ?? const []).cast<String>(),
      );

  /// "$15" or "$12.50".
  String get priceText => formatMoney(pricePerNight);

  String get guestsText => capacity == 1 ? '1 guest' : 'Up to $capacity guests';

  bool fitsGuests(int guests) => guests <= capacity;

  /// True when at least one room is free (or we do not know yet).
  bool get hasRoomLeft => (availableRooms ?? 1) > 0;

  bool canBook(int guests) => hasRoomLeft && fitsGuests(guests);
}
