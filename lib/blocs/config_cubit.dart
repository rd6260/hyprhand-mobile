import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../data/hypr_client.dart';

class ConfigState extends Equatable {
  const ConfigState({
    this.section = 'commands',
    this.text,
    this.busy = false,
    this.status,
    this.error = false,
  });
  final String section;

  /// Pretty JSON as last loaded; null while loading.
  final String? text;
  final bool busy, error;
  final String? status;
  @override
  List<Object?> get props => [section, text, busy, status, error];
}

class ConfigCubit extends Cubit<ConfigState> {
  ConfigCubit(this._c) : super(const ConfigState());
  final HyprClient _c;

  static const sections = [
    'commands',
    'modes',
    'context',
    'fleet',
    'theme',
    'state',
    'auth',
    'server',
  ];

  Future<Map<String, dynamic>> _fetch() async =>
      ((await _c.getJson('/api/config')) as Map).cast<String, dynamic>();

  static String pretty(Object? v) =>
      const JsonEncoder.withIndent('  ').convert(v);

  Future<void> open(String section) async {
    emit(ConfigState(section: section, busy: true));
    try {
      final cfg = await _fetch();
      if (isClosed || state.section != section) return;
      emit(ConfigState(section: section, text: pretty(cfg[section])));
    } on ApiException catch (e) {
      if (isClosed || state.section != section) return;
      emit(ConfigState(section: section, status: e.message, error: true));
    }
  }

  /// Replaces just this section in a freshly read config.
  Future<bool> save(String text) async {
    final s = state;
    if (s.busy || s.text == null) return false;
    ConfigState fail(String m) =>
        ConfigState(section: s.section, text: s.text, status: m, error: true);
    final Object? value;
    try {
      value = jsonDecode(text);
    } on FormatException catch (e) {
      emit(fail('Not valid JSON: ${e.message}'));
      return false;
    }
    emit(ConfigState(section: s.section, text: s.text, busy: true));
    try {
      final cfg = await _fetch();
      if (pretty(cfg[s.section]) != s.text) {
        if (!isClosed) {
          emit(fail('Changed on the rig since you opened it — reload first'));
        }
        return false;
      }
      cfg[s.section] = value;
      await _c.call('/api/config', cfg, 'PUT');
      final fresh = await _fetch();
      if (isClosed) return true;
      emit(
        ConfigState(
          section: s.section,
          text: pretty(fresh[s.section]),
          status: s.section == 'server'
              ? 'Saved — restart hyprhand to apply'
              : 'Saved',
        ),
      );
      return true;
    } on ApiException catch (e) {
      if (!isClosed) emit(fail(e.message));
      return false;
    }
  }
}
