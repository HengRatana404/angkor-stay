import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_provider.dart';
import 'core/api_client.dart';
import 'core/server_address_dialog.dart';
import 'core/theme.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/staff_home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class AngkorStayApp extends StatelessWidget {
  const AngkorStayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Angkor Stay',
      debugShowCheckedModeBanner: false,
      theme: buildAngkorTheme(),
      home: const AuthGate(),
    );
  }
}

/// Decides the first screen: checking, server error, login, or home.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return auth.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Angkor Stay')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 64),
                const SizedBox(height: 16),
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(authProvider),
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: () async {
                    if (await showServerAddressDialog(context, ref)) {
                      ref.invalidate(authProvider);
                    }
                  },
                  child: const Text('Change server address'),
                ),
                TextButton(
                  onPressed: () => ref.read(authProvider.notifier).logoutLocal(),
                  child: const Text('Log out on this phone'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (user) {
        if (user == null) return const LoginScreen();
        // Customers book rooms. Staff and admin have their own home page.
        return user.isCustomer ? HomeScreen(user: user) : StaffHomeScreen(user: user);
      },
    );
  }
}
