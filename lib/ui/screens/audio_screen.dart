import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/deck_bloc.dart';
import '../../data/models.dart';
import '../palette.dart';
import '../widgets.dart';

class AudioScreen extends StatelessWidget {
  const AudioScreen({super.key, required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final player = Panel(
      child: Column(
        children: [
          ArtImage(size: wide ? 110 : 190),
          const SizedBox(height: 12),
          const _TrackTitle(),
          const SeekBar(),
          const Transport(),
        ],
      ),
    );
    const controls = Column(
      children: [VolumeBar(), SizedBox(height: 10), _Mutes()],
    );
    const devices = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Output'),
        _Devices(source: false),
        SizedBox(height: 14),
        SectionLabel('Input'),
        _Devices(source: true),
      ],
    );
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: player,
            ),
          ),
          const Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(10),
              child: Column(
                children: [_Mutes(), SizedBox(height: 14), devices],
              ),
            ),
          ),
        ],
      );
    }
    return PageBody(children: [player, controls, devices]);
  }
}

class _Mutes extends StatelessWidget {
  const _Mutes();
  @override
  Widget build(BuildContext context) {
    final b = context.read<DeckBloc>();
    final (mic, spk) = context.select(
      (DeckBloc b) =>
          (b.state.frame.audio.micMuted, b.state.frame.audio.sinkMuted),
    );
    return Row(
      children: [
        Expanded(
          child: DeckButton(
            mic ? 'Mic muted' : 'Mic on',
            icon: mic ? Icons.mic_off : Icons.mic,
            tone: mic ? Tone.danger : Tone.normal,
            onTap: () => b.add(const MuteToggled(mic: true)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DeckButton(
            spk ? 'Speaker muted' : 'Speaker on',
            icon: spk ? Icons.volume_off : Icons.volume_up,
            tone: spk ? Tone.danger : Tone.normal,
            onTap: () => b.add(const MuteToggled()),
          ),
        ),
      ],
    );
  }
}

class _Devices extends StatelessWidget {
  const _Devices({required this.source});
  final bool source;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final list = context.select(
      (DeckBloc b) =>
          source ? b.state.frame.audio.sources : b.state.frame.audio.sinks,
    );
    if (list.isEmpty) return const EmptyNote('No devices');
    return Column(
      children: [
        for (final d in list)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              tick(context);
              context.read<DeckBloc>().add(
                DeviceSelected(d.id, source: source),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: d.active ? p.tint(.08) : p.low,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: d.active ? p.primary : p.outline),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 9,
                    color: d.active ? p.primary : p.outline,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      d.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: d.active ? p.primary : p.onVar,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TrackTitle extends StatelessWidget {
  const _TrackTitle();
  @override
  Widget build(BuildContext context) {
    final np = context.select((DeckBloc b) => b.state.frame.audio.nowPlaying);
    final p = context.pal;
    return Column(
      children: [
        Text(
          np.hasTrack ? np.title : 'Nothing playing',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: p.on,
          ),
        ),
        if (np.player.isNotEmpty)
          Text(
            np.player.split('.').first,
            style: TextStyle(fontSize: 12, color: p.onVar),
          ),
      ],
    );
  }
}

class ArtImage extends StatelessWidget {
  const ArtImage({super.key, required this.size, this.duotone = false});
  final double size;
  final bool duotone;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final key = context.select(
      (DeckBloc b) => b.state.frame.audio.nowPlaying.artKey,
    );
    final c = context.read<DeckBloc>().repo.client;
    final empty = Center(
      child: Icon(Icons.graphic_eq, size: size * .35, color: p.outline),
    );
    Widget img = key.isEmpty
        ? empty
        : Image.network(
            c.url('/media/art', {'k': key}).toString(),
            headers: c.authHeaders,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => empty,
          );
    if (duotone && key.isNotEmpty) {
      img = ColorFiltered(
        colorFilter: ColorFilter.mode(p.primary, BlendMode.multiply),
        child: ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.grey,
            BlendMode.saturation,
          ),
          child: img,
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.low,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.outline),
      ),
      child: img,
    );
  }
}

class Transport extends StatelessWidget {
  const Transport({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final b = context.read<DeckBloc>();
    final playing = context.select(
      (DeckBloc b) => b.state.frame.audio.nowPlaying.playing,
    );
    Widget btn(String tip, IconData i, String action, {bool main = false}) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Semantics(
              label: tip,
              child: DeckButton(
                null,
                icon: i,
                selected: main,
                height: compact ? 44 : 52,
                onTap: () => b.add(MediaPressed(action)),
              ),
            ),
          ),
        );
    return Row(
      children: [
        btn('Previous', Icons.skip_previous, 'previous'),
        btn(
          playing ? 'Pause' : 'Play',
          playing ? Icons.pause : Icons.play_arrow,
          'play-pause',
          main: true,
        ),
        btn('Next', Icons.skip_next, 'next'),
      ],
    );
  }
}

class VolumeBar extends StatelessWidget {
  const VolumeBar({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final b = context.read<DeckBloc>();
    final (v, muted) = context.select(
      (DeckBloc b) => (b.state.volume, b.state.frame.audio.sinkMuted),
    );
    return Row(
      children: [
        IconButton(
          tooltip: muted ? 'Unmute' : 'Mute',
          onPressed: () => b.add(const MuteToggled()),
          icon: Icon(
            muted ? Icons.volume_off : Icons.volume_up,
            color: muted ? Palette.danger : p.on,
          ),
        ),
        Expanded(
          child: Slider(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            value: (v ?? 0).clamp(0, 150).toDouble(),
            max: 150,
            onChanged: v == null ? null : (x) => b.add(VolumeSet(x.round())),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            v == null ? '—' : '$v%',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: p.onVar),
          ),
        ),
      ],
    );
  }
}

class SeekBar extends StatefulWidget {
  const SeekBar({super.key});
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;
  late int _base;
  late DateTime _at;
  DateTime _holdUntil = DateTime(0);
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _sync(context.read<DeckBloc>().state.frame.audio.nowPlaying);
    // Frames arrive every couple of seconds; tick between them.
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && _np.playing && _drag == null) setState(() {});
    });
  }

  NowPlaying get _np => context.read<DeckBloc>().state.frame.audio.nowPlaying;

  void _sync(NowPlaying np) {
    _base = np.positionUs ?? 0;
    _at = DateTime.now();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  static String fmt(int us) {
    final s = us ~/ 1000000;
    final h = s ~/ 3600, m = s % 3600 ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return BlocConsumer<DeckBloc, DeckState>(
      listenWhen: (a, b) =>
          a.frame.audio.nowPlaying != b.frame.audio.nowPlaying,
      listener: (_, s) {
        if (DateTime.now().isAfter(_holdUntil)) _sync(s.frame.audio.nowPlaying);
      },
      buildWhen: (a, b) => a.frame.audio.nowPlaying != b.frame.audio.nowPlaying,
      builder: (context, s) {
        final np = s.frame.audio.nowPlaying;
        if (!np.seekable) return const SizedBox(height: 14);
        final dur = np.durationUs!;
        final run = np.playing
            ? DateTime.now().difference(_at).inMicroseconds
            : 0;
        final pos = _drag?.round() ?? (_base + run).clamp(0, dur);
        final style = TextStyle(fontSize: 12, color: p.onVar);
        return Row(
          children: [
            Text(fmt(pos), style: style),
            Expanded(
              child: Slider(
                value: pos.toDouble().clamp(0, dur.toDouble()),
                max: dur.toDouble(),
                onChanged: (v) => setState(() => _drag = v),
                onChangeEnd: (v) {
                  setState(() {
                    _drag = null;
                    _base = v.round();
                    _at = DateTime.now();
                    _holdUntil = _at.add(const Duration(milliseconds: 2500));
                  });
                  context.read<DeckBloc>().add(SeekRequested(v.round()));
                },
              ),
            ),
            Text(fmt(dur), style: style),
          ],
        );
      },
    );
  }
}

/// Bottom strip on the phone deck: what's on, volume and play/pause.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final np = context.select((DeckBloc b) => b.state.frame.audio.nowPlaying);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.outline)),
      ),
      child: Column(
        children: [
          const VolumeBar(),
          if (np.hasTrack)
            Row(
              children: [
                const SizedBox(width: 6),
                const ArtImage(size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    np.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: p.on),
                  ),
                ),
                const SizedBox(width: 160, child: Transport(compact: true)),
              ],
            ),
        ],
      ),
    );
  }
}
