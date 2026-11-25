import 'dart:math';

import '../data/input_message.dart';

/// Trackpad gesture recogniser, ported from the PWA: one finger moves, tap
/// clicks, two fingers scroll / right-click, and a pinch is forwarded as raw
/// contacts so libinput sees a genuine gesture.
class Trackpad {
  Trackpad(this._send);
  final void Function(InputMessage) _send;

  double sensitivity = 3;
  bool naturalScroll = true;

  static const _accel = 0.06;
  final _pts = <int, Point<double>>{};
  List<Point<double>>? _starts;
  bool _moved = false, _two = false;
  int _startMs = 0;
  double _ax = 0, _ay = 0, _rx = 0, _ry = 0;
  double _travel = 0;
  String? _gesture;

  void down(int id, double x, double y, int ms) {
    if (_pts.length >= 2) return; // third finger is ignored
    _pts[id] = Point(x, y);
    if (_pts.length == 1) {
      _moved = false;
      _two = false;
      _startMs = ms;
      _travel = _rx = _ry = 0;
      _gesture = null;
    } else {
      _two = true;
      _starts = _pts.values.toList();
      _ax = _ay = 0;
      _gesture = null;
    }
  }

  void move(int id, double x, double y, double width, double height) {
    final prev = _pts[id];
    if (prev == null) return;
    final now = Point(x, y);
    _pts[id] = now;
    if (_pts.length >= 2) return _twoFinger(prev, now, width, height);
    if (_two) return; // one finger left over after a two-finger gesture

    final dx = x - prev.x, dy = y - prev.y;
    _travel += dx.abs() + dy.abs();
    // A resting fingertip jitters; hold the cursor still until it means it.
    if (!_moved && _travel <= 3) return;
    _moved = true;
    final f = sensitivity * (1 + sqrt(dx * dx + dy * dy) * _accel);
    _rx += dx * f;
    _ry += dy * f;
    final sx = _rx.truncate(), sy = _ry.truncate();
    if (sx != 0 || sy != 0) {
      _rx -= sx;
      _ry -= sy;
      _send(InputMessage.move(sx, sy));
    }
  }

  void _twoFinger(Point<double> prev, Point<double> now, double w, double h) {
    final a = _pts.values.toList();
    final s = _starts!;
    if (_gesture == null) {
      final d0 = a[0] - s[0], d1 = a[1] - s[1];
      final hi = max(d0.magnitude, d1.magnitude);
      final lo = min(d0.magnitude, d1.magnitude);
      if (hi > 8 && (lo > 4 || hi > 18)) {
        final u = s[1] - s[0];
        final ul = u.magnitude == 0 ? 1.0 : u.magnitude;
        final rel = ((d1.x - d0.x) * u.x + (d1.y - d0.y) * u.y).abs() / ul / 2;
        final common = (d0 + d1).magnitude / 2;
        _gesture = lo > 4 && lo > 0.2 * hi && rel > 4 && rel > common * 0.8
            ? 'pinch'
            : 'pan';
      }
    }
    if (_gesture == 'pinch') {
      _moved = true;
      _send(
        InputMessage.touch([
          for (final p in a)
            [(p.x / w).clamp(0.0, 1.0), (p.y / h).clamp(0.0, 1.0)],
        ]),
      );
    } else if (_gesture == 'pan') {
      final both = (a[0] - s[0]).magnitude > 6 && (a[1] - s[1]).magnitude > 6;
      final k = both ? 0.5 : 1.0;
      _ax += (now.x - prev.x) * k;
      _ay += (now.y - prev.y) * k;
      // One wheel notch per event, like the PWA, so a flick can't run away.
      final sy = (_ay / 3).truncate(), sx = (_ax / 3).truncate();
      if (sx != 0 || sy != 0) {
        final dir = naturalScroll ? 1 : -1;
        _send(InputMessage.scroll(dy: sy.sign * dir, dx: -sx.sign * dir));
        _ay -= sy * 3;
        _ax -= sx * 3;
        _moved = true;
      }
    }
  }

  void up(int id, int ms, {bool cancelled = false}) {
    if (_pts.remove(id) == null) return;
    if (_gesture == 'pinch' && _pts.length < 2) {
      _send(InputMessage.touch(const []));
      _gesture = 'done';
    }
    if (_pts.isNotEmpty) return;
    final quick = ms - _startMs < (_two ? 300 : 250);
    if (!cancelled && !_moved && quick) {
      _send(InputMessage.click(_two ? 'right' : 'left'));
    }
    _two = false;
    _starts = null;
    _gesture = null;
  }

  /// Never leave fingers "down" on the rig's virtual touchpad.
  void reset() {
    if (_gesture == 'pinch') _send(InputMessage.touch(const []));
    _pts.clear();
    _starts = null;
    _gesture = null;
    _two = false;
  }
}
