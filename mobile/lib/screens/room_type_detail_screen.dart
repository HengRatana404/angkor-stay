import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../booking/booking_repository.dart';
import '../booking/stay_provider.dart';
import '../core/api_error.dart';
import '../core/format.dart';
import '../models/room_type.dart';
import '../rooms/room_types_provider.dart';
import '../widgets/error_banner.dart';
import '../widgets/room_photo.dart';
import '../widgets/room_type_card.dart';
import '../widgets/stay_card.dart';
import 'booking_hold_screen.dart';
import '../core/theme.dart';
import '../widgets/angkor_app_bar.dart';
import '../widgets/motion.dart';

class RoomTypeDetailScreen extends ConsumerStatefulWidget {
  final RoomType roomType;
  const RoomTypeDetailScreen({super.key, required this.roomType});

  @override
  ConsumerState<RoomTypeDetailScreen> createState() =>
      _RoomTypeDetailScreenState();
}

class _RoomTypeDetailScreenState extends ConsumerState<RoomTypeDetailScreen> {
  int _page = 0;
  bool _busy = false;
  String? _error;

  Future<void> _book(RoomType room, Stay stay) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final booking = await ref
          .read(bookingRepositoryProvider)
          .create(roomTypeId: room.id, stay: stay);
      if (!mounted) return;
      // Someone just took a room, so the numbers on the list changed.
      ref.invalidate(roomTypesProvider);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => BookingHoldScreen(booking: booking)),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      // Show the most useful message: a field message, or the main one.
      final message = e.fieldErrors.values.isNotEmpty
          ? e.fieldErrors.values.first
          : e.message;
      setState(() => _error = message);
      // "No room left": refresh so the list shows the truth.
      if (e.code == 'no_room_left') ref.invalidate(roomTypesProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stay = ref.watch(stayProvider);
    // The list is refreshed in the background, so use the newest numbers.
    final latest = ref
        .watch(roomTypesProvider)
        .maybeWhen(
          data: (list) =>
              list.where((t) => t.id == widget.roomType.id).firstOrNull,
          orElse: () => null,
        );
    final room = latest ?? widget.roomType;
    final photos = room.images.isEmpty ? <String?>[null] : room.images;
    final total = stay.nights * room.pricePerNight;

    final String? blockedReason = !room.fitsGuests(stay.guests)
        ? 'A ${room.name} room fits up to ${room.capacity} guests.'
        : !room.hasRoomLeft
        ? 'No ${room.name} room left for these dates. Try other dates.'
        : null;

    return Scaffold(
      appBar: AngkorAppBar(title: '${room.name} room'),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.pal.surface,
          border: Border(top: BorderSide(color: context.pal.border, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 10,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  ErrorBanner(_error!),
                  const SizedBox(height: 8),
                ],
                if (blockedReason != null && _error == null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: context.pal.dangerWash,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.pal.dangerBorder),
                    ),
                    child: Text(
                      blockedReason,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.pal.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatMoney(total),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: context.pal.text,
                            ),
                          ),
                          Text(
                            'Total for ${nightsText(stay.nights)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.pal.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    FilledButton(
                      key: const Key('book-button'),
                      onPressed: (_busy || blockedReason != null)
                          ? null
                          : () => _book(room, stay),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.pal.action,
                        foregroundColor: context.pal.onAction,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Book for ${formatMoney(total)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                height: 260,
                child: Stack(
                  children: [
                    PageView.builder(
                      itemCount: photos.length,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemBuilder: (_, i) => i == 0
                          ? Hero(
                              tag: 'room-photo-${room.id}',
                              child: RoomPhoto(url: photos[i], height: 260),
                            )
                          : RoomPhoto(url: photos[i], height: 260),
                    ),
                    Positioned(
                      top: 14,
                      left: 14,
                      child: AvailabilityChip(
                        roomType: room,
                        guests: stay.guests,
                      ),
                    ),
                    Positioned(
                      top: 14,
                      right: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: context.pal.accent,
                          borderRadius: BorderRadius.circular(10),
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
                    if (photos.length > 1)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < photos.length; i++)
                              Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                width: i == _page ? 20 : 7,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i == _page
                                      ? context.pal.accent
                                      : Colors.white60,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          FadeSlideIn(
            index: 1,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          room.name,
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: context.pal.text,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            room.priceText,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: context.pal.accent,
                            ),
                          ),
                          Text(
                            '/ night',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.pal.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _FeatureChip(
                        icon: Icons.people_outline,
                        label: room.guestsText,
                      ),
                      _FeatureChip(
                        icon: Icons.meeting_room_outlined,
                        label: room.totalRooms == 1
                            ? '1 room'
                            : '${room.totalRooms} rooms',
                      ),
                      const _FeatureChip(icon: Icons.wifi, label: 'Free Wi-Fi'),
                      const _FeatureChip(icon: Icons.ac_unit, label: 'AC'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const StayCard(),
                  const SizedBox(height: 20),
                  Text(
                    'About this room',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.pal.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    room.description,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: context.pal.textMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Amenities',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.pal.text,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.pal.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.pal.border),
                    ),
                    child: const Column(
                      children: [
                        _AmenityRow(
                          icon: Icons.free_breakfast_outlined,
                          label: 'Breakfast Included / Available',
                        ),
                        Divider(height: 16),
                        _AmenityRow(
                          icon: Icons.pool_outlined,
                          label: 'Tropical Swimming Pool & Garden',
                        ),
                        Divider(height: 16),
                        _AmenityRow(
                          icon: Icons.cleaning_services_outlined,
                          label: 'Daily Housekeeping & Turndown',
                        ),
                        Divider(height: 16),
                        _AmenityRow(
                          icon: Icons.support_agent_outlined,
                          label: '24/7 Concierge & Tour Desk',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.pal.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.pal.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: context.pal.goldDeep),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.pal.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmenityRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AmenityRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.pal.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.pal.text,
            ),
          ),
        ),
      ],
    );
  }
}
