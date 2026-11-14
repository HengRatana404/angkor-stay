import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin/admin_repository.dart';
import '../booking/booking_repository.dart';
import '../rooms/room_types_provider.dart';
import '../staff/staff_booking_repository.dart';
import 'api_client.dart';

/// Keeps the screens fresh without pull-to-refresh: every few seconds while
/// the app is open and signed in, and again when the app comes back to the front.
/// A screen that is not open is not fetched (those providers are auto-dispose).
class AutoRefresh extends ConsumerStatefulWidget {
  final Widget child;
  final Duration every;
  const AutoRefresh({
    super.key,
    required this.child,
    this.every = const Duration(seconds: 15),
  });

  @override
  ConsumerState<AutoRefresh> createState() => _AutoRefreshState();
}

class _AutoRefreshState extends ConsumerState<AutoRefresh>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.every, (_) => _refresh());
  }

  void _refresh() {
    if (!mounted || ref.read(authTokenProvider) == null) return;
    ref.invalidate(myBookingsProvider);
    ref.invalidate(roomTypesProvider);
    ref.invalidate(staffBookingsProvider);
    ref.invalidate(staffBookingProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(adminRoomTypesProvider);
    ref.invalidate(staffListProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _start();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
