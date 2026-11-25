import 'package:equatable/equatable.dart';

typedef Json = Map<String, dynamic>;

Json _map(Object? v) => v is Map ? v.cast<String, dynamic>() : const {};
List<T> _list<T>(Object? v, T Function(Json) f) =>
    v is List ? [for (final e in v) f(_map(e))] : <T>[];
int? _int(Object? v) => (v as num?)?.toInt();
double? _dbl(Object? v) => (v as num?)?.toDouble();

/// A rig the app knows about.
class RigHost extends Equatable {
  const RigHost({required this.url, required this.label});
  final String url;
  final String label;

  Uri get uri => Uri.parse(url);
  bool get insecure => uri.scheme != 'https';

  Json toJson() => {'url': url, 'label': label};
  factory RigHost.fromJson(Json j) =>
      RigHost(url: j['url'] as String, label: j['label'] as String);

  /// Accepts `192.168.1.4`, `host:8765`, `https://rig.tailnet.ts.net`, …
  /// Bare Tailscale names mean HTTPS (tailscale serve), everything else is
  /// plain HTTP on hyprhand's default port. Returns null when unparseable.
  static RigHost? parse(String raw, {String? label}) {
    var s = raw.trim();
    if (s.isEmpty || s.contains(RegExp(r'\s'))) return null;
    final hadScheme = s.contains('://');
    if (!hadScheme) {
      final host = s.split(RegExp('[:/]')).first;
      s = host.endsWith('.ts.net') ? 'https://$s' : 'http://$s';
    }
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return null;
    if (u.scheme != 'http' && u.scheme != 'https') return null;
    final defaultPort = !hadScheme && u.scheme == 'http' && !u.hasPort;
    final clean = Uri(
      scheme: u.scheme,
      host: u.host,
      port: defaultPort ? 8765 : (u.hasPort ? u.port : null),
    );
    final name = RegExp(r'^[\d.]+$').hasMatch(u.host)
        ? u.host
        : u.host.split('.').first;
    return RigHost(url: clean.toString(), label: label ?? name);
  }

  @override
  List<Object?> get props => [url, label];
}

class Monitor extends Equatable {
  const Monitor(
    this.name,
    this.model,
    this.w,
    this.h,
    this.refresh,
    this.activeWs,
    this.focused,
    this.dpms,
  );
  factory Monitor.fromJson(Json j) => Monitor(
    j['name'] ?? '',
    j['model'] ?? '',
    _int(j['w']) ?? 0,
    _int(j['h']) ?? 0,
    _int(j['refresh']) ?? 0,
    _int(j['active_ws']),
    j['focused'] ?? false,
    j['dpms'] ?? true,
  );
  final String name, model;
  final int w, h, refresh;
  final int? activeWs;
  final bool focused, dpms;
  @override
  List<Object?> get props => [
    name,
    model,
    w,
    h,
    refresh,
    activeWs,
    focused,
    dpms,
  ];
}

class RigWindow extends Equatable {
  const RigWindow(
    this.address,
    this.title,
    this.cls,
    this.ws,
    this.monitor,
    this.focused,
  );
  factory RigWindow.fromJson(Json j) => RigWindow(
    j['address'] ?? '',
    j['title'] ?? '',
    j['cls'] ?? '',
    _int(j['ws']),
    j['monitor'] ?? '',
    j['focused'] ?? false,
  );
  final String address, title, cls, monitor;
  final int? ws;
  final bool focused;
  String get display => title.isNotEmpty ? title : (cls.isNotEmpty ? cls : '?');
  @override
  List<Object?> get props => [address, title, cls, ws, monitor, focused];
}

class HyprInfo extends Equatable {
  const HyprInfo({
    this.monitors = const [],
    this.windows = const [],
    this.activeClass = '',
  });
  factory HyprInfo.fromJson(Json j) => HyprInfo(
    monitors: _list(j['monitors'], Monitor.fromJson),
    windows: _list(j['windows'], RigWindow.fromJson),
    activeClass: _map(j['active_window'])['class'] ?? '',
  );
  final List<Monitor> monitors;
  final List<RigWindow> windows;
  final String activeClass;

  static const perMonitor = 5;

  /// Workspace ids to show for a monitor: its block of five, plus any other
  /// regular workspace that is active or occupied on it.
  List<int> workspacesFor(int monitorIndex) {
    final m = monitors[monitorIndex];
    final start = monitorIndex * perMonitor + 1;
    return ({
      for (var i = 0; i < perMonitor; i++) start + i,
      for (final w in windows)
        if (w.monitor == m.name && (w.ws ?? 0) > 0) w.ws!,
      if ((m.activeWs ?? 0) > 0) m.activeWs!,
    }.toList()..sort());
  }

  @override
  List<Object?> get props => [monitors, windows, activeClass];
}

class AudioDevice extends Equatable {
  const AudioDevice(this.id, this.name, this.active);
  factory AudioDevice.fromJson(Json j) =>
      AudioDevice(_int(j['id']) ?? 0, j['name'] ?? '', j['active'] ?? false);
  final int id;
  final String name;
  final bool active;
  @override
  List<Object?> get props => [id, name, active];
}

class NowPlaying extends Equatable {
  const NowPlaying({
    this.status = '',
    this.title = '',
    this.player = '',
    this.artKey = '',
    this.positionUs,
    this.durationUs,
  });
  factory NowPlaying.fromJson(Json j) => NowPlaying(
    status: j['status'] ?? '',
    title: j['title'] ?? '',
    player: j['player'] ?? '',
    artKey: j['art_key'] ?? '',
    positionUs: _int(j['position_us']),
    durationUs: _int(j['duration_us']),
  );
  final String status, title, player, artKey;
  final int? positionUs, durationUs;
  bool get playing => status == 'Playing';
  bool get hasTrack => title.isNotEmpty;
  bool get seekable => (durationUs ?? 0) > 0;
  @override
  List<Object?> get props => [
    status,
    title,
    player,
    artKey,
    positionUs,
    durationUs,
  ];
}

class AudioInfo extends Equatable {
  const AudioInfo({
    this.volume,
    this.sinkMuted = false,
    this.micMuted = false,
    this.sinks = const [],
    this.sources = const [],
    this.recording = const [],
    this.nowPlaying = const NowPlaying(),
  });
  factory AudioInfo.fromJson(Json j) => AudioInfo(
    volume: _int(j['volume']),
    sinkMuted: j['sink_muted'] ?? false,
    micMuted: j['mic_muted'] ?? false,
    sinks: _list(j['sinks'], AudioDevice.fromJson),
    sources: _list(j['sources'], AudioDevice.fromJson),
    recording: [for (final r in (j['recording'] as List? ?? [])) '$r'],
    nowPlaying: NowPlaying.fromJson(_map(j['now_playing'])),
  );
  final int? volume;
  final bool sinkMuted, micMuted;
  final List<AudioDevice> sinks, sources;
  final List<String> recording;
  final NowPlaying nowPlaying;
  @override
  List<Object?> get props => [
    volume,
    sinkMuted,
    micMuted,
    sinks,
    sources,
    recording,
    nowPlaying,
  ];
}

class CpuInfo extends Equatable {
  const CpuInfo(this.util, this.temp, this.memUsed, this.memTotal);
  factory CpuInfo.fromJson(Json j) => CpuInfo(
    _dbl(j['util']) ?? 0,
    _dbl(j['temp']),
    _dbl(j['mem_used']) ?? 0,
    _dbl(j['mem_total']) ?? 0,
  );
  final double util, memUsed, memTotal;
  final double? temp;
  @override
  List<Object?> get props => [util, temp, memUsed, memTotal];
}

class GpuInfo extends Equatable {
  const GpuInfo(this.util, this.temp, this.vramUsed, this.vramTotal);
  factory GpuInfo.fromJson(Json j) => GpuInfo(
    _dbl(j['util']) ?? 0,
    _dbl(j['temp']) ?? 0,
    _dbl(j['vram_used']) ?? 0,
    _dbl(j['vram_total']) ?? 0,
  );
  final double util, temp, vramUsed, vramTotal;
  @override
  List<Object?> get props => [util, temp, vramUsed, vramTotal];
}

class Telemetry extends Equatable {
  const Telemetry({this.cpu, this.gpu});
  factory Telemetry.fromJson(Json j) => Telemetry(
    cpu: j['cpu'] == null ? null : CpuInfo.fromJson(_map(j['cpu'])),
    gpu: j['gpu'] == null ? null : GpuInfo.fromJson(_map(j['gpu'])),
  );
  final CpuInfo? cpu;
  final GpuInfo? gpu;
  @override
  List<Object?> get props => [cpu, gpu];
}

class Proc extends Equatable {
  const Proc(this.pid, this.name, this.mem, this.mine);
  factory Proc.fromJson(Json j) => Proc(
    _int(j['pid']) ?? 0,
    j['name'] ?? '',
    _dbl(j['mem']) ?? 0,
    j['mine'] ?? false,
  );
  final int pid;
  final String name;
  final double mem;
  final bool mine;

  /// Fraction of RAM in use. `mem` is meant to be a percentage, but servers
  /// that never read total memory divide by 1 and send bytes × 100.
  double fraction(double totalGb) {
    if (mem <= 100) return mem / 100;
    if (totalGb <= 0) return 0;
    return (mem / 100 / (totalGb * 1073741824)).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [pid, name, mem, mine];
}

class SysInfo extends Equatable {
  const SysInfo({
    this.tailscaleUp = false,
    this.tailscaleSelf,
    this.peersOnline = 0,
    this.peersTotal = 0,
    this.procs = const [],
    this.boot = 0,
  });
  factory SysInfo.fromJson(Json j) {
    final ts = _map(j['tailscale']);
    return SysInfo(
      tailscaleUp: ts['up'] ?? false,
      tailscaleSelf: ts['self_name'],
      peersOnline: _int(ts['online']) ?? 0,
      peersTotal: _int(ts['total']) ?? 0,
      procs: _list(j['procs'], Proc.fromJson),
      boot: _int(j['boot']) ?? 0,
    );
  }
  final bool tailscaleUp;
  final String? tailscaleSelf;
  final int peersOnline, peersTotal, boot;
  final List<Proc> procs;
  @override
  List<Object?> get props => [
    tailscaleUp,
    tailscaleSelf,
    peersOnline,
    peersTotal,
    procs,
    boot,
  ];
}

class DeckFrame extends Equatable {
  const DeckFrame({
    this.hypr = const HyprInfo(),
    this.audio = const AudioInfo(),
    this.telemetry = const Telemetry(),
    this.sys = const SysInfo(),
  });
  factory DeckFrame.fromJson(Json j) => DeckFrame(
    hypr: HyprInfo.fromJson(_map(j['hypr'])),
    audio: AudioInfo.fromJson(_map(j['audio'])),
    telemetry: Telemetry.fromJson(_map(j['telemetry'])),
    sys: SysInfo.fromJson(_map(j['sysinfo'])),
  );
  final HyprInfo hypr;
  final AudioInfo audio;
  final Telemetry telemetry;
  final SysInfo sys;
  @override
  List<Object?> get props => [hypr, audio, telemetry, sys];
}

class RigCommand extends Equatable {
  const RigCommand(this.id, this.label, this.cmd);
  factory RigCommand.fromJson(Json j) =>
      RigCommand(_int(j['id']) ?? 0, j['label'] ?? '', j['cmd'] ?? '');
  final int id;
  final String label, cmd;
  @override
  List<Object?> get props => [id, label, cmd];
}

class RigMode extends Equatable {
  const RigMode(this.id, this.label);
  factory RigMode.fromJson(Json j) => RigMode('${j['id']}', '${j['label']}');
  final String id, label;
  @override
  List<Object?> get props => [id, label];
}

class RigCamera extends Equatable {
  const RigCamera(this.node, this.name);
  factory RigCamera.fromJson(Json j) =>
      RigCamera(j['node'] ?? '', j['name'] ?? '');
  final String node, name;
  @override
  List<Object?> get props => [node, name];
}

class FleetHost extends Equatable {
  const FleetHost(this.name, this.label, this.url, this.online);
  factory FleetHost.fromJson(Json j) => FleetHost(
    j['name'] ?? '',
    j['label'] ?? j['name'] ?? '',
    j['url'] ?? '',
    j['online'],
  );
  final String name, label, url;
  final bool? online;
  @override
  List<Object?> get props => [name, label, url, online];
}

class ContextControl extends Equatable {
  const ContextControl(this.label, this.key, this.mods);
  factory ContextControl.fromJson(Json j) => ContextControl(
    j['label'] ?? j['key'] ?? '',
    j['key'] ?? '',
    j['mods'] ?? '',
  );
  final String label, key, mods;
  @override
  List<Object?> get props => [label, key, mods];
}

class ContextApp extends Equatable {
  const ContextApp(this.cls, this.label, this.persist, this.controls);
  final String cls, label;
  final bool persist;
  final List<ContextControl> controls;
  @override
  List<Object?> get props => [cls, label, persist, controls];
}

class ContextConfig extends Equatable {
  const ContextConfig({this.apps = const [], this.callApps = const []});
  factory ContextConfig.fromJson(Json j) => ContextConfig(
    apps: [
      for (final e in _map(j['apps']).entries)
        ContextApp(
          e.key,
          _map(e.value)['label'] ?? e.key,
          _map(e.value)['show'] == 'persist',
          _list(_map(e.value)['controls'], ContextControl.fromJson),
        ),
    ],
    callApps: [for (final c in (j['call_apps'] as List? ?? [])) '$c'],
  );
  final List<ContextApp> apps;
  final List<String> callApps;

  static bool _loose(String a, String b) =>
      a.isNotEmpty &&
      b.isNotEmpty &&
      (a == b || a.contains(b) || b.contains(a));

  List<ContextApp> visible(HyprInfo h) => [
    for (final a in apps)
      if (a.persist
          ? h.windows.any((w) => w.cls == a.cls)
          : h.activeClass == a.cls)
        a,
  ];

  bool inCall(AudioInfo a) =>
      a.recording.any((r) => callApps.any((c) => _loose(r, c)));

  RigWindow? callWindow(HyprInfo h, AudioInfo a) {
    final rec = a.recording.where((r) => callApps.any((c) => _loose(r, c)));
    for (final w in h.windows) {
      if (rec.any((r) => _loose(w.cls, r))) return w;
    }
    return null;
  }

  @override
  List<Object?> get props => [apps, callApps];
}
