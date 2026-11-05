import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_provider.dart';
import 'core/api_client.dart';
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
      home: const SplashGate(child: AuthGate()),
    );
  }
}

/// Decides the first screen: checking, server error, login, or home.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    // After a trip outside the saved address may be the internet tunnel.
    // Check again on every start so the phone goes back to hotel Wi-Fi.
    if (ref.read(baseUrlProvider) != defaultBaseUrl) {
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

    return auth.when(
      loading: () => const Scaffold(
        backgroundColor: Color(0xFFF9F6F0),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF926A1A)),
        ),
      ),
      error: (error, _) {
        final errText = error.toString();
        final isNetworkInterrupt =
            errText.contains('Cannot reach') ||
            errText.contains('Connection') ||
            errText.contains('timed out') ||
            errText.contains('Network') ||
            errText.contains('Socket');

        // Automatically probe & reconnect when network is interrupted:
        if (isNetworkInterrupt && !_probing) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_probing && mounted) {
              _triggerAutoRecover();
            }
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF9F6F0),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('Angkor Stay'),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEF3C7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.sync_problem,
                      size: 48,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Network Reconnecting',
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF241C16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _probing
                        ? 'Auto-detecting server & reconnecting...'
                        : '$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  if (_probing)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF926A1A),
                      ),
                    )
                  else ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF241C16),
                      ),
                      icon: const Icon(Icons.travel_explore, size: 16),
                      label: const Text('Auto-Detect Server & Reconnect'),
                      onPressed: _triggerAutoRecover,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(authProvider),
                      child: const Text('Retry'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          ref.read(authProvider.notifier).logoutLocal(),
                      child: const Text('Log out on this phone'),
                    ),
                  ],
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
