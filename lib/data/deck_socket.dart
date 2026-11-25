import 'dart:async';
import 'dart:io';

import 'hypr_client.dart';

enum Link { offline, connecting, online }

/// A WebSocket that keeps itself alive: exponential backoff, ping-based dead
/// peer detection, and pause/resume with the app lifecycle.
class DeckSocket {
  DeckSocket(this.client, this.path);
  final HyprClient client;
  final String path;

  final _messages = StreamController<String>.broadcast();
  final _links = StreamController<Link>.broadcast();
  Stream<String> get messages => _messages.stream;
  Stream<Link> get links => _links.stream;

  WebSocket? _ws;
  Timer? _retry;
  bool _active = false;
  bool _connecting = false;
  int _attempt = 0;
  int _generation = 0;
  Link _link = Link.offline;

  void start() {
    if (_active) return;
    _active = true;
    _attempt = 0;
    _connect();
  }

  void stop() {
    _active = false;
    _generation++;
    _connecting = false;
    _retry?.cancel();
    _ws?.close();
    _ws = null;
    _set(Link.offline);
  }

  /// Skip any pending backoff.
  void retryNow() {
    if (!_active || _ws != null || _connecting) return;
    _attempt = 0;
    _retry?.cancel();
    _connect();
  }

  bool send(String data) {
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) return false;
    ws.add(data);
    return true;
  }

  void _set(Link l) {
    if (l == _link || _links.isClosed) return;
    _link = l;
    _links.add(l);
  }

  Future<void> _connect() async {
    final gen = ++_generation;
    bool current() => _active && gen == _generation;
    _connecting = true;
    _set(Link.connecting);
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final ws = await WebSocket.connect(
        client.wsUrl(path).toString(),
        headers: client.authHeaders,
        customClient: http,
      ).timeout(const Duration(seconds: 9));
      if (!current()) {
        ws.close();
        return;
      }
      ws.pingInterval = const Duration(seconds: 8);
      _connecting = false;
      _ws = ws;
      _attempt = 0;
      _set(Link.online);
      try {
        await for (final m in ws) {
          if (!current()) return;
          if (m is String) _messages.add(m);
        }
      } catch (_) {
        /* dropped: fall through to retry */
      }
    } catch (_) {
      if (!current()) return;
      if (await client.sessionValid() == false) {
        if (current()) client.onUnauthorized?.call();
        return;
      }
    } finally {
      http.close(force: gen != _generation);
      if (gen == _generation) {
        _connecting = false;
        _ws = null;
      }
    }
    if (!current()) return;
    _set(Link.offline);
    final secs = [1, 2, 3, 5, 8][_attempt.clamp(0, 4)];
    _attempt++;
    _retry = Timer(Duration(seconds: secs), () {
      if (current()) _connect();
    });
  }

  void dispose() {
    stop();
    _messages.close();
    _links.close();
  }
}
