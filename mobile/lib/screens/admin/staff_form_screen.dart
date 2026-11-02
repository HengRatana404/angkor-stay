import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/admin_repository.dart';
import '../../core/api_error.dart';
import '../../models/staff_member.dart';
import '../../widgets/error_banner.dart';

/// Add a staff member, or (when [member] is given) change one.
class StaffFormScreen extends ConsumerStatefulWidget {
  final StaffMember? member;
  const StaffFormScreen({super.key, this.member});

  @override
  ConsumerState<StaffFormScreen> createState() => _StaffFormScreenState();
}

class _StaffFormScreenState extends ConsumerState<StaffFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.member?.name ?? '');
  late final _email = TextEditingController(text: widget.member?.email ?? '');
  late final _phone = TextEditingController(text: widget.member?.phone ?? '');
  final _password = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;
  Map<String, String> _serverErrors = {};

  bool get _editing => widget.member != null;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _server(String field) => _serverErrors[field];

  Future<void> _save() async {
    setState(() => _serverErrors = {});
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final repo = ref.read(adminRepositoryProvider);
    try {
      if (_editing) {
        await repo.updateStaff(
          widget.member!.id,
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          password: _password.text.isEmpty ? null : _password.text,
        );
      } else {
        await repo.createStaff(
          name: _name.text.trim(),
          email: _email.text.trim(),
          phone: _phone.text.trim(),
          password: _password.text,
        );
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: Text(_editing ? 'Staff account saved.' : 'Staff account made. They can log in now.'),
      ));
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _serverErrors = e.fieldErrors;
        _error = e.fieldErrors.isEmpty ? e.message : null;
      });
      _formKey.currentState!.validate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Staff account' : 'Add staff')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[ErrorBanner(_error!), const SizedBox(height: 16)],
                TextFormField(
                  key: const Key('staff-name'),
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : _server('name'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('staff-email'),
                  controller: _email,
                  enabled: !_editing,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.email_outlined),
                    helperText: _editing ? 'The email cannot be changed' : 'Used to log in',
                  ),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Enter a valid email' : _server('email'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('staff-phone'),
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().length < 8)
                      ? 'Enter a phone number'
                      : _server('phone'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('staff-password'),
                  controller: _password,
                  obscureText: _hide,
                  decoration: InputDecoration(
                    labelText: _editing ? 'New password (leave empty to keep)' : 'Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: _editing
                        ? 'Setting a new password logs this person out everywhere'
                        : 'At least 8 characters. Tell it to the staff member.',
                    helperMaxLines: 2,
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  validator: (v) {
                    final text = v ?? '';
                    if (_editing && text.isEmpty) return _server('password');
                    if (text.length < 8) return 'At least 8 characters';
                    return _server('password');
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('staff-save'),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_editing ? 'Save' : 'Make account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
