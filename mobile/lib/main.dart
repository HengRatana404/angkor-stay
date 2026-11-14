import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_provider.dart';
import 'models/app_user.dart';
import 'core/api_client.dart';
import 'core/auto_refresh.dart';
import 'core/theme.dart';
import 'core/theme_mode_provider.dart';
import 'screens/guest_shell.dart';
import 'widgets/splash_gate.dart';
import 'screens/login_screen.dart';
import 'screens/staff_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandling();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      // No automatic retry: show the error and let the user press Retry.
      retry: (retryCount, error) => null,
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const AngkorStayApp(),
    ),
  );
}

/// One place that catches errors nobody else caught, so the app never just dies silently.
/// (Add a crash-report service here later, for example Crashlytics or Sentry.)
void _installErrorHandling() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    developer.log(
      'Flutter error',
      name: 'angkor_stay',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    developer.log(
      'Unhandled error',
      name: 'angkor_stay',
      error: error,
      stackTrace: stack,
    );
    return true;
  };
  // In the release app a broken widget shows a calm message instead of a grey box.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const Material(
      color: Color(0xFFF3EBDD),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Something went wrong on this screen.\nGo back and try again.',
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 16, color: Color(0xFF2B2118)),
          ),
        ),
      ),
    );
  }
}

class AngkorStayApp extends ConsumerWidget {
  const AngkorStayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Angkor Stay',
      debugShowCheckedModeBanner: false,
      theme: buildAngkorTheme(),
      darkTheme: buildAngkorTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      home: const AutoRefresh(child: SplashGate(child: AuthGate())),
    );
  }
}

/// Decides the first screen: checking, server error, login, or home.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

/// "The server cannot be reached" errors. Not "staff outside the hotel network" or an answer
/// from the server: asking again would give the same answer.
@visibleForTesting
bool isServerDownError(Object error) {
  final text = error.toString();
  return text.contains('Server not reachable') ||
      text.contains('Cannot reach') ||
      text.contains('Connection') ||
      text.contains('timed out') ||
      text.contains('Socket');
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _probing = false;
  bool _autoRecoverAttempted = false;

  /// While the server cannot be reached, ask again every few seconds, so the app
  /// comes back by itself when the server is started again (no need to close the app).
  Timer? _retryTimer;

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // After a trip outside the saved address may be the internet tunnel.
    // Check again on every start so the phone goes back to hotel Wi-Fi.
    if (ref.read(baseUrlProvider) !=
        savedLanUrl(ref.read(sharedPreferencesProvider))) {
      Future.microtask(() async {
        try {
          final best = await detectBestServer();
          if (best != ref.read(baseUrlProvider)) {
            await ref.read(baseUrlProvider.notifier).save(best);
          }
        } catch (_) {}
      });
    }
  }

  void _triggerAutoRecover() async {
    if (_probing) return;
    setState(() => _probing = true);
    try {
      await ref.read(baseUrlProvider.notifier).autoDetect();
      ref.invalidate(authProvider);
    } catch (_) {}
    if (mounted) setState(() => _probing = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    ref.listen<AsyncValue<AppUser?>>(authProvider, (_, next) {
      if (next.isLoading) return; // a retry is running: keep the timer as it is
      if (next.hasError && isServerDownError(next.error!)) {
        _retryTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
          if (mounted && !_probing) ref.invalidate(authProvider);
        });
      } else {
        _retryTimer?.cancel();
        _retryTimer = null;
      }
    });

    return auth.when(
      loading: () => Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: context.pal.accent),
        ),
      ),
      error: (error, _) {
        final errText = error.toString();
        final isOutsideHotel =
            errText.contains('hotel network') ||
            errText.contains('outside_hotel_network');
        final isNetworkInterrupt =
            !isOutsideHotel &&
            (errText.contains('Cannot reach') ||
                errText.contains('Connection') ||
                errText.contains('timed out') ||
                errText.contains('Socket'));

        // Automatically probe & reconnect once when network is interrupted:
        if (isNetworkInterrupt && !_probing && !_autoRecoverAttempted) {
          _autoRecoverAttempted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_probing && mounted) {
              _triggerAutoRecover();
            }
          });
        }

        final titleText = isOutsideHotel
            ? 'Hotel Wi-Fi Required'
            : 'Connection Issue';
        final descText = _probing
            ? 'Auto-detecting server & reconnecting...'
            : isOutsideHotel
            ? '$error\n\nStaff and admin can only use the app on the hotel network. Switch to hotel Wi-Fi, or log out to browse as Guest.'
            : '$error';

        final pal = context.pal;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return Scaffold(
          appBar: AppBar(title: const Text('Angkor Stay')),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isOutsideHotel ? pal.dangerWash : pal.goldWash,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOutsideHotel
                          ? Icons.wifi_off_rounded
                          : Icons.sync_problem,
                      size: 48,
                      color: isOutsideHotel ? pal.danger : pal.goldDeep,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    titleText,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: pal.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    descText,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: pal.textMuted),
                  ),
                  const SizedBox(height: 20),
                  if (_probing) ...[
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: pal.accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    // Light: the dark pill. Dark: the app's action button (a dark pill would melt into the page).
                    style: FilledButton.styleFrom(
                      backgroundColor: dark ? pal.action : pal.strong,
                      foregroundColor: dark ? pal.onAction : pal.onStrong,
                    ),
                    icon: const Icon(Icons.travel_explore, size: 16),
                    label: const Text('Auto-Detect Server & Reconnect'),
                    onPressed: _probing ? null : _triggerAutoRecover,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _probing
                        ? null
                        : () {
                            setState(() => _autoRecoverAttempted = false);
                            ref.invalidate(authProvider);
                          },
                    child: const Text('Retry'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () =>
                        ref.read(authProvider.notifier).logoutLocal(),
                    child: const Text('Log out on this phone'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      data: (user) {
        if (user == null) return const LoginScreen();
        // Customers book rooms. Staff and admin have their own home page.
        return user.isCustomer
            ? GuestShell(user: user)
            : StaffHomeScreen(user: user);
      },
    );
  }
}
