import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Known rigs (preferences) and their session tokens (Android Keystore).
class HostStore {
  HostStore(this._prefs, [this._secure = const FlutterSecureStorage()]);
  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  List<RigHost> hosts() {
    try {
      return [
        for (final s in _prefs.getStringList('hosts') ?? <String>[])
          RigHost.fromJson((jsonDecode(s) as Map).cast()),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(List<RigHost> h) => _prefs.setStringList('hosts', [
    for (final x in h) jsonEncode(x.toJson()),
  ]);

  Future<void> save(RigHost h) async {
    await _write([h, ...hosts().where((x) => x.url != h.url)]);
  }

  Future<void> remove(RigHost h) async {
    await _write(hosts().where((x) => x.url != h.url).toList());
    await clearToken(h);
    if (lastUrl == h.url) await setLast(null);
  }

  String? get lastUrl => _prefs.getString('last_host');
  Future<void> setLast(RigHost? h) async => h == null
      ? await _prefs.remove('last_host')
      : await _prefs.setString('last_host', h.url);

  Future<String?> token(RigHost h) async {
    try {
      return await _secure.read(key: 'token:${h.url}');
    } catch (_) {
      return null; // keystore reset: just ask for the PIN again
    }
  }

  Future<void> setToken(RigHost h, String t) async {
    try {
      await _secure.write(key: 'token:${h.url}', value: t);
    } catch (_) {
      /* session still works until the app is closed */
    }
  }

  Future<void> clearToken(RigHost h) async {
    try {
      await _secure.delete(key: 'token:${h.url}');
    } catch (_) {}
  }
}
