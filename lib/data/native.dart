import 'dart:async';

import 'package:flutter/services.dart';

class PickedFile {
  const PickedFile(this.path, this.name, this.size);
  factory PickedFile.from(Map m) =>
      PickedFile(m['path'], m['name'], (m['size'] as num).toInt());
  final String path, name;
  final int size;
}

class SharePayload {
  const SharePayload(this.text, this.files);
  final String? text;
  final List<PickedFile> files;
}

/// Bridge to MainActivity.kt.
class Native {
  Native() {
    _ch.setMethodCallHandler((c) async {
      switch (c.method) {
        case 'volumeKey':
          final m = c.arguments as Map;
          _volume.add((m['dir'] as int, m['held'] as bool));
        case 'powerKey':
          lastPower = DateTime.now();
          _power.add(null);
        case 'screenOn':
          lastScreenOn = DateTime.now();
          _screenOn.add(null);
        case 'locked':
          _lock.add(c.arguments as bool);
        case 'shareReady':
          _shareReady.add(null);
        case 'shortcut':
          _shortcuts.add(c.arguments as String);
      }
    });
  }
  static const _ch = MethodChannel('hyprhand/native');
  final _volume = StreamController<(int, bool)>.broadcast();
  final _screenOn = StreamController<void>.broadcast();
  final _lock = StreamController<bool>.broadcast();
  final _power = StreamController<void>.broadcast();
  final _shareReady = StreamController<void>.broadcast();
  final _shortcuts = StreamController<String>.broadcast();

  /// (+1 / -1, auto-repeat from holding)
  Stream<(int, bool)> get volumeKeys => _volume.stream;

  /// The press that locks the phone arrives before standby can listen.
  DateTime? lastPower, lastScreenOn;
  Stream<void> get screenOn => _screenOn.stream;

  Stream<bool> get lockChanges => _lock.stream;
  Stream<void> get powerKey => _power.stream;
  Stream<void> get shareReady => _shareReady.stream;
  Stream<String> get shortcuts => _shortcuts.stream;

  Future<T?> _try<T>(String m, [Object? a]) async {
    try {
      return await _ch.invokeMethod<T>(m, a);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> keepAwake(bool on) => _try('keepAwake', on);
  Future<bool> isLocked() async => await _try<bool>('isLocked') ?? false;
  Future<void> standbyShown() => _try('standbyShown');

  /// Brings up the system unlock prompt; never unlocks by itself.
  Future<void> requestUnlock() => _try('requestUnlock');

  Future<void> captureKeys({
    bool up = false,
    bool down = false,
    bool power = false,
  }) => _try('captureKeys', {'up': up, 'down': down, 'power': power});
  Future<String?> takeShortcut() => _try('takeShortcut');
  Future<bool> saveImage(Uint8List png, String name) async =>
      await _try<bool>('saveImage', {'bytes': png, 'name': name}) ?? false;

  Future<List<PickedFile>> pickFiles() async => [
    for (final m in await _try<List>('pickFiles') ?? []) PickedFile.from(m),
  ];

  Future<SharePayload?> takeShare() async {
    final m = await _try<Map>('takeShare');
    if (m == null) return null;
    return SharePayload(m['text'], [
      for (final f in m['files'] as List) PickedFile.from(f),
    ]);
  }

  /// (percent, charging)
  Future<(int, bool)?> battery() async {
    final m = await _try<Map>('battery');
    return m == null ? null : (m['level'] as int, m['charging'] as bool);
  }
}
