import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../data/hypr_client.dart';

class ScreenState extends Equatable {
  const ScreenState({this.running = false, this.png, this.frameMs, this.error});
  final bool running;
  final Uint8List? png;
  final int? frameMs;
  final String? error;
  @override
  List<Object?> get props => [running, identityHashCode(png), frameMs, error];
}

/// Live view built from back-to-back screenshots (the server has no video
/// stream). One request at a time, so it self-paces to the network.
class ScreenCubit extends Cubit<ScreenState> {
  ScreenCubit(this._c) : super(const ScreenState());
  final HyprClient _c;
  int _gen = 0;

  Future<void> start(String monitor) async {
    final gen = ++_gen;
    bool live() => !isClosed && gen == _gen;
    emit(const ScreenState(running: true));
    var failures = 0;
    while (live()) {
      final sw = Stopwatch()..start();
      try {
        final png = await _c.getBytes(
          '/screenshot',
          query: {'monitor': monitor},
        );
        if (!live()) return;
        failures = 0;
        emit(
          ScreenState(running: true, png: png, frameMs: sw.elapsedMilliseconds),
        );
      } on ApiException catch (e) {
        if (!live()) return;
        if (++failures >= 3) {
          emit(
            ScreenState(
              png: state.png,
              error: e.status == 404
                  ? "The rig couldn't capture $monitor"
                  : e.message,
            ),
          );
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      final rest = 120 - sw.elapsedMilliseconds;
      if (rest > 0) await Future<void>.delayed(Duration(milliseconds: rest));
    }
  }

  void stop() {
    _gen++;
    if (!isClosed) emit(ScreenState(png: state.png));
  }

  @override
  Future<void> close() {
    _gen++;
    return super.close();
  }
}
