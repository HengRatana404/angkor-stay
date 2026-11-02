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
import 'booking_hold_screen.dart';

class RoomTypeDetailScreen extends ConsumerStatefulWidget {
  final RoomType roomType;
  const RoomTypeDetailScreen({super.key, required this.roomType});

  @override
  ConsumerState<RoomTypeDetailScreen> createState() => _RoomTypeDetailScreenState();
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
        MaterialPageRoute(builder: (_) => BookingHoldScreen(booking: booking)),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      // Show the most useful message: a field message, or the main one.
      final message = e.fieldErrors.values.isNotEmpty ? e.fieldErrors.values.first : e.message;
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
    final latest = ref.watch(roomTypesProvider).maybeWhen(
          data: (list) => list.where((t) => t.id == widget.roomType.id).firstOrNull,
          orElse: () => null,
        );
    final room = latest ?? widget.roomType;
    final theme = Theme.of(context);
    final photos = room.images.isEmpty ? <String?>[null] : room.images;
    final total = stay.nights * room.pricePerNight;

    final String? blockedReason = !room.fitsGuests(stay.guests)
        ? 'A ${room.name} room fits up to ${room.capacity} guests. Change the number of guests on the first page.'
        : !room.hasRoomLeft
            ? 'No ${room.name} room left for these dates. Try other dates.'
            : null;

    return Scaffold(
      appBar: AppBar(title: Text('${room.name} room')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 8)],
              if (blockedReason != null && _error == null) ...[
                Text(blockedReason, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('book-button'),
                  onPressed: (_busy || blockedReason != null) ? null : () => _book(room, stay),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Book for ${formatMoney(total)}'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              children: [
                PageView.builder(
                  itemCount: photos.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => RoomPhoto(url: photos[i], height: 260),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: AvailabilityChip(roomType: room, guests: stay.guests),
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
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 18 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: i == _page ? Colors.white : Colors.white54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(room.name, style: theme.textTheme.headlineMedium)),
                    Text(
                      room.priceText,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(' / night'),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(avatar: const Icon(Icons.people_outline), label: Text(room.guestsText)),
                    Chip(
                      avatar: const Icon(Icons.meeting_room_outlined),
                      label: Text('${room.totalRooms} rooms'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text('${formatShortDate(stay.checkIn)}  →  ${formatShortDate(stay.checkOut)}'),
                    subtitle: Text(
                      '${nightsText(stay.nights)} · '
                      '${stay.guests == 1 ? '1 guest' : '${stay.guests} guests'}',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('About this room', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(room.description, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
