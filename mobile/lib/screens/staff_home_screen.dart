import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../admin/admin_repository.dart';
import '../core/api_client.dart';
import '../core/api_error.dart';
import '../core/server_address_dialog.dart';
import '../models/app_user.dart';
import 'admin/dashboard_screen.dart';
import 'admin/room_types_screen.dart';
import 'admin/settings_screen.dart';
import 'admin/staff_list_screen.dart';
import 'staff/staff_bookings_screen.dart';

/// The home page for staff and admin. The admin sees extra tiles.
class StaffHomeScreen extends ConsumerWidget {
  final AppUser user;
  const StaffHomeScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    final baseUrl = ref.watch(baseUrlProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Angkor Stay'),
        actions: [
          IconButton(
            tooltip: 'Server address',
            icon: const Icon(Icons.settings_ethernet),
            onPressed: () async {
              if (await showServerAddressDialog(context, ref)) {
                ref.invalidate(healthProvider);
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
        onRefresh: () async => ref.invalidate(healthProvider),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Text('Hello, ${user.name}', style: theme.textTheme.headlineMedium),
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
            const SizedBox(height: 24),
            Text('Front desk', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _Tile(
              key: const Key('tile-bookings'),
              icon: Icons.event_note_outlined,
              title: 'Bookings',
              subtitle: 'Find a guest, take payment, check in and check out',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StaffBookingsScreen()),
              ),
            ),
            const SizedBox(height: 12),
            if (user.isAdmin) ...[
              Text('Admin', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              _Tile(
                key: const Key('tile-dashboard'),
                icon: Icons.dashboard_outlined,
                title: 'Dashboard',
                subtitle: 'Today, rooms, money, bookings waiting to be paid',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DashboardScreen()),
                ),
              ),
              _Tile(
                key: const Key('tile-staff'),
                icon: Icons.badge_outlined,
                title: 'Staff accounts',
                subtitle: 'Add staff, turn accounts on or off, set a new password',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StaffListScreen()),
                ),
              ),
              _Tile(
                key: const Key('tile-rooms'),
                icon: Icons.bed_outlined,
                title: 'Rooms and prices',
                subtitle: 'Room types, prices, photos, and single rooms',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RoomTypesScreen()),
                ),
              ),
              _Tile(
                key: const Key('tile-settings'),
                icon: Icons.tune,
                title: 'Hotel settings',
                subtitle: 'Online discount, check-in and check-out times, hotel network',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              _Tile(
                key: const Key('tile-cleanup'),
                icon: Icons.cleaning_services_outlined,
                title: 'Run clean-up now',
                subtitle: 'Free old holds and mark guests who never came (runs by itself every minute)',
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final r = await ref.read(adminRepositoryProvider).runCleanup();
                    messenger.showSnackBar(SnackBar(content: Text(r.summary)));
                  } on ApiError catch (e) {
                    messenger.showSnackBar(SnackBar(content: Text(e.message)));
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
            const Text('More tools come in the next updates.'),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Tile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
