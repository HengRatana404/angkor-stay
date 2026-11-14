import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../booking/stay_provider.dart';
import '../models/room_type.dart';
import '../screens/room_type_detail_screen.dart';
import 'room_photo.dart';
import '../core/theme.dart';
import 'motion.dart';

class RoomTypeCard extends ConsumerWidget {
  final RoomType roomType;
  const RoomTypeCard({super.key, required this.roomType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final guests = ref.watch(stayProvider).guests;
    final bookable = roomType.canBook(guests);

    return PressScale(
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: context.pal.border, width: 1),
        ),
        elevation: 1,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RoomTypeDetailScreen(roomType: roomType),
            ),
          ),
          child: Opacity(
            opacity: bookable ? 1 : 0.65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Hero(
                      tag: 'room-photo-${roomType.id}',
                      child: RoomPhoto(url: roomType.coverImage, height: 170),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: AvailabilityChip(
                        roomType: roomType,
                        guests: guests,
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: context.pal.accent,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '15% off online',
                          style: TextStyle(
                            color: context.pal.onAccent,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        roomType.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.group_outlined,
                                size: 15,
                                color: context.pal.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                roomType.guestsText,
                                style: TextStyle(
                                  color: context.pal.textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.wifi,
                                size: 15,
                                color: context.pal.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Free Wi-Fi',
                                style: TextStyle(
                                  color: context.pal.textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.ac_unit,
                                size: 15,
                                color: context.pal.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'AC',
                                style: TextStyle(
                                  color: context.pal.textMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    roomType.priceText,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: context.pal.text,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 22,
                                    ),
                                  ),
                                  Text(
                                    ' / night',
                                    style: TextStyle(
                                      color: context.pal.textMuted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Includes taxes & fees',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.pal.textMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          FilledButton.icon(
                            key: Key('book-now-${roomType.id}'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    RoomTypeDetailScreen(roomType: roomType),
                              ),
                            ),
                            iconAlignment: IconAlignment.end,
                            icon: Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: context.pal.onAction,
                            ),
                            label: const Text(
                              'Book Now',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: context.pal.action,
                              foregroundColor: context.pal.onAction,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                              shadowColor: const Color(0x33000000),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
  const AvailabilityChip({
    super.key,
    required this.roomType,
    required this.guests,
  });

  @override
  Widget build(BuildContext context) {
    final left = roomType.availableRooms;
    if (left == null) return const SizedBox.shrink();

    final String text;
    final Color bgColor;
    final Color textColor;
    final Color borderColor;
    if (!roomType.fitsGuests(guests)) {
      text = 'Fits up to ${roomType.capacity} guests';
      bgColor = context.pal.dangerWash;
      textColor = context.pal.danger;
      borderColor = context.pal.dangerBorder;
    } else if (left == 0) {
      text = 'No room left';
      bgColor = context.pal.dangerWash;
      textColor = context.pal.danger;
      borderColor = context.pal.dangerBorder;
    } else if (left <= 2) {
      text = 'Only $left left';
      bgColor = context.pal.goldWash;
      textColor = context.pal.goldDeep;
      borderColor = context.pal.goldSoft;
    } else {
      text = '$left rooms left';
      bgColor = context.pal.successWash;
      textColor = context.pal.success;
      borderColor = context.pal.successBorder;
    }

    return ChangeSwitcher(
      value: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
