import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../booking/stay_provider.dart';
import '../models/app_user.dart';
import '../widgets/motion.dart';
import '../rooms/room_types_provider.dart';
import 'home_screen.dart';
import 'my_bookings_screen.dart';
import 'profile_screen.dart';

/// The guest's main frame: three tabs (Home, Bookings, Profile) and one
/// navigation bar that stays visible. System Back on another tab goes to Home first.
class GuestShell extends ConsumerStatefulWidget {
  final AppUser user;
  const GuestShell({super.key, required this.user});

  @override
  ConsumerState<GuestShell> createState() => _GuestShellState();
}

class _GuestShellState extends ConsumerState<GuestShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const double _maxContentWidth = 640;
  int _index = 0;
  // A tab is built the first time it is opened, then kept alive.
  final _opened = <int>{0};

  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fade.dispose();
    super.dispose();
  }

  /// Coming back to the app (maybe the next day): fix old dates, reload "rooms left".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshRooms();
  }

  void _refreshRooms() {
    ref.read(stayProvider.notifier).refreshIfStale();
    ref.invalidate(roomTypesProvider);
  }

  void _select(int i) {
    // A booking may have been cancelled or paid on another tab: reload the room counts.
    if (i == 0 && _index != 0) _refreshRooms();
    setState(() {
      _index = i;
      _opened.add(i);
    });
    // A short fade and lift so switching tabs does not just blink.
    if (!reduceMotion(context)) _fade.forward(from: 0);
  }

  Widget _tab(int i) {
    if (!_opened.contains(i)) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return HomeScreen(user: widget.user);
      case 1:
        return const MyBookingsScreen(embedded: true);
      default:
        return const ProfileScreen(embedded: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        // On a tablet or a wide window the phone layout stays a readable width.
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _fade, curve: appearCurve),
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.015),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: _fade, curve: appearCurve)),
                child: IndexedStack(
                  index: _index,
                  children: [for (var i = 0; i < 3; i++) _tab(i)],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              decoration: BoxDecoration(
                color: context.pal.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: context.pal.border, width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: NavigationBar(
                  backgroundColor: context.pal.surface,
                  indicatorColor: context.pal.accent,
                  indicatorShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  selectedIndex: _index,
                  elevation: 0,
                  height: 64,
                  onDestinationSelected: _select,
                  destinations: [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(
                        Icons.home,
                        color: context.pal.onAccent,
                      ),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(
                        Icons.receipt_long,
                        color: context.pal.onAccent,
                      ),
                      label: 'Bookings',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.person_outline),
                      selectedIcon: Icon(
                        Icons.person,
                        color: context.pal.onAccent,
                      ),
                      label: 'Profile',
                    ),
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
