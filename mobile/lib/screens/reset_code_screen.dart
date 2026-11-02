import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../core/api_error.dart';
import '../widgets/error_banner.dart';
import 'new_password_screen.dart';

class ResetCodeScreen extends ConsumerStatefulWidget {
  final String email;
  const ResetCodeScreen({super.key, required this.email});

  @override
  ConsumerState<ResetCodeScreen> createState() => _ResetCodeScreenState();
}

class _ResetCodeScreenState extends ConsumerState<ResetCodeScreen> {
  static const _resendSeconds = 60;

  final _code = TextEditingController();
  Timer? _timer;
  int _wait = _resendSeconds;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _wait = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });

    try {
      await ref
          .read(authProvider.notifier)
          .checkResetCode(email: widget.email, code: code);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NewPasswordScreen(email: widget.email, code: code),
        ),
      );
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await ref.read(authProvider.notifier).forgotPassword(widget.email);
      if (!mounted) return;
      setState(() => _info = 'A new code was sent.');
      _startCountdown();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter the code')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.mark_email_read_outlined, size: 64),
              const SizedBox(height: 16),
              Text(
                'If ${widget.email} has an account,\nwe sent it a 6-digit code.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
              if (_info != null) ...[
                Text(_info!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 28, letterSpacing: 8),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  counterText: '',
                  hintText: '------',
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _verify,
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Verify code'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _wait > 0 || _busy ? null : _resend,
                child: Text(_wait > 0 ? 'Send a new code in ${_wait}s' : 'Send a new code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
