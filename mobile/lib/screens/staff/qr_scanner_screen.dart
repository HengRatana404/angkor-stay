import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/staff_booking.dart';
import '../../staff/staff_booking_repository.dart';
import '../../widgets/angkor_app_bar.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/motion.dart';
import '../../widgets/status_chip.dart';
import 'staff_booking_detail_screen.dart';
import 'take_payment_screen.dart';
import '../../widgets/top_message.dart';

/// What a scan should do.
enum ScanMode { checkIn, checkOut }

/// Camera QR scanner for hotel staff and admin.
/// Scan a guest QR, see who it is, then check the guest in or out with one tap.
class QrScannerScreen extends ConsumerStatefulWidget {
  final void Function(String code)? onScanned;

  /// Start on check-in or on check-out (the booking screen knows which one fits).
  final ScanMode initialMode;

  const QrScannerScreen({
    super.key,
    this.onScanned,
    this.initialMode = ScanMode.checkIn,
  });

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen> {
  late final MobileScannerController _controller;
  bool _handled = false;
  bool _torchOn = false;
  late ScanMode _mode = widget.initialMode;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _handleCode(raw.trim());
        break;
      }
    }
  }

  Future<void> _handleCode(String code) async {
    if (_handled) return;
    setState(() => _handled = true);

    if (widget.onScanned != null) {
      widget.onScanned!(code);
      Navigator.of(context).pop(code);
      return;
    }

    // AS-0006, AS-2026-0006 or 6 all mean booking 6.
    final parts = code.split('-');
    final bookingId = int.tryParse(parts.isNotEmpty ? parts.last : code);

    if (bookingId == null || bookingId <= 0) {
      if (mounted) {
        TopMessage.of(context).show('That QR code is not an Angkor Stay booking.', error: true);
        setState(() => _handled = false);
      }
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ScanResultSheet(bookingId: bookingId, mode: _mode),
    );
    // Sheet closed: ready for the next guest.
    if (mounted) setState(() => _handled = false);
  }

  @override
  Widget build(BuildContext context) {
    final checkIn = _mode == ScanMode.checkIn;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AngkorAppBar(
        title: 'Scan guest QR',
        strong: true,
        actions: [
          IconButton(
            tooltip: 'Toggle flashlight',
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: angkorGoldLight,
            ),
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
          IconButton(
            tooltip: 'Flip camera',
            icon: const Icon(Icons.flip_camera_android, color: angkorGoldLight),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: kIsWeb
                ? const Center(
                    child: Text(
                      'Camera scanner active on mobile',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.no_photography, size: 54, color: angkorGoldLight),
                              const SizedBox(height: 16),
                              Text(
                                'Camera permission required or camera busy.\n${error.errorDetails?.message ?? ""}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Check in / Check out switch
          Positioned(
            top: 8,
            left: 20,
            right: 20,
            child: SegmentedButton<ScanMode>(
              key: const Key('scan-mode'),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                backgroundColor: const Color(0xDD1E1A17),
                foregroundColor: Colors.white,
                selectedBackgroundColor: angkorGoldLight,
                selectedForegroundColor: angkorInk,
                side: BorderSide(color: angkorGoldLight.withValues(alpha: 0.4)),
              ),
              segments: const [
                ButtonSegment(
                  value: ScanMode.checkIn,
                  icon: Icon(Icons.login, size: 18),
                  label: Text('Check in'),
                ),
                ButtonSegment(
                  value: ScanMode.checkOut,
                  icon: Icon(Icons.logout, size: 18),
                  label: Text('Check out'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),

          // Viewfinder frame
          Center(
            child: AnimatedContainer(
              duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 250),
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _handled ? Colors.white : angkorGoldLight,
                  width: 3,
                ),
              ),
            ),
          ),

          // Instruction and demo button
          Positioned(
            left: 20,
            right: 20,
            bottom: 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xDD1E1A17),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: angkorGoldLight.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.qr_code_scanner, color: angkorGoldLight, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        checkIn
                            ? 'Scan the guest QR to check in'
                            : 'Scan the guest QR to check out',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // One-tap demo scan for presentations
                FilledButton.icon(
                  key: const Key('demo-scan-button'),
                  onPressed: () => _handleCode('AS-0006'),
                  icon: const Icon(Icons.flash_on, size: 16, color: angkorInk),
                  label: const Text(
                    'Quick demo: scan AS-0006',
                    style: TextStyle(color: angkorInk, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: angkorGoldLight,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows the scanned booking and the one action that fits the chosen mode.
class ScanResultSheet extends ConsumerStatefulWidget {
  final int bookingId;
  final ScanMode mode;
  const ScanResultSheet({super.key, required this.bookingId, required this.mode});

  @override
  ConsumerState<ScanResultSheet> createState() => _ScanResultSheetState();
}

class _ScanResultSheetState extends ConsumerState<ScanResultSheet> {
  bool _busy = false;
  String? _error;
  String? _done; // message after a successful check-in or check-out

  void _refresh() {
    ref.invalidate(staffBookingProvider(widget.bookingId));
    ref.invalidate(staffBookingsProvider);
  }

  Future<void> _run(
    Future<StaffBooking> Function(StaffBookingRepository repo) action,
    String Function(StaffBooking) doneText,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final b = await action(ref.read(staffBookingRepositoryProvider));
      _refresh();
      if (mounted) setState(() => _done = doneText(b));
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
      _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final booking = ref.watch(staffBookingProvider(widget.bookingId));

    return Container(
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        22 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: pal.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            booking.when(
              loading: () => const SizedBox(
                height: 140,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ErrorBanner('$e'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Scan again'),
                  ),
                ],
              ),
              data: (b) => _content(context, b),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, StaffBooking b) {
    final pal = context.pal;
    final checkIn = widget.mode == ScanMode.checkIn;

    if (_done != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopIn(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: pal.successWash, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, size: 40, color: pal.success),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _done!,
            key: const Key('scan-done'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: pal.text),
          ),
          const SizedBox(height: 4),
          Text(
            'Room ${b.roomNumber} · ${b.code}',
            style: TextStyle(color: pal.textMuted),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('scan-next'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Scan next guest'),
          ),
        ],
      );
    }

    final a = b.actions;
    final paid = b.payments.any((p) => p.status == 'paid');

    // Say clearly why the chosen action is not possible.
    String? blocked;
    if (checkIn && !a.canCheckIn) {
      blocked = switch (b.status) {
        'checked_in' => 'Already checked in. Switch to "Check out" to check this guest out.',
        'checked_out' => 'This guest already checked out.',
        'cancelled' => 'This booking was cancelled.',
        'no_show' => 'This booking was marked as a no-show.',
        _ => a.checkInProblem ?? 'This guest cannot check in yet.',
      };
    } else if (!checkIn && !a.canCheckOut) {
      blocked = switch (b.status) {
        'checked_out' => 'Already checked out.',
        'confirmed' || 'pending' => 'This guest has not checked in yet. Switch to "Check in" first.',
        _ => 'This guest cannot be checked out.',
      };
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                b.code,
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: pal.text,
                ),
              ),
            ),
            StatusChip(b.status, paid: b.paid),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          b.guestName,
          key: const Key('scan-guest'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: pal.text),
        ),
        const SizedBox(height: 4),
        Text(
          '${b.roomTypeName} · Room ${b.roomNumber}',
          style: TextStyle(color: pal.textMuted),
        ),
        Text(
          '${formatShortDate(b.checkIn)} → ${formatShortDate(b.checkOut)} · ${nightsText(b.nights)}',
          style: TextStyle(color: pal.textMuted),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: paid ? pal.successWash : pal.goldWash,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: paid ? pal.successBorder : pal.goldSoft),
          ),
          child: Row(
            children: [
              Icon(
                paid ? Icons.check_circle : Icons.payments_outlined,
                size: 18,
                color: paid ? pal.success : pal.goldDeep,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  paid
                      ? 'Paid ${formatMoney(b.payments.where((p) => p.status == 'paid').fold<double>(0, (t, p) => t + p.amount))}'
                      : 'Not paid. ${formatMoney(b.totalPrice)} to collect.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: paid ? pal.success : pal.goldDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorBanner(_error!),
        ],
        const SizedBox(height: 16),
        if (blocked != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: pal.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              blocked,
              key: const Key('scan-blocked'),
              style: TextStyle(color: pal.text),
            ),
          )
        else
          FilledButton.icon(
            key: Key(checkIn ? 'scan-check-in' : 'scan-check-out'),
            onPressed: _busy
                ? null
                : () => checkIn
                    ? _run((r) => r.checkIn(b.id), (x) => '${x.guestName} is checked in')
                    : _run((r) => r.checkOut(b.id), (x) => '${x.guestName} is checked out'),
            icon: Icon(checkIn ? Icons.login : Icons.logout),
            label: Text(checkIn ? 'Check in to room ${b.roomNumber}' : 'Check out of room ${b.roomNumber}'),
          ),
        if (checkIn && a.canTakePayment) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('scan-take-payment'),
            onPressed: _busy
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => TakePaymentScreen(booking: b)),
                    );
                    _refresh();
                  },
            icon: const Icon(Icons.payments_outlined),
            label: Text('Take payment (${formatMoney(b.totalPrice)})'),
          ),
        ],
        const SizedBox(height: 6),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StaffBookingDetailScreen(bookingId: b.id),
              ),
            );
          },
          child: const Text('Open full booking'),
        ),
      ],
    );
  }
}
