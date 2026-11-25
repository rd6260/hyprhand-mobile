import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyprhand_mobile/blocs/commands_cubit.dart';
import 'package:hyprhand_mobile/blocs/config_cubit.dart';
import 'package:hyprhand_mobile/blocs/deck_bloc.dart';
import 'package:hyprhand_mobile/blocs/notice_cubit.dart';
import 'package:hyprhand_mobile/blocs/session_bloc.dart';
import 'package:hyprhand_mobile/data/deck_repository.dart';
import 'package:hyprhand_mobile/data/deck_socket.dart';
import 'package:hyprhand_mobile/data/host_store.dart';
import 'package:hyprhand_mobile/data/hypr_client.dart';
import 'package:hyprhand_mobile/data/input_message.dart';
import 'package:hyprhand_mobile/data/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Behaves like the real server, including its 2 MB body quirk.
class FakeRig {
  late HttpServer s;
  String token = 'tok1';
  final calls = <String>[];
  final input = <String>[];
  final sockets = <WebSocket>[];
  List<Map> commands = [
    {'id': 0, 'label': 'A', 'cmd': 'true'},
  ];
  Map<String, dynamic> config = {'commands': [], 'modes': []};
  Duration volumeDelay = Duration.zero;
  Uri get base => Uri.parse('http://127.0.0.1:${s.port}');

  Future<void> start([int port = 0]) async {
    s = await HttpServer.bind('127.0.0.1', port);
    s.listen((r) async {
      try {
        await _handle(r);
      } catch (_) {}
    });
  }

  Future<void> _handle(HttpRequest r) async {
    Future<void> out(Object o, [int code = 200]) {
      r.response.statusCode = code;
      r.response.write(o is String ? o : jsonEncode(o));
      return r.response.close();
    }

    final path = r.uri.path;
    if (path == '/login') {
      final pin = (jsonDecode(await utf8.decodeStream(r)) as Map)['pin'];
      if (pin != '1234') return out({'ok': false, 'error': 'invalid PIN'}, 401);
      r.response.headers.add(
        'set-cookie',
        'hyprhand_session=$token; HttpOnly; SameSite=Strict; Secure; Path=/',
      );
      return out({'ok': true});
    }
    if (!r.cookies.any(
      (c) => c.name == 'hyprhand_session' && c.value == token,
    )) {
      return out('auth required', 401);
    }
    if (path.startsWith('/ws')) {
      final ws = await WebSocketTransformer.upgrade(r);
      sockets.add(ws);
      if (path == '/ws') {
        ws.add('not json');
        ws.add(
          jsonEncode({
            'audio': {'volume': 30},
          }),
        );
        ws.listen((_) {});
      } else {
        ws.listen((m) => input.add(m as String));
      }
      return;
    }
    final body = <int>[];
    await for (final c in r) {
      body.addAll(c);
    }
    calls.add(
      '${r.method} $path ${body.length < 200 ? utf8.decode(body, allowMalformed: true) : ''}',
    );
    switch (path) {
      case '/upload':
        final big = body.length > 2097152;
        final raw = latin1.decode(body);
        final start = raw.indexOf('\r\n\r\n') + 4;
        final size = raw.lastIndexOf('\r\n--') - start;
        return out({'ok': true, 'name': 'f', 'size': big ? 0 : size});
      case '/commands':
        return out(commands);
      case '/audio/volume':
        await Future<void>.delayed(volumeDelay);
        return out({'ok': true});
      case '/hypr/focus':
        return out({'ok': false});
      case '/api/config':
        if (r.method == 'PUT') {
          config = (jsonDecode(utf8.decode(body)) as Map).cast();
        }
        return out(r.method == 'PUT' ? {'ok': true} : config);
      case '/commands/run' || '/input/available':
        return out({'ok': true});
    }
    return out('', 404);
  }

  Future<void> stop() async {
    for (final w in sockets) {
      await w.close();
    }
    sockets.clear();
    await s.close(force: true);
  }
}

Future<void> until(bool Function() f) async {
  final sw = Stopwatch()..start();
  while (!f()) {
    if (sw.elapsed > const Duration(seconds: 8)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late FakeRig rig;
  late HyprClient client;
  late NoticeCubit notices;
  setUp(() async {
    HttpOverrides.global = null; // flutter_test blocks real sockets
    rig = FakeRig();
    await rig.start();
    client = HyprClient(rig.base, token: 'tok1');
    notices = NoticeCubit();
  });
  tearDown(() async {
    client.close();
    await rig.stop();
  });

  test('login carries the Secure cookie over plain http', () async {
    final c = HyprClient(rig.base);
    expect(await c.sessionValid(), isFalse);
    await expectLater(c.login('9'), throwsA(isA<ApiException>()));
    expect(await c.login('1234'), 'tok1');
    expect(await c.sessionValid(), isTrue);
  });

  test('missing routes and refusals surface as errors', () async {
    await expectLater(
      client.call('/media/next'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
    );
    await expectLater(
      client.call('/hypr/focus', {}),
      throwsA(isA<ApiException>()),
    );
  });

  test('upload verifies stored size', () async {
    final d = await Directory.systemTemp.createTemp();
    final small = await File('${d.path}/s').writeAsBytes(List.filled(5000, 65));
    final big = await File('${d.path}/b')
        .writeAsBytes(List.filled(3000000, 65));
    expect((await client.upload(small, 's"\r\n.bin'))['ok'], isTrue);
    await expectLater(
      client.upload(big, 'b.bin'),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'm', contains('2 MB')),
      ),
    );
    await d.delete(recursive: true);
  });

  test('socket reconnects after the rig restarts', () async {
    final s = DeckSocket(client, '/ws');
    final links = <Link>[];
    s.links.listen(links.add);
    s.start();
    await until(() => links.contains(Link.online));
    final port = rig.s.port;
    await rig.stop();
    await until(() => links.last != Link.online);
    await rig.start(port);
    await until(() => links.last == Link.online);
    s.dispose();
  });

  test('expired session on the socket asks for login', () async {
    var expired = 0;
    client
      ..token = 'old'
      ..onUnauthorized = () => expired++;
    final s = DeckSocket(client, '/ws')..start();
    await until(() => expired == 1);
    s.dispose();
  });

  test('deck bloc: frames, input, latest-wins volume, refusals', () async {
    final repo = DeckRepository(
      RigHost(url: '${rig.base}', label: 'x'),
      client,
    );
    final bloc = DeckBloc(repo, notices)..add(const DeckResumed());
    await until(() => bloc.state.volume == 30);
    await until(() => repo.send(InputMessage.click('left')));
    await until(() => rig.input.isNotEmpty);
    expect(jsonDecode(rig.input.first), {'t': 'click', 'b': 'left'});

    rig.volumeDelay = const Duration(milliseconds: 150);
    for (var v = 31; v <= 60; v++) {
      bloc.add(VolumeSet(v));
    }
    await until(
      () => rig.calls.where((c) => c.contains('"pct":60')).isNotEmpty,
    );
    expect(
      rig.calls.where((c) => c.contains('/audio/volume')).length,
      lessThan(4),
    );
    expect(bloc.state.volume, 60);

    bloc.add(const WindowFocused('0x1'));
    await until(() => notices.state?.error ?? false);
    await bloc.close();
  });

  test('a command whose position changed is not run', () async {
    final cubit = CommandsCubit(client, notices);
    await cubit.load();
    rig.commands = [
      {'id': 0, 'label': 'Danger', 'cmd': 'rm'},
    ];
    await cubit.run(cubit.state.items.single);
    expect(rig.calls.any((c) => c.contains('/commands/run')), isFalse);
    expect(cubit.state.items.single.label, 'Danger');
    await cubit.run(cubit.state.items.single);
    expect(rig.calls.any((c) => c.contains('/commands/run')), isTrue);
    await cubit.close();
  });

  test('config: bad JSON and concurrent edits never reach the rig', () async {
    final cubit = ConfigCubit(client);
    await cubit.open('modes');
    expect(await cubit.save('[oops'), isFalse);
    rig.config['modes'] = [1];
    expect(await cubit.save('[2]'), isFalse);
    expect(rig.config['modes'], [1]);
    await cubit.open('modes');
    expect(await cubit.save('[2]'), isTrue);
    expect(rig.config, {
      'commands': [],
      'modes': [2],
    });
    await cubit.close();
  });

  test('session: pick → login → active → expiry → login', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final store = HostStore(await SharedPreferences.getInstance());
    final b = SessionBloc(store)..add(const SessionStarted());
    await until(() => b.state is SessionPicking);
    b.add(HostChosen(RigHost(url: '${rig.base}', label: 'x')));
    await until(() => b.state is SessionLogin);
    b.add(const PinSubmitted('0'));
    await until(() => (b.state as SessionLogin).error == 'invalid PIN');
    b.add(const PinSubmitted('1234'));
    await until(() => b.state is SessionActive);

    final again = SessionBloc(store)..add(const SessionStarted());
    await until(() => again.state is SessionActive);

    rig.token = 'tok2';
    (b.state as SessionActive).repo.start();
    await until(() => b.state is SessionLogin);
    expect(await store.token(store.hosts().single), isNull);
    await b.close();
    await again.close();
  });
}
