import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../core/api_client.dart';
import '../core/api_error.dart';
import '../core/server_address_dialog.dart';
import '../widgets/angkor_logo.dart';
import '../widgets/error_banner.dart';
import '../core/theme.dart';
import '../core/theme_mode_provider.dart';
import '../core/format.dart';
import '../widgets/angkor_app_bar.dart';

/// The guest changes their name, phone or password. Email cannot be changed.
/// Staff and admin can only change their password: the admin manages their name
/// and sets a new password when they forget it (they have no real inbox for a code).
class ProfileScreen extends ConsumerStatefulWidget {
  /// True when shown as a tab inside the guest shell (no back arrow).
  final bool embedded;
  const ProfileScreen({super.key, this.embedded = false});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _done;
  Map<String, String> _fieldErrors = {};

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).value;
    _name = TextEditingController(text: user?.name ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
  }

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
        () => ref
            .read(authProvider.notifier)
            .updateProfile(name: _name.text.trim(), phone: _phone.text.trim()),
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

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Log out',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to log out of Angkor Stay?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.pal.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(authProvider.notifier).logout();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    final isGuest = user == null || user.role == 'customer';
    final health = ref.watch(healthProvider);
    final baseUrl = ref.watch(baseUrlProvider);

    final initial =
        (user?.name.isNotEmpty == true ? user!.name[0] : 'U').toUpperCase();

    return Scaffold(
        appBar: AngkorAppBar(title: 'My Profile', showBack: !widget.embedded),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.pal.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.pal.border, width: 1.2),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0A000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CircleAvatar(
                        radius: 38,
                        backgroundColor: context.pal.strong,
                        child: Text(
                          initial,
                          style: TextStyle(
                            color: context.pal.accent,
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'serif',
                          ),
                        ),
                      ),
                      const Positioned(
                        bottom: 0,
                        right: 0,
                        child: AngkorLogo(size: 24),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!isGuest)
                    Text(
                      user.name,
                      key: const Key('staff-name'),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.pal.text,
                      ),
                    )
                  else
                    Text(
                      user?.name ?? 'Guest User',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.pal.text,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    user?.email ?? '',
                    style: TextStyle(color: context.pal.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: context.pal.strong,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isGuest ? 'VIP guest' : titleCase(user.role),
                      style: TextStyle(
                        color: context.pal.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (!isGuest) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Your name is set by the admin.',
                      style: TextStyle(
                        color: context.pal.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (isGuest) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.pal.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.pal.border, width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personal Information',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: context.pal.text,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        errorText: _fieldErrors['name'],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone',
                        errorText: _fieldErrors['phone'],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _saveProfile,
                        style: FilledButton.styleFrom(
                          backgroundColor: context.pal.action,
                          foregroundColor: context.pal.onAction,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Save profile'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            const _AppearanceCard(),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.pal.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.pal.border, width: 1.2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Change password',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: context.pal.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _current,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Current password',
                      errorText: _fieldErrors['current_password'],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _new,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'New password (8+ characters)',
                      errorText: _fieldErrors['password'],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password again',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _savePassword,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.pal.text,
                        side: BorderSide(
                          color: context.pal.text,
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Change password'),
                    ),
                  ),
                  if (!isGuest) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Forgot your password? Ask the admin to set a new one.',
                      key: const Key('staff-forgot-note'),
                      style: TextStyle(
                        color: context.pal.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              ErrorBanner(_error!),
            ],
            if (_done != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.pal.successWash,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.pal.successBorder),
                ),
                child: Text(
                  _done!,
                  style: TextStyle(
                    color: context.pal.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Card(
              margin: EdgeInsets.zero,
              color: context.pal.surface,
              elevation: 0.5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: context.pal.border, width: 1.2),
              ),
              child: Column(
                children: [
                  if (user != null &&
                      (user.role == 'admin' || user.role == 'staff')) ...[
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: context.pal.goldWash,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.pal.goldSoft),
                        ),
                        child: Icon(
                          Icons.settings_ethernet,
                          color: context.pal.accent,
                          size: 20,
                        ),
                      ),
                      title: Row(
                        children: [
                          const Text(
                            'Network & Server',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: health.maybeWhen(
                                data: (h) => h.ok ? Colors.green : context.pal.danger,
                                orElse: () => Colors.amber,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            health.maybeWhen(
                              data: (h) => h.ok ? 'Connected' : 'Offline',
                              orElse: () => '...',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: health.maybeWhen(
                                data: (h) => h.ok
                                    ? context.pal.success
                                    : context.pal.danger,
                                orElse: () => Colors.amber.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        baseUrl,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.pal.textMuted,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: context.pal.accent,
                      ),
                      onTap: () async {
                        if (await showServerAddressDialog(
                          context,
                          ref,
                          isStaffOrAdmin: true,
                        )) {
                          ref.invalidate(healthProvider);
                        }
                      },
                    ),
                    const Divider(height: 1, indent: 56),
                  ],
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: context.pal.dangerWash,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.pal.dangerBorder),
                      ),
                      child: Icon(
                        Icons.logout,
                        color: context.pal.danger,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      'Log out',
                      style: TextStyle(
                        color: context.pal.danger,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: const Text(
                      'Sign out of your account on this device',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: context.pal.danger,
                    ),
                    onTap: _logout,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
  }
}


/// Choose light, dark, or follow the phone.
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.pal.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.pal.border, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Appearance',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: context.pal.text,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              key: const Key('theme-mode'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {mode},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
        ],
      ),
    );
  }
}
