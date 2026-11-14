import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/theme.dart';
import 'angkor_logo.dart';
import 'motion.dart';

/// Shows a short opening animation on top of the app, then reveals the app.
///
/// Timeline (2.4 s): gold ripples and the logo turning in, the name rising letter by
/// letter, a gold line and "Siem Reap", then the splash fades while the app slides up.
/// Skipped when the phone has "remove animations" turned on.
class SplashGate extends StatefulWidget {
  final Widget child;
  const SplashGate({super.key, required this.child});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  static const _name = 'Angkor Stay';
  static const _revealAt = 0.74; // when the app starts to appear

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  bool _done = false;
  bool _started = false;
  bool _showChild = false;
  bool _waitingForFrame = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotion(context)) {
      _done = true;
      _showChild = true;
    } else {
      // Start the clock only when the first frame has really reached the screen. On a
      // slow start the Android window stays up for a while; the logo must not play unseen.
      // (Widget tests have no screen, so they start straight away.)
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  void _onFirstFrameDrawn(List<FrameTiming> timings) {
    _stopWaiting();
    if (mounted) _play();
  }

  void _stopWaiting() {
    if (!_waitingForFrame) return;
    _waitingForFrame = false;
    SchedulerBinding.instance.removeTimingsCallback(_onFirstFrameDrawn);
  }

  void _play() {
    if (!mounted) return;
    _c.addListener(_buildAppWhenLogoHasPlayed);
    _c.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  /// The app behind is built part-way through, so its start-up work does not stutter the logo.
  void _buildAppWhenLogoHasPlayed() {
    if (!_showChild && _c.value >= 0.3) setState(() => _showChild = true);
  }

  @override
  void dispose() {
    _stopWaiting();
    _c.dispose();
    super.dispose();
  }

  /// 0..1 progress of [_c] between [from] and [to] (as fractions of the whole timeline).
  double _t(double from, double to, [Curve curve = Curves.easeOutCubic]) {
    final v = ((_c.value - from) / (to - from)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;

    return Stack(
      children: [
        if (_showChild)
          AnimatedBuilder(
            animation: _c,
            // Hidden while the logo plays, then fades and slides up as the splash leaves.
            builder: (context, child) {
              final t = _done ? 1.0 : _t(_revealAt, 1.0);
              return Offstage(
                offstage: !_done && _c.value < _revealAt,
                child: Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 22),
                    child: child,
                  ),
                ),
              );
            },
            child: widget.child,
          ),
        if (!_done)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final leave = _t(_revealAt, 1.0, Curves.easeIn);
                final logo = _t(0.0, 0.34, Curves.easeOutBack);
                final line = _t(0.5, 0.74, Curves.easeInOutCubic);
                return Opacity(
                  opacity: 1 - leave,
                  child: Transform.scale(
                    scale: 1 + leave * 0.06,
                    // Material gives the text the app's normal font (a bare Text would fall back).
                    child: Material(
                      color: pal.page,
                      child: Align(
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 200,
                              height: 200,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  for (var i = 0; i < 2; i++) _ripple(i),
                                  Opacity(
                                    opacity: logo.clamp(0.0, 1.0),
                                    child: Transform.rotate(
                                      angle: (1 - logo) * -0.4,
                                      child: Transform.scale(
                                        scale: 0.6 + 0.4 * logo,
                                        child: const AngkorLogo(size: 112),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < _name.length; i++)
                                  _letter(_name[i], i, pal.text),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: 110 * line,
                              height: 2,
                              color: angkorGoldLight,
                            ),
                            const SizedBox(height: 14),
                            Opacity(
                              opacity: line,
                              child: Text(
                                'Siem Reap',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                  color: pal.goldDeep,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// An expanding gold ring that fades out, started one after the other.
  Widget _ripple(int i) {
    final p = _t(0.04 + i * 0.1, 0.5 + i * 0.1, Curves.easeOut);
    return Opacity(
      opacity: (1 - p) * 0.55,
      child: Transform.scale(
        scale: 0.7 + p * 1.1,
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: angkorGoldLight, width: 2),
          ),
        ),
      ),
    );
  }

  /// One letter of the name: rises and fades in a little after the one before it.
  Widget _letter(String ch, int i, Color color) {
    final start = 0.26 + i * 0.022;
    final p = _t(start, start + 0.16);
    return Opacity(
      opacity: p,
      child: Transform.translate(
        offset: Offset(0, (1 - p) * 16),
        child: Text(
          ch,
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: color,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
