import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../models/app_user.dart';
import '../rooms/room_types_provider.dart';
import '../widgets/error_banner.dart';
import '../widgets/room_type_card.dart';
import '../core/theme.dart';
import '../widgets/motion.dart';
import '../widgets/angkor_app_bar.dart';
import '../widgets/notifications_sheet.dart';

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

    return Scaffold(
      appBar: AngkorAppBar(
        title: 'Angkor Stay',
        showLogo: true,
        showBack: false,
        actions: [const NotificationBell()],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, ${user.name}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: context.pal.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Welcome to Siem Reap',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.pal.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Only shown when the connection is down.
              if (health.maybeWhen(data: (h) => !h.ok, orElse: () => false))
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: context.pal.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.pal.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: health.maybeWhen(
                              data: (h) =>
                                  h.ok ? Colors.green : context.pal.danger,
                              orElse: () => Colors.amber,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          health.maybeWhen(
                            data: (h) => h.ok ? 'Online' : 'Offline',
                            orElse: () => 'Connecting...',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.pal.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 20),
              Text(
                'Our rooms',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold, fontSize: 20),
              ),
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
                    : Column(
                        children: [
                          for (final (i, t) in list.indexed)
                            FadeSlideIn(
                              index: i,
                              child: RoomTypeCard(roomType: t),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
