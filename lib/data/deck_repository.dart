import 'dart:convert';

import 'deck_socket.dart';
import 'hypr_client.dart';
import 'input_message.dart';
import 'models.dart';

/// Everything live for one logged-in rig.
class DeckRepository {
  DeckRepository(this.host, this.client)
    : _state = DeckSocket(client, '/ws'),
      _input = DeckSocket(client, '/ws/input');

  final RigHost host;
  final HyprClient client;
  final DeckSocket _state;
  final DeckSocket _input;

  Stream<Link> get links => _state.links;

  Stream<DeckFrame> get frames => _state.messages.expand((m) {
    try {
      return [DeckFrame.fromJson((jsonDecode(m) as Map).cast())];
    } catch (_) {
      return const <DeckFrame>[]; // a malformed frame must not kill the feed
    }
  });

  void start() {
    _state.start();
    _input.start();
  }

  void pause() {
    _state.stop();
    _input.stop();
  }

  void retryNow() {
    _state.retryNow();
    _input.retryNow();
  }

  bool send(InputMessage m) => _input.send(jsonEncode(m.json));

  void dispose() {
    _state.dispose();
    _input.dispose();
    client.close();
  }
}
