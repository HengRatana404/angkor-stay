import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin/admin_repository.dart';
import '../core/api_client.dart';
import '../core/api_error.dart';
import '../core/format.dart';
import '../models/app_user.dart';
import '../models/dashboard.dart';
import '../models/staff_booking.dart';
import '../staff/staff_booking_repository.dart';
import 'admin/dashboard_screen.dart';
import 'admin/room_types_screen.dart';
import 'admin/settings_screen.dart';
import 'admin/staff_list_screen.dart';
import 'profile_screen.dart';
import 'staff/qr_scanner_screen.dart';
import 'staff/staff_bookings_screen.dart';
import '../core/theme.dart';
import '../widgets/angkor_app_bar.dart';
import '../widgets/motion.dart';
import '../widgets/top_message.dart';

/// The modern luxury home page for staff and admin.
class StaffHomeScreen extends ConsumerWidget {
  final AppUser user;
  const StaffHomeScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);
    final dashboard = user.isAdmin ? ref.watch(dashboardProvider) : null;
    final staffBookings = user.role == 'staff'
        ? ref.watch(staffBookingsProvider)
        : null;

    return Scaffold(
      appBar: AngkorAppBar(
        title: 'Angkor Stay',
        showLogo: true,
        showBack: false,
        actions: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              ),
              child: Tooltip(
                message: 'My profile',
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0x28F4EEE4),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0x55F4EEE4),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    Icons.person,
                    color: context.pal.onStrong,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      // The main job at the desk, always in reach of the thumb.
      bottomNavigationBar: user.role == 'staff'
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: FilledButton.icon(
                  key: const Key('staff-home-scan-fab'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const QrScannerScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan guest QR'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(healthProvider);
          if (user.isAdmin) {
            ref.invalidate(dashboardProvider);
          } else {
            ref.invalidate(staffBookingsProvider);
          }
        },
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
            // At least as tall as the screen, so the free space is spread out
            // instead of being left as a blank band at the bottom.
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 12),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // User Greeting & Role Badge
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
                                user.email,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.pal.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: context.pal.strong,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            titleCase(user.role),
                            style: TextStyle(
                              color: context.pal.onStrong,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Only shown when the connection is down.
                    if (health.maybeWhen(
                      data: (h) => !h.ok,
                      orElse: () => false,
                    )) ...[
                      const SizedBox(height: 10),
                      Container(
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
                                data: (h) =>
                                    h.ok ? 'Connected' : 'Not connected',
                                orElse: () => 'Checking...',
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
                    ],
                    const SizedBox(height: 12),

                    // ================= STAFF FRONT DESK VIEW =================
                    if (user.role == 'staff') ...[
                      // Front Desk Shift Pulse Counters
                      _StaffPulseCard(
                        bookings: staffBookings?.value ?? const [],
                        onOpenBookings: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const StaffBookingsScreen(),
                          ),
                        ),
                        onOpenWithFilter: (status) {
                          ref
                              .read(bookingFilterProvider.notifier)
                              .setStatus(status);
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const StaffBookingsScreen(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      const _GroupTitle('Front desk'),
                      _AdminGroup(
                        children: [
                          _AdminRow(
                            key: const Key('tile-bookings'),
                            icon: Icons.event_note_outlined,
                            title: 'Bookings',
                            subtitle:
                                'Find a guest, take payment, check in and out',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const StaffBookingsScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // ================= ADMIN MANAGEMENT VIEW =================
                    if (user.isAdmin) ...[
                      _AdminPulseCard(dashboard: dashboard?.value),
                      const Spacer(),
                      const _GroupTitle('Manage'),
                      _AdminGroup(
                        children: [
                          _AdminRow(
                            key: const Key('tile-bookings'),
                            icon: Icons.event_note_outlined,
                            title: 'Bookings',
                            subtitle: 'Guests, reservations and payments',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const StaffBookingsScreen(),
                              ),
                            ),
                          ),
                          _AdminRow(
                            key: const Key('tile-staff'),
                            icon: Icons.badge_outlined,
                            title: 'Staff accounts',
                            subtitle: 'Add staff, turn accounts on or off',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const StaffListScreen(),
                              ),
                            ),
                          ),
                          _AdminRow(
                            key: const Key('tile-rooms'),
                            icon: Icons.bed_outlined,
                            title: 'Rooms and prices',
                            subtitle: 'Room types, prices and photos',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const RoomTypesScreen(),
                              ),
                            ),
                          ),
                          _AdminRow(
                            key: const Key('tile-settings'),
                            icon: Icons.tune,
                            title: 'Hotel settings',
                            subtitle: 'Discount and check-in times',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const SettingsScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const _GroupTitle('Reports and upkeep'),
                      _AdminGroup(
                        children: [
                          _AdminRow(
                            key: const Key('tile-dashboard'),
                            icon: Icons.insights_outlined,
                            title: 'Dashboard',
                            subtitle: 'Today, rooms, money and unpaid bookings',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const DashboardScreen(),
                              ),
                            ),
                          ),
                          _AdminRow(
                            key: const Key('tile-cleanup'),
                            icon: Icons.cleaning_services_outlined,
                            title: 'Release unpaid holds',
                            subtitle:
                                'Also marks guests who never came as no-shows',
                            onTap: () async {
                              final top = TopMessage.of(context);
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Release unpaid holds?'),
                                  content: const Text(
                                    'This frees rooms held for unpaid bookings. It also marks guests who '
                                    'never arrived as no-shows and refunds their online payments. '
                                    'It cannot be undone.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Not now'),
                                    ),
                                    FilledButton(
                                      key: const Key('confirm-cleanup'),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Run clean-up'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok != true) return;
                              try {
                                final r = await ref
                                    .read(adminRepositoryProvider)
                                    .runCleanup();
                                top.show(r.summary);
                              } on ApiError catch (e) {
                                top.show(e.message, error: true);
                              }
                            },
                          ),
                        ],
                      ),
                      const Spacer(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _count(int n, String one, [String? many]) =>
    n == 1 ? '1 $one' : '$n ${many ?? '${one}s'}';

/// What the receptionist needs right now: one plain sentence and four tappable counts.
class _StaffPulseCard extends StatelessWidget {
  final List<StaffBooking> bookings;
  final VoidCallback onOpenBookings;
  final void Function(String? status) onOpenWithFilter;

  const _StaffPulseCard({
    required this.bookings,
    required this.onOpenBookings,
    required this.onOpenWithFilter,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final arrivals = bookings
        .where((b) => b.actions.canCheckIn || b.status == 'confirmed')
        .length;
    final inHouse = bookings.where((b) => b.status == 'checked_in').length;
    final departures = bookings.where((b) => b.actions.canCheckOut).length;
    final unpaid = bookings
        .where(
          (b) => !b.paid && b.status != 'cancelled' && b.status != 'no_show',
        )
        .length;

    final sentence = arrivals + departures + unpaid == 0
        ? 'Nothing is waiting right now.'
        : '${_count(arrivals, 'guest')} to check in, ${_count(departures, 'guest')} to check out.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sentence,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: pal.text,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CountChip(
              label: 'To check in',
              count: arrivals,
              onTap: () => onOpenWithFilter('confirmed'),
            ),
            _CountChip(
              label: 'In the hotel',
              count: inHouse,
              onTap: () => onOpenWithFilter('checked_in'),
            ),
            _CountChip(
              label: 'To check out',
              count: departures,
              onTap: () => onOpenWithFilter('checked_in'),
            ),
            _CountChip(
              label: 'Unpaid',
              count: unpaid,
              onTap: () => onOpenWithFilter('pending'),
            ),
          ],
        ),
      ],
    );
  }
}

/// A tappable count: the number, then what it counts.
class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback onTap;
  const _CountChip({
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Material(
      color: pal.surface,
      shape: StadiumBorder(side: BorderSide(color: pal.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: pal.text,
                ),
              ),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(fontSize: 13, color: pal.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Today for the admin: one plain sentence and how full the hotel is.
class _AdminPulseCard extends StatelessWidget {
  final Dashboard? dashboard;
  const _AdminPulseCard({this.dashboard});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final d = dashboard;
    final occupied = d?.roomsOccupied ?? 0;
    final total = d?.roomsTotal ?? 15;
    final free = d?.roomsFree ?? (total - occupied);
    final fraction = total > 0 ? (occupied / total).clamp(0.0, 1.0) : 0.0;

    final sentence = d == null
        ? 'Loading today…'
        : 'Today: ${_count(d.checkIns, 'arrival')}, ${_count(d.checkOuts, 'departure')}, '
              '$free ${free == 1 ? 'room' : 'rooms'} free.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sentence,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: pal.text,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        TweenAnimationBuilder<double>(
          tween: Tween(end: fraction),
          duration: reduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Container(
            height: 8,
            decoration: BoxDecoration(
              color: pal.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: pal.border),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: v,
              child: ColoredBox(
                color: context.pal.accent,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                (d != null && d.roomsMaintenance > 0)
                    ? '$occupied of $total in use · ${d.roomsMaintenance} in maintenance'
                    : '$occupied of $total rooms in use',
                style: TextStyle(fontSize: 13, color: pal.textMuted),
              ),
            ),
            Text(
              'Taken today ${formatMoney(d?.moneyToday ?? 0)}',
              style: TextStyle(fontSize: 13, color: pal.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

/// A small section title above a group of rows.
class _GroupTitle extends StatelessWidget {
  final String text;
  const _GroupTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: context.pal.text,
      ),
    ),
  );
}

/// Rows in one rounded box, separated by thin lines.
class _AdminGroup extends StatelessWidget {
  final List<Widget> children;
  const _AdminGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: pal.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 70, color: pal.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One tappable row: icon, title, one line of help, chevron.
class _AdminRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: pal.goldWash,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 22, color: pal.goldDeep),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: pal.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: pal.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: pal.textMuted),
          ],
        ),
      ),
    );
  }
}
