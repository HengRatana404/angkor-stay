import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../booking/stay_provider.dart';
import '../models/room_type.dart';
import '../screens/room_type_detail_screen.dart';
import 'room_photo.dart';

class RoomTypeCard extends ConsumerWidget {
  final RoomType roomType;
  const RoomTypeCard({super.key, required this.roomType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final guests = ref.watch(stayProvider).guests;
    final bookable = roomType.canBook(guests);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RoomTypeDetailScreen(roomType: roomType)),
        ),
        child: Opacity(
          opacity: bookable ? 1 : 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  RoomPhoto(url: roomType.coverImage, height: 180),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: AvailabilityChip(roomType: roomType, guests: guests),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(roomType.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.people_outline, size: 18),
                              const SizedBox(width: 4),
                              Text(roomType.guestsText),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          roomType.priceText,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text('per night'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "3 left", "Only 1 left", "No room left" or "Fits up to 2 guests".
class AvailabilityChip extends StatelessWidget {
  final RoomType roomType;
  final int guests;
  const AvailabilityChip({super.key, required this.roomType, required this.guests});

  @override
  Widget build(BuildContext context) {
    final left = roomType.availableRooms;
    if (left == null) return const SizedBox.shrink();

    final String text;
    final Color color;
    if (!roomType.fitsGuests(guests)) {
      text = 'Fits up to ${roomType.capacity} guests';
      color = Colors.red.shade700;
    } else if (left == 0) {
      text = 'No room left';
      color = Colors.red.shade700;
    } else if (left <= 2) {
      text = 'Only $left left';
      color = Colors.orange.shade800;
    } else {
      text = '$left rooms left';
      color = Colors.green.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}
