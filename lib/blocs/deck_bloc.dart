import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../data/deck_repository.dart';
import '../data/deck_socket.dart';
import '../data/hypr_client.dart';
import '../data/models.dart';
import 'notice_cubit.dart';

sealed class DeckEvent {
  const DeckEvent();
}

class DeckResumed extends DeckEvent {
  const DeckResumed();
}

class DeckPaused extends DeckEvent {
  const DeckPaused();
}

class _Frame extends DeckEvent {
  const _Frame(this.frame);
  final DeckFrame frame;
}

class _LinkChanged extends DeckEvent {
  const _LinkChanged(this.link);
  final Link link;
}

class _HoldExpired extends DeckEvent {
  const _HoldExpired(this.seq);
  final int seq;
}

class WorkspaceFocused extends DeckEvent {
  const WorkspaceFocused(this.id);
  final int id;
}

class WindowFocused extends DeckEvent {
  const WindowFocused(this.address);
  final String address;
}

class WindowMoved extends DeckEvent {
  const WindowMoved(this.address, this.workspace);
  final String address;
  final int workspace;
}

class DpmsSet extends DeckEvent {
  const DpmsSet(this.monitor, this.on);
  final String monitor;
  final bool on;
}

class BrightnessRequested extends DeckEvent {
  const BrightnessRequested();
}

class BrightnessSet extends DeckEvent {
  const BrightnessSet(this.monitor, this.pct);
  final String monitor;
  final int pct;
}

class VolumeSet extends DeckEvent {
  const VolumeSet(this.pct);
  final int pct;
}

class VolumeNudged extends DeckEvent {
  const VolumeNudged(this.delta);
  final int delta;
}

class MuteToggled extends DeckEvent {
  const MuteToggled({this.mic = false});
  final bool mic;
}

class DeviceSelected extends DeckEvent {
  const DeviceSelected(this.id, {this.source = false});
  final int id;
  final bool source;
}

class MediaPressed extends DeckEvent {
  const MediaPressed(this.action);
  final String action;
}

class SeekRequested extends DeckEvent {
  const SeekRequested(this.positionUs);
  final int positionUs;
}

class ContextKeyPressed extends DeckEvent {
  const ContextKeyPressed(this.cls, this.control);
  final String cls;
  final ContextControl control;
}

class ContextReloaded extends DeckEvent {
  const ContextReloaded();
}

class LockRequested extends DeckEvent {
  const LockRequested();
}

class ProcessKilled extends DeckEvent {
  const ProcessKilled(this.proc);
  final Proc proc;
}

class DeckState extends Equatable {
  const DeckState({
    this.frame = const DeckFrame(),
    this.link = Link.connecting,
    this.hasFrame = false,
    this.brightness = const {},
    this.volumeHold,
    this.context = const ContextConfig(),
  });
  final DeckFrame frame;
  final Link link;
  final bool hasFrame;
  final Map<String, int> brightness;
  final ContextConfig context;

  /// Locally chosen volume, shown until the rig has had time to report it.
  final int? volumeHold;

  int? get volume => volumeHold ?? frame.audio.volume;

  DeckState copyWith({
    DeckFrame? frame,
    Link? link,
    bool? hasFrame,
    Map<String, int>? brightness,
    int? Function()? volumeHold,
    ContextConfig? context,
  }) => DeckState(
    frame: frame ?? this.frame,
    link: link ?? this.link,
    hasFrame: hasFrame ?? this.hasFrame,
    brightness: brightness ?? this.brightness,
    volumeHold: volumeHold == null ? this.volumeHold : volumeHold(),
    context: context ?? this.context,
  );

  @override
  List<Object?> get props => [
    frame,
    link,
    hasFrame,
    brightness,
    volumeHold,
    context,
  ];
}

class DeckBloc extends Bloc<DeckEvent, DeckState> {
  DeckBloc(this.repo, this._notices) : super(const DeckState()) {
    on<DeckResumed>((_, _) {
      repo.start();
      repo.retryNow();
    });
    on<DeckPaused>((_, _) => repo.pause());
    on<_Frame>(
      (e, emit) => emit(state.copyWith(frame: e.frame, hasFrame: true)),
    );
    on<_LinkChanged>((e, emit) {
      emit(state.copyWith(link: e.link));
      if (e.link == Link.online) {
        add(const ContextReloaded());
        add(const BrightnessRequested());
      }
    });
    on<_HoldExpired>((e, emit) {
      if (e.seq == _holdSeq) emit(state.copyWith(volumeHold: () => null));
    });

    on<WorkspaceFocused>((e, _) => _do('/hypr/workspace', {'id': e.id}));
    on<WindowFocused>((e, _) => _do('/hypr/focus', {'address': e.address}));
    on<WindowMoved>(
      (e, _) =>
          _do('/hypr/move', {'address': e.address, 'workspace': e.workspace}),
    );
    on<DpmsSet>(
      (e, _) => _do('/hypr/dpms', {'monitor': e.monitor, 'on': e.on}),
    );

    on<BrightnessRequested>((_, emit) async {
      try {
        // ddcutil probing is slow the first time
        final j = await _c.getJson(
          '/brightness',
          timeout: const Duration(seconds: 45),
        );
        emit(
          state.copyWith(
            brightness: {
              for (final m in (j as Map).entries)
                '${m.key}': (m.value as num).toInt(),
            },
          ),
        );
      } on ApiException {
        // sliders simply stay hidden
      }
    });
    on<BrightnessSet>((e, emit) async {
      emit(state.copyWith(brightness: {...state.brightness, e.monitor: e.pct}));
      await _do('/brightness', {'monitor': e.monitor, 'pct': e.pct});
    });

    on<VolumeSet>((e, emit) => _setVolume(e.pct, emit));
    on<VolumeNudged>((e, emit) async {
      final v = state.volume;
      if (v != null) await _setVolume(v + e.delta, emit);
    });
    on<MuteToggled>(
      (e, _) => _do('/audio/mute', {'target': e.mic ? 'mic' : 'sink'}),
    );
    on<DeviceSelected>(
      (e, _) => _do(e.source ? '/audio/source' : '/audio/sink', {'id': e.id}),
    );
    on<MediaPressed>((e, _) => _do('/media/${e.action}'));
    on<SeekRequested>(
      (e, _) => _do('/media/seek', {'position_us': e.positionUs}),
    );

    on<ContextReloaded>((_, emit) async {
      try {
        final j = await _c.getJson('/context');
        emit(
          state.copyWith(context: ContextConfig.fromJson((j as Map).cast())),
        );
      } on ApiException {
        // strip stays as it was
      }
    });
    on<ContextKeyPressed>(
      (e, _) => _do('/context/key', {
        'cls': e.cls,
        'key': e.control.key,
        'mods': e.control.mods,
      }),
    );
    on<LockRequested>((_, _) async {
      if (await _do('/sys/lock')) _notices.info('Rig locked');
    });
    on<ProcessKilled>((e, _) async {
      if (await _do('/sys/kill', {'pid': e.proc.pid})) {
        _notices.info('Sent SIGTERM to ${e.proc.name}');
      }
    });

    _subs = [
      repo.frames.listen((f) => add(_Frame(f))),
      repo.links.listen((l) => add(_LinkChanged(l))),
    ];
  }

  final DeckRepository repo;
  final NoticeCubit _notices;
  HyprClient get _c => repo.client;
  late final List<StreamSubscription<Object>> _subs;

  int _holdSeq = 0;
  Timer? _holdTimer;
  int? _nextVolume;
  bool _sendingVolume = false;

  Future<bool> _do(String path, [Object? body]) async {
    try {
      await _c.call(path, body);
      return true;
    } on ApiException catch (e) {
      _notices.error(e);
      return false;
    }
  }

  /// Latest-wins: a drag produces many values but only one request in flight.
  Future<void> _setVolume(int pct, Emitter<DeckState> emit) async {
    final v = pct.clamp(0, 150);
    emit(state.copyWith(volumeHold: () => v));
    final seq = ++_holdSeq;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!isClosed) add(_HoldExpired(seq));
    });
    _nextVolume = v;
    if (_sendingVolume) return;
    _sendingVolume = true;
    try {
      while (_nextVolume != null) {
        final send = _nextVolume!;
        _nextVolume = null;
        await _do('/audio/volume', {'pct': send});
      }
    } finally {
      _sendingVolume = false;
    }
  }

  @override
  Future<void> close() async {
    _holdTimer?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    repo.dispose();
    return super.close();
  }
}
