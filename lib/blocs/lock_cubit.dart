import 'dart:async';

import 'package:bloc/bloc.dart';

import '../data/native.dart';

/// True while the phone is locked and we may be showing over the lock screen.
class LockCubit extends Cubit<bool> {
  LockCubit(Native native, {bool locked = false}) : super(locked) {
    _sub = native.lockChanges.listen(emit);
    // Catch a lock or unlock that happened before we were listening.
    native.isLocked().then((l) {
      if (!isClosed) emit(l);
    });
  }
  late final StreamSubscription<bool> _sub;

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
