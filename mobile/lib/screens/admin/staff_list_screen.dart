import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/admin_repository.dart';
import '../../core/api_error.dart';
import '../../models/staff_member.dart';
import '../../widgets/error_banner.dart';
import 'staff_form_screen.dart';
import '../../widgets/angkor_app_bar.dart';

class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  final _busy = <int>{};

  Future<void> _toggle(StaffMember member, bool active) async {
    setState(() => _busy.add(member.id));
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateStaff(member.id, isActive: active);
      ref.invalidate(staffListProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active
                ? '${member.name} can log in again.'
                : '${member.name} is turned off and logged out.',
          ),
        ),
      );
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(member.id));
    }
  }

  Future<void> _open({StaffMember? member}) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => StaffFormScreen(member: member)));
    ref.invalidate(staffListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(staffListProvider);

    return Scaffold(
      appBar: AngkorAppBar(title: 'Staff accounts'),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-staff'),
        onPressed: () => _open(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add staff'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(staffListProvider);
          try {
            await ref.read(staffListProvider.future);
          } catch (_) {}
        },
        child: staff.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ErrorBanner('$error'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => ref.invalidate(staffListProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 48),
                  Icon(Icons.badge_outlined, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No staff yet. Tap "Add staff" to make the first account.',
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final m = list[i];
                return ListTile(
                  key: Key('staff-${m.id}'),
                  leading: CircleAvatar(
                    child: Text(m.name.isEmpty ? '?' : m.name[0].toUpperCase()),
                  ),
                  title: Text(m.name),
                  subtitle: Text(
                    '${m.email}\n${m.isActive ? 'Active' : 'Turned off'}',
                  ),
                  isThreeLine: true,
                  onTap: () => _open(member: m),
                  trailing: Switch(
                    key: Key('switch-${m.id}'),
                    value: m.isActive,
                    onChanged:
                        _busy.contains(m.id) ? null : (v) => _toggle(m, v),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
