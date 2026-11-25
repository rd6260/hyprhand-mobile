import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/bindings.dart';

class BindingsState extends Equatable {
  const BindingsState({this.enabled = false, this.map = const {}});
  final bool enabled;
  final Map<PhoneButton, ButtonBinding> map;

  ButtonBinding of(PhoneButton b) => map[b] ?? const ButtonBinding();

  /// On, and this button has something to do.
  bool armed(PhoneButton b) => enabled && of(b).steps.isNotEmpty;

  @override
  List<Object?> get props => [enabled, map];
}

class BindingsCubit extends Cubit<BindingsState> {
  BindingsCubit(this._p) : super(_load(_p));
  final SharedPreferences _p;

  static BindingsState _load(SharedPreferences p) {
    try {
      final j = jsonDecode(p.getString('bindings') ?? '{}') as Map;
      return BindingsState(
        enabled: j['on'] == true,
        map: {
          for (final b in PhoneButton.values)
            if (j[b.name] != null) b: ButtonBinding.fromJson(j[b.name]),
        },
      );
    } catch (_) {
      return const BindingsState();
    }
  }

  void _set(BindingsState s) {
    emit(s);
    _p.setString(
      'bindings',
      jsonEncode({
        'on': s.enabled,
        for (final e in s.map.entries) e.key.name: e.value.toJson(),
      }),
    );
  }

  void setEnabled(bool on) => _set(BindingsState(enabled: on, map: state.map));

  void _bind(PhoneButton b, ButtonBinding v) =>
      _set(BindingsState(enabled: state.enabled, map: {...state.map, b: v}));

  void setRepeat(PhoneButton b, bool on) =>
      _bind(b, ButtonBinding(steps: state.of(b).steps, repeat: on));

  void _steps(PhoneButton b, void Function(List<ActionStep>) edit) {
    final s = [...state.of(b).steps];
    edit(s);
    _bind(b, ButtonBinding(steps: s, repeat: state.of(b).repeat));
  }

  void add(PhoneButton b, ActionStep s) => _steps(b, (l) => l.add(s));
  void replace(PhoneButton b, int i, ActionStep s) =>
      _steps(b, (l) => l[i] = s);
  void removeAt(PhoneButton b, int i) => _steps(b, (l) => l.removeAt(i));
  void clear(PhoneButton b) => _steps(b, (l) => l.clear());
  void move(PhoneButton b, int i, int dir) => _steps(b, (l) {
    final j = i + dir;
    if (j >= 0 && j < l.length) l.insert(j, l.removeAt(i));
  });
}
