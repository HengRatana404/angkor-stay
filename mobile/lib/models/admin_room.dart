/// One room as the admin sees it.
class AdminRoom {
  final int id;
  final String roomNumber;
  final int floor;
  final String status; // available | maintenance

  const AdminRoom({required this.id, required this.roomNumber, required this.floor, required this.status});

  factory AdminRoom.fromJson(Map<String, dynamic> json) => AdminRoom(
        id: json['id'] as int,
        roomNumber: json['room_number'] as String,
        floor: json['floor'] as int,
        status: json['status'] as String,
      );

  bool get inMaintenance => status == 'maintenance';
}

/// One room type with its photos and rooms, as the admin sees it.
class AdminRoomType {
  final int id;
  final String name;
  final String description;
  final double pricePerNight;
  final int capacity;
  final List<String> images;
  final List<AdminRoom> rooms;

  const AdminRoomType({
    required this.id,
    required this.name,
    required this.description,
    required this.pricePerNight,
    required this.capacity,
    required this.images,
    required this.rooms,
  });

  factory AdminRoomType.fromJson(Map<String, dynamic> json) => AdminRoomType(
        id: json['id'] as int,
        name: json['name'] as String,
        description: json['description'] as String,
        pricePerNight: (json['price_per_night'] as num).toDouble(),
        capacity: json['capacity'] as int,
        images: (json['images'] as List).cast<String>(),
        rooms: (json['rooms'] as List)
            .map((r) => AdminRoom.fromJson(r as Map<String, dynamic>))
            .toList(),
      );
}
