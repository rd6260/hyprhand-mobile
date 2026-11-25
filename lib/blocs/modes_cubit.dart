import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../data/hypr_client.dart';
import '../data/models.dart';

class ModesState extends Equatable {
  const ModesState({
    this.items = const [],
    this.loading = true,
    this.error,
    this.running,
    this.output = const [],
  });
  final List<RigMode> items;
  final bool loading;
  final String? error, running;
  final List<String> output;
  @override
  List<Object?> get props => [items, loading, error, running, output];
}

class ModesCubit extends Cubit<ModesState> {
  ModesCubit(this._c) : super(const ModesState());
  final HyprClient _c;

  Future<void> load() async {
    try {
      final j = await _c.getJson('/modes') as List;
      if (isClosed) return;
      emit(
        ModesState(
          loading: false,
          output: state.output,
          items: [for (final e in j) RigMode.fromJson((e as Map).cast())],
        ),
      );
    } on ApiException catch (e) {
      if (!isClosed) emit(ModesState(loading: false, error: e.message));
    }
  }

  Future<void> run(RigMode m) async {
    if (state.running != null) return;
    final items = state.items;
    emit(
      ModesState(
        items: items,
        loading: false,
        running: m.id,
        output: ['applying ${m.label}…'],
      ),
    );
    List<String> out;
    try {
      // each launch step may wait 8 s for its window
      final r = await _c.call(
        '/modes/run',
        {'id': m.id},
        'POST',
        const Duration(minutes: 3),
      );
      out = [for (final s in (r['steps'] as List? ?? [])) '$s'];
      if (out.isEmpty) out = ['done — no steps'];
    } on ApiException catch (e) {
      out = ['✗ ${e.message}'];
    }
    if (!isClosed) emit(ModesState(items: items, loading: false, output: out));
  }
}
