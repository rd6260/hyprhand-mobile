import 'dart:async';
import 'dart:math';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/lock_cubit.dart';
import '../blocs/notice_cubit.dart';
import '../blocs/settings_cubit.dart';
import '../data/bindings.dart';
import '../data/native.dart';
import 'palette.dart';

/// Sits above the whole navigator. While locked, everything underneath keeps
/// its state but is invisible, frozen, and deaf to touch, focus, back and
/// accessibility. MainActivity also blocks touches before they reach Flutter.
class StandbyGate extends StatefulWidget {
  const StandbyGate({super.key, required this.child});
  final Widget child;
  @override
  State<StandbyGate> createState() => _StandbyGateState();
}

class _StandbyGateState extends State<StandbyGate> {
  @override
  Widget build(BuildContext context) {
    final locked = context.watch<LockCubit>().state;
    return Stack(
      children: [
        // Same tree shape either way, so unlocking returns to the same screen.
        Visibility(
          visible: !locked,
          maintainState: true,
          child: ExcludeFocus(
            excluding: locked,
            child: AbsorbPointer(absorbing: locked, child: widget.child),
          ),
        ),
        if (locked) const Positioned.fill(child: Standby()),
      ],
    );
  }
}

/// Swallows system back while locked. Must be registered before WidgetsApp's
/// own observer, i.e. from above MaterialApp.
class StandbyBackBlocker extends StatefulWidget {
  const StandbyBackBlocker({super.key, required this.child});
  final Widget child;
  @override
  State<StandbyBackBlocker> createState() => _StandbyBackBlockerState();
}

class _StandbyBackBlockerState extends State<StandbyBackBlocker>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async => context.read<LockCubit>().state;
  @override
  bool handleStartBackGesture(PredictiveBackEvent e) =>
      context.read<LockCubit>().state;

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Pulse {
  _Pulse(this.button, this.failed);
  final PhoneButton button;
  final bool failed;

  /// Set on the first painted tick, so frames skipped while paused don't count.
  Duration? start;
  double at(Duration now) =>
      start == null ? 0 : (now - start!).inMilliseconds / 1200;
}

/// Black and still until a button is pressed; then light comes in from the
/// edge where that button physically is.
class Standby extends StatefulWidget {
  const Standby({super.key});
  @override
  State<Standby> createState() => _StandbyState();
}

class _StandbyState extends State<Standby> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _now = ValueNotifier<Duration>(Duration.zero);
  final _pulses = <_Pulse>[];
  late final List<StreamSubscription<Object?>> _subs;
  late final Timer _hintTimer;
  Timer? _wake;
  bool _hint = true;
  DateTime _pressed = DateTime(0);
  PhoneButton _last = PhoneButton.power;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.primaryFocus?.unfocus();
    final native = context.read<Native>();
    _subs = [
      native.volumeKeys.listen(
        (k) => _press(k.$1 > 0 ? PhoneButton.volumeUp : PhoneButton.volumeDown),
      ),
      native.powerKey.listen((_) => _press(PhoneButton.power)),
      native.screenOn.listen((_) => _playPower()),
      context.read<NoticeCubit>().stream.listen(_notice),
    ];
    final last = native.lastPower;
    if (last != null && DateTime.now().difference(last).inSeconds < 10) {
      _pressed = last;
      _waitForScreen();
      if (native.lastScreenOn?.isAfter(last) ?? false) _playPower();
    }
    _hintTimer = Timer(
      const Duration(seconds: 4),
      () => setState(() => _hint = false),
    );
    // The native side covers the old frame until we are really on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => native.standbyShown());
  }

  /// Runs only while something is playing; idle standby costs nothing.
  void _tick(Duration t) {
    for (final p in _pulses) {
      p.start ??= t;
    }
    _pulses.removeWhere((p) => p.at(t) >= 1);
    _now.value = t;
    if (_pulses.isEmpty) _ticker.stop();
  }

  void _play(PhoneButton b, {bool failed = false}) {
    // Holding a button must not pile up hundreds of effects.
    if (_pulses.length >= 6) _pulses.removeAt(0);
    _pulses.add(_Pulse(b, failed));
    if (!_ticker.isActive) _ticker.start();
  }

  void _press(PhoneButton b) {
    if (context.read<SettingsCubit>().state.haptics) {
      HapticFeedback.mediumImpact();
    }
    _pressed = DateTime.now();
    _last = b;
    b == PhoneButton.power ? _waitForScreen() : _play(b);
  }

  /// A power press turns the display off: save its effect for the wake-up,
  /// with a fallback in case that is never reported.
  void _waitForScreen() {
    _wake?.cancel();
    _wake = Timer(const Duration(milliseconds: 1500), _playPower);
  }

  void _playPower() {
    if (_wake == null) return;
    _wake!.cancel();
    _wake = null;
    _play(PhoneButton.power);
  }

  /// Failures are the same light in red, nothing more: details can name private actions.
  void _notice(Notice? n) {
    if (n == null || !n.error) return;
    if (DateTime.now().difference(_pressed).inSeconds < 15) {
      _play(_last, failed: true);
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hintTimer.cancel();
    _wake?.cancel();
    _ticker.dispose();
    _now.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _StandbyPainter(
                  _now,
                  _pulses,
                  p,
                  MediaQuery.disableAnimationsOf(context),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Semantics(
              button: true,
              label: 'Unlock',
              excludeSemantics: true,
              onTap: context.read<Native>().requestUnlock,
              child: AnimatedOpacity(
                opacity: _hint ? 1 : 0,
                duration: const Duration(milliseconds: 900),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: Text(
                    'Swipe up to unlock',
                    style: TextStyle(
                      fontSize: 13,
                      color: p.onVar.withValues(alpha: .6),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StandbyPainter extends CustomPainter {
  _StandbyPainter(this.now, this._pulses, this.p, this.still)
    : super(repaint: now);
  final ValueNotifier<Duration> now;
  final List<_Pulse> _pulses;
  final Palette p;
  final bool still;

  @override
  void paint(Canvas c, Size s) {
    for (final pulse in _pulses) {
      final f = pulse.at(now.value);
      if (f < 1) _breathe(c, s, pulse, f);
    }
  }

  /// Volume on the left edge, power on the right, in portrait.
  Offset _origin(PhoneButton b, Size s) => switch (b) {
    PhoneButton.volumeUp => Offset(0, s.height * .27),
    PhoneButton.volumeDown => Offset(0, s.height * .37),
    PhoneButton.power => Offset(s.width, s.height * .32),
  };

  // A Gaussian falloff; plain linear stops leave a visible edge on black.
  static final _stops = [for (var i = 0; i <= 12; i++) i / 12];
  static final _falloff = [
    for (final x in _stops) (exp(-4.5 * x * x) - exp(-4.5)) / (1 - exp(-4.5)),
  ];

  /// One breath of light: a hairline on the edge beside the button, and its
  /// glow. Volume leans the way the sound goes; power opens evenly.
  void _breathe(Canvas c, Size s, _Pulse pulse, double f) {
    // Quick in, long out.
    final a = f < .14
        ? Curves.easeOut.transform(f / .14)
        : 1 - Curves.easeInOutSine.transform((f - .14) / .86);
    final open = still ? 1.0 : Curves.easeOutCubic.transform(f);
    final lean = switch (pulse.button) {
      PhoneButton.volumeUp => -1.0,
      PhoneButton.volumeDown => 1.0,
      PhoneButton.power => 0.0,
    };
    final o =
        _origin(pulse.button, s) + Offset(0, still ? 0 : lean * 34 * open);
    final inward = o.dx == 0 ? 1.0 : -1.0;
    final col = pulse.failed ? Palette.danger : p.primary;

    // Taller than wide, so it reads as light from the edge rather than a ball.
    final reach = s.shortestSide * (.34 + .16 * open);
    c
      ..save()
      ..translate(o.dx, o.dy)
      ..scale(1, 1.7);
    final glow = Rect.fromCircle(center: Offset.zero, radius: reach);
    c
      ..drawRect(
        glow,
        Paint()
          ..shader = RadialGradient(
            stops: _stops,
            colors: [
              for (final k in _falloff) col.withValues(alpha: .34 * a * k),
            ],
          ).createShader(glow),
      )
      ..restore();

    final half = 18 + 30 * open;
    final x = o.dx + 2.5 * inward;
    final line = Rect.fromLTRB(x - 1, o.dy - half, x + 1, o.dy + half);
    c.drawRRect(
      RRect.fromRectAndRadius(line, const Radius.circular(1)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            col.withValues(alpha: 0),
            Color.lerp(col, Colors.white, .45)!.withValues(alpha: a),
            col.withValues(alpha: 0),
          ],
        ).createShader(line),
    );
  }

  @override
  bool shouldRepaint(_StandbyPainter o) => o.p != p || o.still != still;
}
