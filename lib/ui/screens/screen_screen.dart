import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/deck_bloc.dart';
import '../../blocs/screen_cubit.dart';
import '../../data/input_message.dart';
import '../palette.dart';
import '../widgets.dart';

class ScreenScreen extends StatefulWidget {
  const ScreenScreen({super.key});
  @override
  State<ScreenScreen> createState() => _ScreenScreenState();
}

class _ScreenScreenState extends State<ScreenScreen>
    with WidgetsBindingObserver {
  String? _monitor;
  bool _control = true;
  late final ScreenCubit _cubit = ScreenCubit(
    context.read<DeckBloc>().repo.client,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.resumed) _cubit.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mons = context.select((DeckBloc b) => b.state.frame.hypr.monitors);
    if (mons.isEmpty) {
      return const Center(child: EmptyNote('No monitors to view'));
    }
    final mon = mons.any((m) => m.name == _monitor)
        ? _monitor!
        : mons.firstWhere((m) => m.focused, orElse: () => mons.first).name;
    final repo = context.read<DeckBloc>().repo;
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<ScreenCubit, ScreenState>(
        builder: (context, s) {
          return Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: p.outline),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: s.png == null
                        ? Center(
                            child: EmptyNote(
                              s.error ??
                                  (s.running
                                      ? 'Waiting for the first frame…'
                                      : 'A few frames per second, straight from the rig.\nTap to click, drag to drag, hold to right-click.'),
                            ),
                          )
                        : InteractiveViewer(
                            maxScale: 6,
                            panEnabled: !_control,
                            scaleEnabled: !_control,
                            child: ScreenSurface(
                              png: s.png!,
                              monitor: mon,
                              enabled: _control && s.running,
                              send: repo.send,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.error ??
                      (s.running && s.frameMs != null
                          ? '${s.frameMs} ms per frame'
                          : ' '),
                  style: TextStyle(
                    fontSize: 12,
                    color: s.error != null ? Palette.danger : p.onVar,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    IntrinsicWidth(
                      child: DeckButton(
                        s.running ? 'Stop' : 'View',
                        icon: s.running ? Icons.stop : Icons.play_arrow,
                        tone: s.running ? Tone.normal : Tone.primary,
                        onTap: () =>
                            s.running ? _cubit.stop() : _cubit.start(mon),
                      ),
                    ),
                    Seg<bool>(
                      items: const {true: 'Control', false: 'Zoom'},
                      value: _control,
                      onChanged: (v) => setState(() => _control = v),
                    ),
                    if (mons.length > 1)
                      Seg<String>(
                        items: {for (final m in mons) m.name: m.name},
                        value: mon,
                        onChanged: (v) {
                          setState(() => _monitor = v);
                          if (s.running) _cubit.start(v);
                        },
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Paints the latest frame and turns touches into absolute pointer events.
class ScreenSurface extends StatefulWidget {
  const ScreenSurface({
    super.key,
    required this.png,
    required this.monitor,
    required this.enabled,
    required this.send,
  });
  final Uint8List png;
  final String monitor;
  final bool enabled;
  final bool Function(InputMessage) send;
  @override
  State<ScreenSurface> createState() => _ScreenSurfaceState();
}

class _ScreenSurfaceState extends State<ScreenSurface> {
  ui.Image? _img;
  int _seq = 0;

  int? _pointer;
  Offset _start = Offset.zero;
  bool _dragging = false, _consumed = false;
  Timer? _long;
  int _lastMove = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(ScreenSurface old) {
    super.didUpdateWidget(old);
    if (!identical(old.png, widget.png)) _decode();
    if (old.enabled && !widget.enabled) _end();
  }

  Future<void> _decode() async {
    final seq = ++_seq;
    try {
      final codec = await ui.instantiateImageCodec(widget.png);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || seq != _seq) return frame.image.dispose();
      final old = _img;
      setState(() => _img = frame.image);
      old?.dispose();
    } catch (_) {
      /* keep the last good frame */
    }
  }

  @override
  void dispose() {
    _end();
    _seq++;
    _img?.dispose();
    super.dispose();
  }

  (double, double)? _frac(Offset o, Size box) {
    final i = _img;
    if (i == null) return null;
    final s = min(box.width / i.width, box.height / i.height);
    final w = i.width * s, h = i.height * s;
    final fx = (o.dx - (box.width - w) / 2) / w;
    final fy = (o.dy - (box.height - h) / 2) / h;
    return fx < 0 || fx > 1 || fy < 0 || fy > 1 ? null : (fx, fy);
  }

  void _send(String t, Offset o, Size box) {
    final f = _frac(o, box);
    if (f != null) {
      widget.send(InputMessage.video(t, widget.monitor, f.$1, f.$2));
    }
  }

  void _end() {
    _long?.cancel();
    if (_dragging) widget.send(InputMessage.videoUp());
    _dragging = false;
    _pointer = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final box = c.biggest;
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (!widget.enabled || _pointer != null) return;
            if (_frac(e.localPosition, box) == null) return;
            _pointer = e.pointer;
            _start = e.localPosition;
            _consumed = false;
            _send('vmove', _start, box);
            _long = Timer(const Duration(milliseconds: 500), () {
              _consumed = true;
              tick(context);
              _send('vrclick', _start, box);
            });
          },
          onPointerMove: (e) {
            if (e.pointer != _pointer || _consumed) return;
            if (!_dragging && (e.localPosition - _start).distance > 8) {
              _long?.cancel();
              _dragging = true;
              _send('vdown', _start, box);
            }
            final now = e.timeStamp.inMilliseconds;
            if (_dragging && now - _lastMove > 40) {
              _lastMove = now;
              _send('vmove', e.localPosition, box);
            }
          },
          onPointerUp: (e) {
            if (e.pointer != _pointer) return;
            if (_dragging) {
              _send('vmove', e.localPosition, box);
            } else if (!_consumed) {
              _send('vclick', _start, box);
            }
            _end();
          },
          onPointerCancel: (e) {
            if (e.pointer == _pointer) _end();
          },
          child: SizedBox.expand(
            child: RawImage(
              image: _img,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        );
      },
    );
  }
}
