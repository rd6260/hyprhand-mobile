import 'package:bloc/bloc.dart';

import '../data/bindings.dart';
import '../data/hypr_client.dart';
import '../data/input_message.dart';
import '../data/models.dart';
import 'bindings_cubit.dart';
import 'deck_bloc.dart';
import 'notice_cubit.dart';

sealed class MacroEvent {
  const MacroEvent();
}

class ButtonPressed extends MacroEvent {
  const ButtonPressed(this.button, {this.held = false});
  final PhoneButton button;

  /// Auto-repeat from holding the button down.
  final bool held;
}

/// Try a chain from the editor, whether or not the buttons are switched on.
class ChainTested extends MacroEvent {
  const ChainTested(this.button);
  final PhoneButton button;
}

/// Runs button chains one at a time, in press order. State: what's running.
class MacroBloc extends Bloc<MacroEvent, PhoneButton?> {
  MacroBloc(this._deck, this._bindings, this._notices) : super(null) {
    on<MacroEvent>(
      _run,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }
  final DeckBloc _deck;
  final BindingsCubit _bindings;
  final NoticeCubit _notices;

  static const _maxQueued = 4;
  int _queued = 0;

  @override
  void add(MacroEvent event) {
    // Mashing or holding a button must not build a backlog of slow chains.
    final held = event is ButtonPressed && event.held;
    if (_queued >= (held ? 1 : _maxQueued)) return;
    if (held && !_bindings.state.of(event.button).repeat) return;
    _queued++;
    super.add(event);
  }

  Future<void> _run(MacroEvent e, Emitter<PhoneButton?> emit) async {
    final (button, test) = switch (e) {
      ButtonPressed(:final button) => (button, false),
      ChainTested(:final button) => (button, true),
    };
    emit(button);
    try {
      for (final s in _bindings.state.of(button).steps) {
        if (isClosed || (!test && !_bindings.state.enabled)) return;
        await _step(s);
      }
    } on ApiException catch (err) {
      _notices.error(
        ApiException('${button.label}: ${err.message}', err.status),
      );
    } finally {
      _queued--;
      if (!isClosed) emit(null);
    }
  }

  void _send(InputMessage m) {
    if (!_deck.repo.send(m)) throw const ApiException('not connected');
  }

  Future<void> _step(ActionStep s) async {
    final c = _deck.repo.client;
    final v = s.args.first;
    switch (s.kind) {
      case StepKind.keys:
        _send(InputMessage.combo(s.args));
      case StepKind.text:
        _send(InputMessage.text(v));
      case StepKind.click:
        _send(InputMessage.click(v));
      case StepKind.scroll:
        _send(InputMessage.scroll(dy: v == 'up' ? 3 : -3));
      case StepKind.media:
        await c.call('/media/$v');
      case StepKind.volume:
        switch (v) {
          case 'up':
            _deck.add(const VolumeNudged(5));
          case 'down':
            _deck.add(const VolumeNudged(-5));
          default:
            await c.call('/audio/mute', {
              'target': v == 'mic' ? 'mic' : 'sink',
            });
        }
      case StepKind.workspace:
        await c.call('/hypr/workspace', {'id': int.tryParse(v) ?? 1});
      case StepKind.command:
        // Saved by content: ids are list positions and shift on the rig.
        final list = await c.getJson('/commands') as List;
        for (final e in list) {
          final cmd = RigCommand.fromJson((e as Map).cast());
          if (cmd.label == v && cmd.cmd == s.args[1]) {
            await c.call('/commands/run', {'id': cmd.id});
            return;
          }
        }
        throw ApiException('“$v” is no longer on this rig');
      case StepKind.wait:
        await Future<void>.delayed(
          Duration(milliseconds: (int.tryParse(v) ?? 0).clamp(0, 10000)),
        );
    }
  }
}
