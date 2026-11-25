import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../data/hypr_client.dart';
import '../data/models.dart';
import 'notice_cubit.dart';

class CommandsState extends Equatable {
  const CommandsState({
    this.items = const [],
    this.loading = true,
    this.error,
    this.running = const {},
  });
  final List<RigCommand> items;
  final bool loading;
  final String? error;
  final Set<int> running;
  CommandsState copyWith({Set<int>? running}) => CommandsState(
    items: items,
    loading: loading,
    error: error,
    running: running ?? this.running,
  );
  @override
  List<Object?> get props => [items, loading, error, running];
}

class CommandsCubit extends Cubit<CommandsState> {
  CommandsCubit(this._c, this._n) : super(const CommandsState());
  final HyprClient _c;
  final NoticeCubit _n;

  Future<void> load() async {
    try {
      final j = await _c.getJson('/commands') as List;
      if (isClosed) return;
      emit(
        CommandsState(
          loading: false,
          items: [for (final e in j) RigCommand.fromJson((e as Map).cast())],
        ),
      );
    } on ApiException catch (e) {
      if (!isClosed) {
        emit(
          CommandsState(items: state.items, loading: false, error: e.message),
        );
      }
    }
  }

  Future<void> run(RigCommand c) async {
    if (state.running.contains(c.id)) return;
    emit(state.copyWith(running: {...state.running, c.id}));
    try {
      // Ids are list positions: make sure ours still means the same command.
      final j = await _c.getJson('/commands') as List;
      final now = [for (final e in j) RigCommand.fromJson((e as Map).cast())];
      if (!now.contains(c)) {
        _n.error('Commands changed on the rig — list refreshed, tap again');
        await load();
        return;
      }
      final r = await _c.call('/commands/run', {'id': c.id});
      _n.info('${c.label}: ${r['status'] ?? 'done'}');
    } on ApiException catch (e) {
      _n.error('${c.label}: ${e.message}');
    } finally {
      if (!isClosed) {
        emit(state.copyWith(running: {...state.running}..remove(c.id)));
      }
    }
  }

  Future<bool> save({int? id, required String label, required String cmd}) =>
      _mutate('/commands/save', {'id': ?id, 'label': label, 'cmd': cmd});
  Future<bool> delete(int id) => _mutate('/commands/delete', {'id': id});
  Future<bool> move(int id, int dir) =>
      _mutate('/commands/move', {'id': id, 'dir': dir});

  Future<bool> _mutate(String path, Object body) async {
    try {
      await _c.call(path, body);
      return true;
    } on ApiException catch (e) {
      _n.error(e);
      return false;
    } finally {
      await load();
    }
  }
}
