import '../../core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/admin_repository.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../models/admin_room.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/angkor_app_bar.dart';

/// Admin: all room types with price and rooms. Tap one to change it.
class RoomTypesScreen extends ConsumerWidget {
  const RoomTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(adminRoomTypesProvider);

    return Scaffold(
      appBar: AngkorAppBar(title: 'Rooms and prices'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-type'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RoomTypeFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Room type'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminRoomTypesProvider),
        child: types.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ErrorBanner('$e'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(adminRoomTypesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
          data: (list) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              for (final t in list)
                Card(
                  child: ListTile(
                    key: Key('type-${t.id}'),
                    title: Text(t.name),
                    subtitle: Text(
                      '${formatMoney(t.pricePerNight)} per night · up to ${t.capacity} guests\n'
                      '${t.rooms.length} room${t.rooms.length == 1 ? '' : 's'}'
                      '${t.rooms.any((r) => r.inMaintenance) ? ' (${t.rooms.where((r) => r.inMaintenance).length} in maintenance)' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RoomTypeFormScreen(type: t),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Create a room type, or change one and manage its rooms.
class RoomTypeFormScreen extends ConsumerStatefulWidget {
  final AdminRoomType? type;
  const RoomTypeFormScreen({super.key, this.type});

  @override
  ConsumerState<RoomTypeFormScreen> createState() => _RoomTypeFormScreenState();
}

class _RoomTypeFormScreenState extends ConsumerState<RoomTypeFormScreen> {
  late final _name = TextEditingController(text: widget.type?.name ?? '');
  late final _description = TextEditingController(
    text: widget.type?.description ?? '',
  );
  late final _price = TextEditingController(
    text: widget.type == null
        ? ''
        : widget.type!.pricePerNight.toStringAsFixed(2),
  );
  late final _capacity = TextEditingController(
    text: '${widget.type?.capacity ?? ''}',
  );
  late final _photos = TextEditingController(
    text: (widget.type?.images ?? []).join('\n'),
  );
  final _roomNumber = TextEditingController();
  final _floor = TextEditingController(text: '1');

  late AdminRoomType? _type = widget.type;
  bool _busy = false;
  String? _error;
  String? _done;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _price,
      _capacity,
      _photos,
      _roomNumber,
      _floor,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Runs one change, shows the server's message if it is refused, and reloads the data after.
  Future<bool> _run(Future<void> Function() action, {String? doneText}) async {
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
      _fieldErrors = {};
    });
    try {
      await action();
      ref.invalidate(adminRoomTypesProvider);
      if (mounted) setState(() => _done = doneText);
      return true;
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _fieldErrors = e.fieldErrors;
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    final id = _type?.id;
    if (id == null) return;
    final all = await ref.read(adminRepositoryProvider).roomTypes();
    if (mounted) {
      setState(() => _type = all.where((t) => t.id == id).firstOrNull ?? _type);
    }
  }

  Future<void> _save() async {
    final price = double.tryParse(_price.text.trim());
    final capacity = int.tryParse(_capacity.text.trim());
    if (price == null || capacity == null) {
      setState(() => _error = 'Price and guests must be numbers.');
      return;
    }
    final photos = _photos.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final created = await _run(
      () async {
        final saved = await ref.read(adminRepositoryProvider).saveRoomType(
              id: _type?.id,
              name: _name.text.trim(),
              description: _description.text.trim(),
              price: price,
              capacity: capacity,
              images: photos,
            );
        _type = saved;
      },
      doneText: 'Saved. New bookings use this price; old bookings keep theirs.',
    );
    if (created && mounted) setState(() {});
  }

  Future<void> _deleteType() async {
    if (!await _confirm(
      'Delete this room type?',
      'Its photos are deleted too.',
    )) {
      return;
    }
    final ok = await _run(
      () => ref.read(adminRepositoryProvider).deleteRoomType(_type!.id),
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _addRoom() async {
    final floor = int.tryParse(_floor.text.trim());
    if (floor == null) {
      setState(() => _error = 'Floor must be a number.');
      return;
    }
    final ok = await _run(
      () => ref.read(adminRepositoryProvider).addRoom(
            roomTypeId: _type!.id,
            roomNumber: _roomNumber.text.trim(),
            floor: floor,
          ),
    );
    if (ok) {
      _roomNumber.clear();
      await _reload();
    }
  }

  Future<void> _toggle(AdminRoom r) async {
    final ok = await _run(
      () => ref
          .read(adminRepositoryProvider)
          .setRoomStatus(r.id, maintenance: !r.inMaintenance),
    );
    if (ok) await _reload();
  }

  Future<void> _deleteRoom(AdminRoom r) async {
    if (!await _confirm(
      'Delete room ${r.roomNumber}?',
      'This cannot be undone.',
    )) {
      return;
    }
    final ok = await _run(
      () => ref.read(adminRepositoryProvider).deleteRoom(r.id),
    );
    if (ok) await _reload();
  }

  Future<bool> _confirm(String title, String text) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, delete'),
          ),
        ],
      ),
    );
    return yes == true;
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _type == null;

    return Scaffold(
      appBar: AngkorAppBar(title: isNew ? 'New room type' : _type!.name),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            key: const Key('type-name'),
            controller: _name,
            decoration: InputDecoration(
              labelText: 'Name',
              errorText: _fieldErrors['name'],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Description',
              errorText: _fieldErrors['description'],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('type-price'),
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Price per night (USD)',
              errorText: _fieldErrors['price_per_night'],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('type-capacity'),
            controller: _capacity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Most guests',
              errorText: _fieldErrors['capacity'],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _photos,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Photo links (one per line, first is the cover)',
              errorText: _fieldErrors.entries
                  .where((e) => e.key.startsWith('images'))
                  .map((e) => e.value)
                  .firstOrNull,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('save-type'),
            onPressed: _busy ? null : _save,
            child: Text(isNew ? 'Create room type' : 'Save changes'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            ErrorBanner(_error!),
          ],
          if (_done != null) ...[
            const SizedBox(height: 16),
            Text(_done!, style: const TextStyle(color: Colors.green)),
          ],
          if (!isNew) ...[
            const Divider(height: 48),
            Text('Rooms', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final r in _type!.rooms)
              ListTile(
                key: Key('room-${r.roomNumber}'),
                contentPadding: EdgeInsets.zero,
                title: Text('Room ${r.roomNumber}'),
                subtitle: Text(
                  'Floor ${r.floor} · ${r.inMaintenance ? 'In maintenance' : 'Available'}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      key: Key('toggle-${r.roomNumber}'),
                      tooltip: r.inMaintenance
                          ? 'Put back in service'
                          : 'Put in maintenance',
                      icon: Icon(
                        r.inMaintenance
                            ? Icons.check_circle_outline
                            : Icons.build_outlined,
                      ),
                      onPressed: _busy ? null : () => _toggle(r),
                    ),
                    IconButton(
                      key: Key('delete-${r.roomNumber}'),
                      tooltip: 'Delete room',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy ? null : () => _deleteRoom(r),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('new-room-number'),
                    controller: _roomNumber,
                    decoration: InputDecoration(
                      labelText: 'New room number',
                      errorText: _fieldErrors['room_number'],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _floor,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Floor'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const Key('add-room'),
              onPressed: _busy ? null : _addRoom,
              child: const Text('Add room'),
            ),
            const Divider(height: 48),
            TextButton.icon(
              key: const Key('delete-type'),
              onPressed: _busy ? null : _deleteType,
              icon: Icon(Icons.delete_outline, color: context.pal.danger),
              label: Text(
                'Delete this room type',
                style: TextStyle(color: context.pal.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
