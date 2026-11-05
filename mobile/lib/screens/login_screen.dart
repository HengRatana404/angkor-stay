import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../core/api_client.dart';
import '../core/api_error.dart';
import '../core/server_address_dialog.dart';
import '../widgets/angkor_logo.dart';
import '../widgets/error_banner.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'verify_email_screen.dart';
import '../core/theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  bool _rememberMe = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final prefs = ref.read(sharedPreferencesProvider);
        final rem = prefs.getBool('remember_me');
        final savedEmail = prefs.getString('saved_email') ?? '';
        if (mounted) {
          setState(() {
            _rememberMe = rem ?? true;
            if (_rememberMe && savedEmail.isNotEmpty) {
              _email.text = savedEmail;
            }
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final email = _email.text.trim();
    try {
      await ref
          .read(authProvider.notifier)
          .login(email: email, password: _password.text);
      try {
        final prefs = ref.read(sharedPreferencesProvider);
        if (_rememberMe) {
          await prefs.setBool('remember_me', true);
          await prefs.setString('saved_email', email);
        } else {
          await prefs.remove('remember_me');
          await prefs.remove('saved_email');
        }
      } catch (_) {}
      // On success the app switches to the home screen by itself.
    } on ApiError catch (e) {
      if (e.code == 'email_not_verified') {
        // The first code may have expired, so ask for a fresh one.
        try {
          await ref.read(authProvider.notifier).resendCode(email);
        } catch (_) {}
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => VerifyEmailScreen(email: email)),
        );
      } else if (e.code == 'outside_hotel_network') {
        if (mounted) {
          setState(
            () => _error =
                'Staff and Admin can only log in on the hotel Wi-Fi.\nPlease tap the gear icon above and select Local Wi-Fi (192.168.123.6).',
          );
        }
      } else {
        if (mounted) setState(() => _error = e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.pal.page,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: const Border(),
        toolbarHeight: 44,
        // The page is light in the light theme, so the clock and icons must be dark there.
        systemOverlayStyle: Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxHeight < 680;
            final logoSize = isCompact ? 52.0 : 86.0;

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 20 : 24,
                vertical: isCompact ? 4 : 12,
              ),
              child: Column(
                children: [
                  // Prominent Top Brand Hero
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onLongPress: () => showServerAddressDialog(
                            context,
                            ref,
                            isStaffOrAdmin: true,
                          ),
                          child: AngkorLogo(size: logoSize),
                        ),
                        SizedBox(height: isCompact ? 8 : 12),
                        Text(
                          'Angkor Stay',
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: isCompact ? 26 : 32,
                            fontWeight: FontWeight.bold,
                            color: context.pal.text,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Hotel in Siem Reap',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.pal.goldDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isCompact ? 14 : 22),
                  // White Card Form
                  Container(
                    padding: EdgeInsets.all(isCompact ? 18 : 22),
                    decoration: BoxDecoration(
                      color: context.pal.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.pal.border, width: 1.2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0C000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Welcome back',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: context.pal.text,
                                ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Log in to book your stay.',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.pal.textMuted,
                            ),
                          ),
                          SizedBox(height: isCompact ? 14 : 18),
                          if (_error != null) ...[
                            ErrorBanner(_error!),
                            const SizedBox(height: 14),
                          ],
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Enter your email'
                                : null,
                          ),
                          SizedBox(height: isCompact ? 12 : 16),
                          TextFormField(
                            controller: _password,
                            obscureText: _hidePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _hidePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword,
                                ),
                              ),
                            ),
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Enter your password'
                                : null,
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: _busy
                                    ? null
                                    : () => setState(
                                          () => _rememberMe = !_rememberMe,
                                        ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Checkbox(
                                      value: _rememberMe,
                                      activeColor: angkorCharcoal,
                                      checkColor: Colors.white,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onChanged: _busy
                                          ? null
                                          : (v) => setState(
                                                () => _rememberMe = v ?? false,
                                              ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Remember me',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: context.pal.text,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                ForgotPasswordScreen(
                                              initialEmail: _email.text.trim(),
                                            ),
                                          ),
                                        ),
                                child: const Text('Forgot password?'),
                              ),
                            ],
                          ),
                          SizedBox(height: isCompact ? 8 : 12),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: _busy
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Log in'),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const RegisterScreen(),
                                      ),
                                    ),
                            child: const Text(
                              "Don't have an account? Register",
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
