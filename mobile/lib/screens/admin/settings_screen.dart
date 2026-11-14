import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/admin_repository.dart';
import '../../core/api_error.dart';
import '../../models/hotel_settings.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/angkor_app_bar.dart';
import '../../widgets/top_message.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(hotelSettingsProvider);

    return Scaffold(
      appBar: AngkorAppBar(title: 'Hotel settings'),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ErrorBanner('$error'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => ref.invalidate(hotelSettingsProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
        data: (r) => SettingsForm(initial: r.settings, yourIp: r.yourIp),
      ),
    );
  }
}

class SettingsForm extends ConsumerStatefulWidget {
  final HotelSettings initial;
  final String yourIp;
  const SettingsForm({super.key, required this.initial, required this.yourIp});

  @override
  ConsumerState<SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<SettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final _discount = TextEditingController(
    text: '${widget.initial.onlineDiscountPercent}',
  );
  late final _networks = TextEditingController(
    text: widget.initial.allowedNetworks.join('\n'),
  );
  late String _checkIn = widget.initial.checkInTime;
  late String _checkOut = widget.initial.checkOutTime;
  late bool _restricted = widget.initial.staffLoginRestricted;

  bool _busy = false;
  String? _error;
  Map<String, String> _serverErrors = {};

  @override
  void dispose() {
    _discount.dispose();
    _networks.dispose();
    super.dispose();
  }

  /// The first server message about a field, such as "allowed_networks.1".
  String? _server(String field) {
    for (final e in _serverErrors.entries) {
      if (e.key == field || e.key.startsWith('$field.')) return e.value;
    }
    return null;
  }

  List<String> get _networkLines => _networks.text
      .split(RegExp(r'[\n,]'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  String _two(int n) => n.toString().padLeft(2, '0');

  Future<void> _pickTime({required bool checkIn}) async {
    final current = (checkIn ? _checkIn : _checkOut).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(current[0]),
        minute: int.parse(current[1]),
      ),
      helpText: checkIn ? 'Check-in time' : 'Check-out time',
    );
    if (picked == null) return;
    final text = '${_two(picked.hour)}:${_two(picked.minute)}';
    setState(() => checkIn ? _checkIn = text : _checkOut = text);
  }

  void _addThisDevice() {
    final mine = networkForIp(widget.yourIp);
    if (!_networkLines.contains(mine)) {
      final text = _networks.text.trimRight();
      setState(() => _networks.text = text.isEmpty ? mine : '$text\n$mine');
    }
  }

  Future<void> _save() async {
    setState(() => _serverErrors = {});
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final settings = HotelSettings(
      onlineDiscountPercent: int.parse(_discount.text.trim()),
      checkInTime: _checkIn,
      checkOutTime: _checkOut,
      staffLoginRestricted: _restricted,
      allowedNetworks: _networkLines,
    );

    try {
      await ref.read(adminRepositoryProvider).saveSettings(settings);
      ref.invalidate(hotelSettingsProvider);
      if (!mounted) return;
      TopMessage.of(context).show('Settings saved.');
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
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (_error != null) ...[
            ErrorBanner(_error!),
            const SizedBox(height: 16),
          ],
          Text('Online payment', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('discount'),
            controller: _discount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Discount when paying online',
              suffixText: '%',
              border: OutlineInputBorder(),
              helperText: 'From 0 to 50. Paying at the hotel has no discount.',
            ),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              if (n == null || n < 0 || n > 50) {
                return 'Enter a whole number from 0 to 50';
              }
              return _server('online_discount_percent');
            },
          ),
          const Divider(height: 32),
          Text('Times', style: theme.textTheme.titleMedium),
          ListTile(
            key: const Key('check-in-time'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.login),
            title: const Text('Check-in'),
            trailing: Text(_checkIn, style: theme.textTheme.titleMedium),
            onTap: () => _pickTime(checkIn: true),
          ),
          ListTile(
            key: const Key('check-out-time'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: const Text('Check-out'),
            trailing: Text(_checkOut, style: theme.textTheme.titleMedium),
            onTap: () => _pickTime(checkIn: false),
          ),
          const Divider(height: 32),
          Text('Staff and admin network', style: theme.textTheme.titleMedium),
          SwitchListTile(
            key: const Key('restricted'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Only on the hotel network'),
            subtitle: const Text(
              'Staff and admin cannot log in or work outside it. Customers are not affected.',
            ),
            value: _restricted,
            onChanged: (v) => setState(() => _restricted = v),
          ),
          if (_restricted) ...[
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('networks'),
              controller: _networks,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Allowed networks (one per line)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                helperText: 'Example: 192.168.1.0/24',
              ),
              validator: (v) {
                if (_networkLines.isEmpty) return 'Add at least one network';
                return _server('allowed_networks');
              },
            ),
            const SizedBox(height: 8),
            Text(
              'This device connects from ${widget.yourIp}',
              key: const Key('your-ip'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('add-this-device'),
              onPressed: widget.yourIp.isEmpty ? null : _addThisDevice,
              icon: const Icon(Icons.wifi),
              label: Text(
                "Add this device's network (${networkForIp(widget.yourIp)})",
              ),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('settings-save'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save settings'),
          ),
        ],
      ),
    );
  }
}
