import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../data/deck_repository.dart';
import '../data/host_store.dart';
import '../data/hypr_client.dart';
import '../data/models.dart';

sealed class SessionEvent {
  const SessionEvent();
}

class SessionStarted extends SessionEvent {
  const SessionStarted();
}

class HostChosen extends SessionEvent {
  const HostChosen(this.host);
  final RigHost host;
}

class HostForgotten extends SessionEvent {
  const HostForgotten(this.host);
  final RigHost host;
}

class PinSubmitted extends SessionEvent {
  const PinSubmitted(this.pin);
  final String pin;
}

class SwitchRigPressed extends SessionEvent {
  const SwitchRigPressed();
}

class LoggedOut extends SessionEvent {
  const LoggedOut();
}

class SessionExpired extends SessionEvent {
  const SessionExpired(this.repo);
  final DeckRepository repo;
}

sealed class SessionState extends Equatable {
  const SessionState();
  @override
  List<Object?> get props => [];
}

class SessionLoading extends SessionState {
  const SessionLoading();
}

class SessionPicking extends SessionState {
  const SessionPicking(this.hosts);
  final List<RigHost> hosts;
  @override
  List<Object?> get props => [hosts];
}

class SessionLogin extends SessionState {
  const SessionLogin(this.host, {this.busy = false, this.error});
  final RigHost host;
  final bool busy;
  final String? error;
  @override
  List<Object?> get props => [host, busy, error];
}

class SessionActive extends SessionState {
  const SessionActive(this.repo);
  final DeckRepository repo;
  @override
  List<Object?> get props => [identityHashCode(repo)];
}

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  SessionBloc(this._store) : super(const SessionLoading()) {
    // One sequential handler: rig switches and logins must never interleave.
    on<SessionEvent>(
      (e, emit) async => switch (e) {
        SessionStarted() => await _start(emit),
        HostChosen(:final host) => await _open(host, emit),
        HostForgotten(:final host) => await _forget(host, emit),
        PinSubmitted(:final pin) => await _login(pin, emit),
        SwitchRigPressed() => await _toPicker(emit),
        LoggedOut() => await _logout(emit),
        SessionExpired(:final repo) => await _expire(repo, emit),
      },
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final HostStore _store;

  Future<void> _start(Emitter<SessionState> emit) async {
    final hosts = _store.hosts();
    for (final h in hosts) {
      if (h.url == _store.lastUrl) return _open(h, emit);
    }
    emit(SessionPicking(hosts));
  }

  Future<void> _open(RigHost host, Emitter<SessionState> emit) async {
    final token = await _store.token(host);
    await _store.save(host);
    if (token == null) {
      emit(SessionLogin(host));
      return;
    }
    await _activate(host, HyprClient(host.uri, token: token), emit);
  }

  Future<void> _activate(
    RigHost host,
    HyprClient client,
    Emitter<SessionState> emit,
  ) async {
    await _store.setLast(host);
    final repo = DeckRepository(host, client);
    client.onUnauthorized = () {
      if (!isClosed) add(SessionExpired(repo));
    };
    emit(SessionActive(repo));
  }

  Future<void> _login(String pin, Emitter<SessionState> emit) async {
    final s = state;
    if (s is! SessionLogin || s.busy) return;
    emit(SessionLogin(s.host, busy: true));
    final client = HyprClient(s.host.uri);
    try {
      await _store.setToken(s.host, await client.login(pin));
      await _activate(s.host, client, emit);
    } on ApiException catch (e) {
      client.close();
      emit(SessionLogin(s.host, error: e.message));
    }
  }

  Future<void> _forget(RigHost h, Emitter<SessionState> emit) async {
    await _store.remove(h);
    emit(SessionPicking(_store.hosts()));
  }

  Future<void> _toPicker(Emitter<SessionState> emit) async {
    await _store.setLast(null);
    emit(SessionPicking(_store.hosts()));
  }

  Future<void> _logout(Emitter<SessionState> emit) async {
    final s = state;
    if (s is! SessionActive) return;
    await _store.clearToken(s.repo.host);
    emit(SessionLogin(s.repo.host));
  }

  Future<void> _expire(DeckRepository repo, Emitter<SessionState> emit) async {
    final s = state;
    if (s is! SessionActive || !identical(s.repo, repo)) return;
    await _store.clearToken(repo.host);
    emit(
      SessionLogin(repo.host, error: 'Session expired — enter the PIN again'),
    );
  }
}
