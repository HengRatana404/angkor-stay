import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

/// Lets the user type the server address (emulator, USB phone or Wi-Fi).
/// Returns true when a new address was saved.
Future<bool> showServerAddressDialog(
  BuildContext context,
  WidgetRef ref, {
  bool isStaffOrAdmin = false,
}) async {
  final controller = TextEditingController(text: ref.read(baseUrlProvider));
  final saved = await showDialog<String>(
    context: context,
    builder: (ctx) {
      bool probing = false;
      String? probeStatus;

      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Server address'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'API URL',
                    hintText: 'https://...',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  icon: probing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore, size: 18),
                  label: Text(probing ? 'Probing network...' : 'Auto-Detect Server (Smart)'),
                  onPressed: probing
                      ? null
                      : () async {
                          setState(() {
                            probing = true;
                            probeStatus = 'Testing local Wi-Fi & cloud tunnel...';
                          });
                          final best = await detectBestServer();
                          controller.text = best;
                          setState(() {
                            probing = false;
                            probeStatus = best.contains('192.168')
                                ? 'Found: Hotel Local Wi-Fi (192.168.123.6)'
                                : 'Found: Public Cloud Tunnel (Ngrok)';
                          });
                        },
                ),
                if (probeStatus != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    probeStatus!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: probeStatus!.contains('Local')
                          ? Colors.green.shade800
                          : const Color(0xFF926A1A),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (!isStaffOrAdmin) ...[
                  const Text(
                    'GUEST / CUSTOMER (ANYWHERE)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF926A1A),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_queue, size: 16, color: Color(0xFF926A1A)),
                    label: const Text('Public Cloud Tunnel (Any Wi-Fi / 4G)', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      controller.text = cloudTunnelBaseUrl;
                    },
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.wifi, size: 16),
                    label: const Text('Local Wi-Fi (192.168.123.6)', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      controller.text = defaultBaseUrl;
                    },
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),
                  const Text(
                    'STAFF & ADMIN (HOTEL WI-FI ONLY)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Hotel security policy blocks staff & admin on public cloud tunnel. Staff must connect to local hotel Wi-Fi.',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, size: 20, color: Color(0xFF92400E)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Staff & Admin Access: Hotel security policy restricts staff logins to the internal hotel Wi-Fi.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.wifi, size: 16, color: Color(0xFF241C16)),
                    label: const Text(
                      'Connect to Hotel Wi-Fi (192.168.123.6)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      controller.text = defaultBaseUrl;
                    },
                  ),
                ],
              ],
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
    },
  );

  if (saved != null && saved.trim().isNotEmpty) {
    await ref.read(baseUrlProvider.notifier).save(saved);
    return true;
  }
  return false;
}
