import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../core/api_client.dart';
import '../core/server_address_dialog.dart';
import '../models/app_user.dart';
import '../rooms/room_types_provider.dart';
import '../widgets/error_banner.dart';
import 'my_bookings_screen.dart';
import 'profile_screen.dart';
import '../widgets/room_type_card.dart';
import '../widgets/stay_card.dart';

class HomeScreen extends ConsumerWidget {
  final AppUser user;
  const HomeScreen({super.key, required this.user});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(healthProvider);
    ref.invalidate(roomTypesProvider);
    try {
      await ref.read(roomTypesProvider.future);
    } catch (_) {
      // The error is shown on screen by the room list itself.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    final rooms = ref.watch(roomTypesProvider);
    final baseUrl = ref.watch(baseUrlProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Angkor Stay'),
        actions: [
          IconButton(
            tooltip: 'My bookings',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const MyBookingsScreen())),
          ),
          IconButton(
            tooltip: 'My profile',
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
          ),
          IconButton(
            tooltip: 'Server address',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              if (await showServerAddressDialog(context, ref)) {
                await _refresh(ref);
              }
            },
          ),
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Text('Hello, ${user.name}', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(user.role.toUpperCase())),
                Chip(label: Text(user.email)),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                dense: true,
                leading: health.when(
                  loading: () => const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, _) => const Icon(Icons.error, color: Colors.red),
                  data: (h) => Icon(
                    h.ok ? Icons.check_circle : Icons.error,
                    color: h.ok ? Colors.green : Colors.red,
                  ),
                ),
                title: Text(health.maybeWhen(
                  data: (h) => h.ok ? 'Connected' : 'Not connected',
                  orElse: () => 'Checking...',
                )),
                subtitle: Text(baseUrl),
              ),
            ),
            const SizedBox(height: 16),
            const StayCard(),
            const SizedBox(height: 24),
            Text('Our rooms', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            rooms.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Column(
                children: [
                  ErrorBanner('$error'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(roomTypesProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
              data: (list) => list.isEmpty
                  ? const Text('No rooms yet.')
                  : Column(children: [for (final t in list) RoomTypeCard(roomType: t)]),
            ),
          ],
        ),
      ),
    );
  }
}
