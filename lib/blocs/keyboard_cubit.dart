import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../data/input_message.dart';

enum ModState { off, once, locked }

class KeyboardState extends Equatable {
  const KeyboardState({this.mods = const {}, this.caps = false});
  final Map<String, ModState> mods;
  final bool caps;

  bool isOn(String m) => (mods[m] ?? ModState.off) != ModState.off;
  bool get shift => isOn('shift');
  bool get upper => shift != caps;
  @override
  List<Object?> get props => [mods, caps];
}

/// On-screen keyboard modifier logic. Tap a modifier to apply it to the next
/// key; long-press to hold it down until tapped again.
class KeyboardCubit extends Cubit<KeyboardState> {
  KeyboardCubit(this._send) : super(const KeyboardState());
  final void Function(InputMessage) _send;

  static const order = ['ctrl', 'alt', 'shift', 'super'];

  void toggleMod(String m, {bool lock = false}) {
    final next = lock
        ? ModState.locked
        : (state.isOn(m) ? ModState.off : ModState.once);
    emit(KeyboardState(mods: {...state.mods, m: next}, caps: state.caps));
  }

  /// Caps stays on the phone. Letters are sent already shifted, so toggling
  /// the rig's CapsLock as well would invert them back.
  void toggleCaps() => emit(KeyboardState(mods: state.mods, caps: !state.caps));

  void special(String key) {
    _send(InputMessage.combo([..._active, key]));
    _release();
  }

  void char(String base, {String? shifted}) {
    final letter = RegExp(r'^[a-z]$').hasMatch(base);
    if (_active.any((m) => m != 'shift')) {
      _send(InputMessage.combo([..._active, base]));
    } else if (letter) {
      _send(InputMessage.text(state.upper ? base.toUpperCase() : base));
    } else {
      _send(InputMessage.text(state.shift ? (shifted ?? base) : base));
    }
    _release();
  }

  List<String> get _active => [
    for (final m in order)
      if (state.isOn(m)) m,
  ];

  void _release() {
    if (!state.mods.values.contains(ModState.once)) return;
    emit(
      KeyboardState(
        caps: state.caps,
        mods: {
          for (final e in state.mods.entries)
            if (e.value == ModState.locked) e.key: e.value,
        },
      ),
    );
  }
}

/// Diffs the system keyboard's text field into rig keystrokes, so autocorrect,
/// swipe typing and voice dictation all work.
List<InputMessage> diffTyping(String before, String after) {
  var p = 0;
  while (p < before.length && p < after.length && before[p] == after[p]) {
    p++;
  }
  // Don't split a surrogate pair: one backspace on the rig is one character.
  if (p > 0 &&
      p < before.length &&
      (before.codeUnitAt(p - 1) & 0xFC00) == 0xD800) {
    p--;
  }
  final removed = before.substring(p).runes.where(typeable).length;
  final added = String.fromCharCodes(after.substring(p).runes.where(typeable));
  return [
    for (var i = 0; i < removed; i++) InputMessage.combo(const ['backspace']),
    if (added.isNotEmpty) InputMessage.text(added),
  ];
}

/// The server types through a US layout: printable ASCII, newline and tab.
bool typeable(int r) => (r >= 0x20 && r < 0x7F) || r == 0x0A || r == 0x09;
