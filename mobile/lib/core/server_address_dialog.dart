import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Lets the user type the server address (emulator, USB phone or Wi-Fi).
/// Returns true when a new address was saved.
Future<bool> showServerAddressDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController(text: ref.read(baseUrlProvider));
  final saved = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Server address'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          helperText: 'Emulator: http://10.0.2.2:8000/api\n'
              'Phone on USB: http://127.0.0.1:8000/api\n'
              'Phone on Wi-Fi: http://<PC IP>:8000/api',
          helperMaxLines: 4,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (saved != null && saved.trim().isNotEmpty) {
    await ref.read(baseUrlProvider.notifier).save(saved);
    return true;
  }
  return false;
}
