import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../core/api_error.dart';
import '../widgets/error_banner.dart';

/// The guest changes their name, phone or password. Email cannot be changed.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final _name = TextEditingController(text: ref.read(authProvider).value?.name ?? '');
  late final _phone = TextEditingController(text: ref.read(authProvider).value?.phone ?? '');
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _done;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in [_name, _phone, _current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String doneText) async {
    setState(() {
      _busy = true;
      _error = null;
      _done = null;
      _fieldErrors = {};
    });
    try {
      await action();
      if (mounted) setState(() => _done = doneText);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _fieldErrors = e.fieldErrors;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveProfile() => _run(
        () => ref.read(authProvider.notifier).updateProfile(
              name: _name.text.trim(),
              phone: _phone.text.trim(),
            ),
        'Saved.',
      );

  Future<void> _savePassword() => _run(() async {
        await ref.read(authProvider.notifier).changePassword(
              current: _current.text,
              password: _new.text,
              confirmation: _confirm.text,
            );
        _current.clear();
        _new.clear();
        _confirm.clear();
      }, 'Your password was changed.');

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(user?.email ?? '', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: 'Name', errorText: _fieldErrors['name']),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'Phone', errorText: _fieldErrors['phone']),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _saveProfile,
            child: const Text('Save profile'),
          ),
          const Divider(height: 48),
          Text('Change password', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _current,
            obscureText: true,
            decoration: InputDecoration(
                labelText: 'Current password', errorText: _fieldErrors['current_password']),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _new,
            obscureText: true,
            decoration: InputDecoration(
                labelText: 'New password (8+ characters)', errorText: _fieldErrors['password']),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password again'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _busy ? null : _savePassword,
            child: const Text('Change password'),
          ),
          if (_error != null) ...[const SizedBox(height: 16), ErrorBanner(_error!)],
          if (_done != null) ...[
            const SizedBox(height: 16),
            Text(_done!, style: const TextStyle(color: Colors.green)),
          ],
        ],
      ),
    );
  }
}
