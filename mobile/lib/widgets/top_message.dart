import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// A short message that slides in at the TOP of the screen (a green tick for good news,
/// a red mark for a problem) and goes away by itself. It replaces the grey bar at the bottom.
///
/// Make it with [TopMessage.of] BEFORE closing a screen, then call [show] when you want:
/// it stays valid after the screen is gone.
class TopMessage {
  TopMessage._(this._overlay);

  final OverlayState _overlay;

  static OverlayEntry? _current;

  static TopMessage of(BuildContext context) =>
      TopMessage._(Overlay.of(context, rootOverlay: true));

  void show(String text, {bool error = false}) {
    _current?.remove();
    _current = null;
    if (!_overlay.mounted) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TopToast(
        text: text,
        error: error,
        onDone: () {
          if (_current == entry) _current = null;
          entry.remove();
        },
      ),
    );
    _current = entry;
    _overlay.insert(entry);
  }
}

class _TopToast extends StatefulWidget {
  final String text;
  final bool error;
  final VoidCallback onDone;
  const _TopToast({
    required this.text,
    required this.error,
    required this.onDone,
  });

  @override
  State<_TopToast> createState() => _TopToastState();
}

class _TopToastState extends State<_TopToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );
  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _anim.forward();
    // An error stays a little longer: it has more to read.
    _timer = Timer(Duration(milliseconds: widget.error ? 4500 : 3000), _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    await _anim.reverse();
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final tone = widget.error ? pal.danger : pal.success;
    final bg = widget.error ? pal.dangerWash : pal.successWash;
    final border = widget.error ? pal.dangerBorder : pal.successBorder;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, -1.4),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic),
                ),
            child: FadeTransition(
              opacity: _anim,
              child: Material(
                key: const Key('top-message'),
                color: bg,
                elevation: 6,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _close,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.error
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          color: tone,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.text,
                            style: TextStyle(
                              color: pal.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
