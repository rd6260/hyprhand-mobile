import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Looks for hyprhand servers on the phone's own /24 networks, port 8765.
Stream<RigHost> scanLan() async* {
  final nets = <String>{};
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in i.addresses) {
      final p = a.address.split('.');
      final o1 = int.parse(p[0]), o2 = int.parse(p[1]);
      final private =
          o1 == 10 ||
          (o1 == 172 && o2 >= 16 && o2 < 32) ||
          (o1 == 192 && o2 == 168);
      if (private) nets.add(p.take(3).join('.'));
    }
  }
  final targets = [
    for (final n in nets)
      for (var i = 1; i < 255; i++) '$n.$i',
  ];
  final out = StreamController<RigHost>();
  var next = 0;
  Future<void> worker() async {
    while (next < targets.length && !out.isClosed) {
      final ip = targets[next++];
      if (await _isHyprhand(ip)) {
        out.add(RigHost(url: 'http://$ip:8765', label: ip));
      }
    }
  }

  out.onCancel = () => next = targets.length;
  unawaited(
    Future.wait([for (var i = 0; i < 48; i++) worker()])
        .whenComplete(out.close),
  );
  yield* out.stream;
}

Future<bool> _isHyprhand(String ip) async {
  try {
    final s = await Socket.connect(
      ip,
      8765,
      timeout: const Duration(milliseconds: 600),
    );
    s.destroy();
  } catch (_) {
    return false;
  }
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    return await () async {
      final r = await (await c.getUrl(
        Uri.parse('http://$ip:8765/static/manifest.webmanifest'),
      )).close();
      final j = jsonDecode(await utf8.decodeStream(r));
      return j is Map && j['name'] == 'hyprhand';
    }().timeout(const Duration(seconds: 3));
  } catch (_) {
    return false;
  } finally {
    c.close(force: true);
  }
}
