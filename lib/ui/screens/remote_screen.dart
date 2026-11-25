import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/deck_bloc.dart';
import '../../blocs/files_cubit.dart';
import '../../blocs/keyboard_cubit.dart';
import '../../blocs/notice_cubit.dart';
import '../../blocs/settings_cubit.dart';
import '../../blocs/trackpad.dart';
import '../../data/hypr_client.dart';
import '../../data/input_message.dart';
import '../palette.dart';
import '../widgets.dart';
import 'buttons_tab.dart';

enum _Mode { pad, keys, type, buttons }

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.wide});
  final bool wide;
  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  _Mode _mode = _Mode.pad;
  bool _available = true;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    try {
      final ok = await context.read<DeckBloc>().repo.client.inputAvailable();
      if (mounted) setState(() => _available = ok);
    } on ApiException {
      // assume fine; the link indicator covers outages
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<DeckBloc>().repo;
    final pad = Column(
      children: [
        Expanded(child: TrackpadSurface(send: repo.send)),
        const SizedBox(height: 8),
        _Clicks(send: repo.send),
      ],
    );
    final lower = switch (_mode) {
      _Mode.keys => Keyboard(compact: !widget.wide),
      _Mode.type => _TypeBox(send: repo.send),
      _Mode.pad || _Mode.buttons => null,
    };
    final tabs = Seg<_Mode>(
      items: const {
        _Mode.pad: 'Trackpad',
        _Mode.keys: 'Keys',
        _Mode.type: 'Type',
        _Mode.buttons: 'Buttons',
      },
      value: _mode,
      onChanged: (m) => setState(() => _mode = m),
    );
    return BlocProvider(
      create: (_) => KeyboardCubit(repo.send),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_available)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Remote input is off: the rig has no /dev/uinput access.',
                  style: TextStyle(color: Palette.danger, fontSize: 12),
                ),
              ),
            Center(child: tabs),
            const SizedBox(height: 8),
            if (_mode == _Mode.buttons)
              const Expanded(child: ButtonsTab())
            else if (widget.wide)
              Expanded(
                child: lower == null
                    ? pad
                    : _mode == _Mode.keys
                    ? lower
                    : Row(
                        children: [
                          Expanded(child: pad),
                          const SizedBox(width: 10),
                          Expanded(child: SingleChildScrollView(child: lower)),
                        ],
                      ),
              )
            else ...[
              // On short screens the keyboard needs the trackpad's space.
              if (_mode == _Mode.keys &&
                  MediaQuery.sizeOf(context).height < 700)
                const Spacer()
              else
                Expanded(child: pad),
              if (lower != null) ...[const SizedBox(height: 10), lower],
            ],
          ],
        ),
      ),
    );
  }
}

class TrackpadSurface extends StatefulWidget {
  const TrackpadSurface({super.key, required this.send});
  final bool Function(InputMessage) send;
  @override
  State<TrackpadSurface> createState() => _TrackpadSurfaceState();
}

class _TrackpadSurfaceState extends State<TrackpadSurface> {
  late final Trackpad _t = Trackpad(widget.send);

  @override
  void dispose() {
    _t.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.watch<SettingsCubit>().state;
    _t
      ..sensitivity = s.sensitivity
      ..naturalScroll = s.naturalScroll;
    return LayoutBuilder(
      builder: (context, box) {
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _t.down(
            e.pointer,
            e.localPosition.dx,
            e.localPosition.dy,
            e.timeStamp.inMilliseconds,
          ),
          onPointerMove: (e) => _t.move(
            e.pointer,
            e.localPosition.dx,
            e.localPosition.dy,
            box.maxWidth,
            box.maxHeight,
          ),
          onPointerUp: (e) => _t.up(e.pointer, e.timeStamp.inMilliseconds),
          onPointerCancel: (e) =>
              _t.up(e.pointer, e.timeStamp.inMilliseconds, cancelled: true),
          child: CustomPaint(
            painter: _PadGrid(p),
            child: Center(
              child: Text(
                'drag to move · tap to click\ntwo fingers: scroll, pinch, tap for right-click',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: p.onVar.withValues(alpha: .6),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PadGrid extends CustomPainter {
  _PadGrid(this.p);
  final Palette p;
  @override
  void paint(Canvas c, Size s) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & s,
      const Radius.circular(10),
    );
    c.drawRRect(r, Paint()..color = p.low);
    c.save();
    c.clipRRect(r);
    final g = Paint()..color = p.primary.withValues(alpha: .07);
    for (var x = 22.0; x < s.width; x += 22) {
      c.drawRect(Rect.fromLTWH(x, 0, 1, s.height), g);
    }
    for (var y = 22.0; y < s.height; y += 22) {
      c.drawRect(Rect.fromLTWH(0, y, s.width, 1), g);
    }
    c.restore();
    c.drawRRect(
      r.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = p.primary.withValues(alpha: .7),
    );
  }

  @override
  bool shouldRepaint(_PadGrid o) => o.p != p;
}

class _Clicks extends StatelessWidget {
  const _Clicks({required this.send});
  final bool Function(InputMessage) send;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final (i, b) in ['left', 'middle', 'right'].indexed) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: DeckButton(
            b[0].toUpperCase() + b.substring(1),
            onTap: () => send(InputMessage.click(b)),
          ),
        ),
      ],
    ],
  );
}

// ── on-screen keyboard ──

sealed class _K {
  const _K(this.flex);
  final double flex;
}

class _Char extends _K {
  const _Char(this.c, [this.shift, super.flex = 1]);
  final String c;
  final String? shift;
}

class _Special extends _K {
  const _Special(this.key, this.label, [super.flex = 1]);
  final String key, label;
}

class _Mod extends _K {
  const _Mod(this.mod, this.label, [super.flex = 1]);
  final String mod, label;
}

class _Caps extends _K {
  const _Caps([super.flex = 1]);
}

class _Layer extends _K {
  const _Layer([super.flex = 1]);
}

List<_K> _letters(String s) => [for (final c in s.split('')) _Char(c)];
const _digits = [
  _Char('1', '!'),
  _Char('2', '@'),
  _Char('3', '#'),
  _Char('4', r'$'),
  _Char('5', '%'),
  _Char('6', '^'),
  _Char('7', '&'),
  _Char('8', '*'),
  _Char('9', '('),
  _Char('0', ')'),
];
const _arrows = [
  _Special('left', '←'),
  _Special('up', '↑'),
  _Special('down', '↓'),
  _Special('right', '→'),
];

final _full = <List<_K>>[
  [
    const _Special('esc', 'Esc'),
    const _Char('`', '~'),
    ..._digits,
    const _Char('-', '_'),
    const _Char('=', '+'),
    const _Special('backspace', 'Bksp', 2),
  ],
  [
    const _Special('tab', 'Tab', 1.5),
    ..._letters('qwertyuiop'),
    const _Char('[', '{'),
    const _Char(']', '}'),
    const _Char('\\', '|', 1.5),
  ],
  [
    const _Caps(1.75),
    ..._letters('asdfghjkl'),
    const _Char(';', ':'),
    const _Char("'", '"'),
    const _Special('enter', 'Enter', 2.25),
  ],
  [
    const _Mod('shift', 'Shift', 2.25),
    ..._letters('zxcvbnm'),
    const _Char(',', '<'),
    const _Char('.', '>'),
    const _Char('/', '?'),
    const _Special('delete', 'Del', 1.5),
  ],
  [
    const _Mod('ctrl', 'Ctrl', 1.5),
    const _Mod('super', 'Super', 1.5),
    const _Mod('alt', 'Alt', 1.5),
    const _Char(' ', null, 5),
    ..._arrows,
  ],
];

final _compact = <List<_K>>[
  [
    const _Special('esc', 'Esc', 1.2),
    const _Special('tab', 'Tab', 1.2),
    const _Mod('ctrl', 'Ctrl', 1.3),
    const _Mod('super', 'Sup', 1.3),
    const _Mod('alt', 'Alt', 1.2),
    ..._arrows,
  ],
  _digits,
  _letters('qwertyuiop'),
  _letters('asdfghjkl'),
  [
    const _Mod('shift', 'Shift', 1.5),
    ..._letters('zxcvbnm'),
    const _Special('backspace', 'Bksp', 1.5),
  ],
  [
    const _Layer(1.5),
    const _Char(',', '<'),
    const _Char(' ', null, 4),
    const _Char('.', '>'),
    const _Special('enter', 'Enter', 1.8),
  ],
];

final _symbols = <List<_K>>[
  _compact[0],
  [for (var i = 1; i <= 6; i++) _Special('f$i', 'F$i')],
  [for (var i = 7; i <= 12; i++) _Special('f$i', 'F$i')],
  [for (final c in '`~-_=+[]{}'.split('')) _Char(c)],
  [for (final c in r'\|;:"/?<>'.split('')) _Char(c), const _Char("'")],
  [
    const _Layer(1.5),
    const _Special('home', 'Hm'),
    const _Special('end', 'End'),
    const _Special('pageup', 'PgU'),
    const _Special('pagedown', 'PgD'),
    const _Special('delete', 'Del'),
    const _Special('enter', 'Enter', 1.5),
  ],
];

class Keyboard extends StatefulWidget {
  const Keyboard({super.key, required this.compact});
  final bool compact;
  @override
  State<Keyboard> createState() => _KeyboardState();
}

class _KeyboardState extends State<Keyboard> {
  bool _sym = false;
  @override
  Widget build(BuildContext context) {
    final rows = !widget.compact ? _full : (_sym ? _symbols : _compact);
    return BlocBuilder<KeyboardCubit, KeyboardState>(
      builder: (context, s) {
        return LayoutBuilder(
          builder: (context, box) {
            final h = box.hasBoundedHeight
                ? (box.maxHeight / rows.length - 4).clamp(30.0, 56.0)
                : 46.0;
            return Column(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      height: h,
                      child: Row(
                        children: [
                          for (final k in row)
                            Expanded(
                              flex: (k.flex * 100).round(),
                              child: _key(context, k, s),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _key(BuildContext context, _K k, KeyboardState s) {
    final kb = context.read<KeyboardCubit>();
    return switch (k) {
      _Char(:final c, :final shift) => _KeyCap(
        label: c == ' '
            ? 'space'
            : RegExp('[a-z]').hasMatch(c)
            ? (s.upper ? c.toUpperCase() : c)
            : (s.shift ? shift ?? c : c),
        repeat: true,
        onPress: () => kb.char(c, shifted: shift),
      ),
      _Special(:final key, :final label) => _KeyCap(
        label: label,
        small: true,
        repeat: true,
        onPress: () => kb.special(key),
      ),
      _Mod(:final mod, :final label) => _KeyCap(
        label: label,
        small: true,
        lit: s.isOn(mod),
        locked: s.mods[mod] == ModState.locked,
        onPress: () => kb.toggleMod(mod),
        onLong: () => kb.toggleMod(mod, lock: true),
      ),
      _Caps() => _KeyCap(
        label: 'Caps',
        small: true,
        lit: s.caps,
        onPress: kb.toggleCaps,
      ),
      _Layer() => _KeyCap(
        label: _sym ? 'abc' : '#+=',
        small: true,
        onPress: () => setState(() => _sym = !_sym),
      ),
    };
  }
}

/// Fires on touch-down for typing feel, repeats while held.
class _KeyCap extends StatefulWidget {
  const _KeyCap({
    required this.label,
    required this.onPress,
    this.onLong,
    this.small = false,
    this.lit = false,
    this.locked = false,
    this.repeat = false,
  });
  final String label;
  final VoidCallback onPress;
  final VoidCallback? onLong;
  final bool small, lit, locked, repeat;
  @override
  State<_KeyCap> createState() => _KeyCapState();
}

class _KeyCapState extends State<_KeyCap> {
  bool _down = false;
  Timer? _hold;

  void _press() {
    setState(() => _down = true);
    tick(context);
    widget.onPress();
    _hold?.cancel();
    if (widget.onLong != null) {
      _hold = Timer(const Duration(milliseconds: 450), () {
        tick(context);
        widget.onLong!();
      });
    } else if (widget.repeat) {
      _hold = Timer(const Duration(milliseconds: 420), () {
        _hold = Timer.periodic(
          const Duration(milliseconds: 55),
          (_) => widget.onPress(),
        );
      });
    }
  }

  void _release() {
    _hold?.cancel();
    if (mounted) setState(() => _down = false);
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final lit = _down || widget.lit;
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPress,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _press(),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: lit ? p.tint(.22) : p.high,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                width: widget.locked ? 2 : 1,
                color: widget.locked
                    ? p.secondary
                    : lit
                    ? p.primary
                    : p.outline,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.small ? 12 : 16,
                  color: lit ? p.primary : p.on,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// System keyboard: live-typed to the rig, or pasted through its clipboard.
class _TypeBox extends StatefulWidget {
  const _TypeBox({required this.send});
  final bool Function(InputMessage) send;
  @override
  State<_TypeBox> createState() => _TypeBoxState();
}

class _TypeBoxState extends State<_TypeBox> {
  final _c = TextEditingController();
  String _last = '';
  bool _live = true;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _changed(String now) {
    if (_live) {
      diffTyping(_last, now).forEach(widget.send);
    }
    _last = now;
    setState(() {});
  }

  void _clear() {
    _c.clear();
    _last = '';
    setState(() {});
  }

  Future<void> _paste() async {
    final files = context.read<FilesCubit>();
    if (await files.sendClip(_c.text)) {
      widget.send(InputMessage.combo(const ['ctrl', 'v']));
      if (mounted) _clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final odd = _c.text.runes.any((r) => !typeable(r));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _live ? 'Typing live on the rig' : 'Compose, then send',
                style: TextStyle(fontSize: 12, color: p.onVar),
              ),
            ),
            Text('Live', style: TextStyle(fontSize: 12, color: p.onVar)),
            Switch(
              value: _live,
              onChanged: (v) {
                _clear();
                setState(() => _live = v);
              },
            ),
          ],
        ),
        TextField(
          controller: _c,
          onChanged: _changed,
          minLines: 1,
          maxLines: 4,
          autofocus: true,
          style: const TextStyle(fontSize: 15),
          decoration: const InputDecoration(hintText: 'Type or dictate…'),
        ),
        if (odd)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Some characters are outside the rig\'s US layout and '
              'can\'t be typed. Turn Live off and use Paste.',
              style: TextStyle(fontSize: 12, color: p.secondary),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DeckButton(
                'Enter',
                onTap: () {
                  widget.send(InputMessage.combo(const ['enter']));
                  if (_live) _clear();
                },
              ),
            ),
            const SizedBox(width: 8),
            if (_live)
              Expanded(
                child: DeckButton(
                  'Backspace',
                  onTap: () =>
                      widget.send(InputMessage.combo(const ['backspace'])),
                ),
              )
            else ...[
              Expanded(
                child: DeckButton(
                  'Type',
                  onTap: _c.text.isEmpty || odd
                      ? null
                      : () {
                          if (widget.send(InputMessage.text(_c.text))) {
                            _clear();
                          } else {
                            context.read<NoticeCubit>().error('Not connected');
                          }
                        },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DeckButton(
                  'Paste',
                  tone: Tone.primary,
                  onTap: _c.text.isEmpty ? null : _paste,
                ),
              ),
            ],
            const SizedBox(width: 8),
            Expanded(child: DeckButton('Clear', onTap: _clear)),
          ],
        ),
      ],
    );
  }
}
