import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyprhand_mobile/blocs/bindings_cubit.dart';
import 'package:hyprhand_mobile/blocs/commands_cubit.dart';
import 'package:hyprhand_mobile/blocs/deck_bloc.dart';
import 'package:hyprhand_mobile/blocs/files_cubit.dart';
import 'package:hyprhand_mobile/blocs/fleet_cubit.dart';
import 'package:hyprhand_mobile/blocs/macro_bloc.dart';
import 'package:hyprhand_mobile/blocs/nav_cubit.dart';
import 'package:hyprhand_mobile/blocs/notice_cubit.dart';
import 'package:hyprhand_mobile/blocs/session_bloc.dart';
import 'package:hyprhand_mobile/blocs/settings_cubit.dart';
import 'package:hyprhand_mobile/blocs/theme_cubit.dart';
import 'package:hyprhand_mobile/data/bindings.dart';
import 'package:hyprhand_mobile/data/deck_repository.dart';
import 'package:hyprhand_mobile/data/deck_socket.dart';
import 'package:hyprhand_mobile/data/host_store.dart';
import 'package:hyprhand_mobile/data/hypr_client.dart';
import 'package:hyprhand_mobile/data/input_message.dart';
import 'package:hyprhand_mobile/data/models.dart';
import 'package:hyprhand_mobile/data/native.dart';
import 'package:hyprhand_mobile/ui/palette.dart';
import 'package:hyprhand_mobile/ui/screens/connect_screen.dart';
import 'package:hyprhand_mobile/ui/shell.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Set SHOTS to a directory to also write PNGs.
final shots = Platform.environment['SHOTS'];

class FakeClient extends HyprClient {
  FakeClient() : super(Uri.parse('http://rig:8765'));
  final calls = <(String, Object?)>[];
  @override
  Future<Object?> getJson(
    String path, {
    Duration timeout = Duration.zero,
  }) async => switch (path) {
    '/commands' => [
      for (final (i, l) in [
        'Reload Hyprland',
        'Update system',
        'Night light',
        'Open a terminal with a long name',
      ].indexed)
        {'id': i, 'label': l, 'cmd': 'hyprctl reload && notify-send done'},
    ],
    '/modes' => [
      {'id': 'Focus', 'label': 'Focus'},
      {'id': 'Movie', 'label': 'Movie'},
    ],
    '/api/config' => {
      'commands': [
        {'label': 'x', 'cmd': 'y'},
      ],
    },
    '/theme' => {
      'profile': 'green',
      'ambient': {'idle_min': 2.0, 'liturgy': true},
    },
    '/cameras' => [
      {'node': 'video0', 'name': 'USB2.0 HD UVC WebCam'},
    ],
    '/fleet' => [
      {
        'name': 'eva',
        'label': 'Eva',
        'url': 'https://eva.x.ts.net',
        'online': true,
      },
    ],
    _ => {'ok': true},
  };
  @override
  Future<Json> call(
    String path, [
    Object? body,
    String method = 'POST',
    Duration timeout = Duration.zero,
  ]) async {
    calls.add((path, body));
    return {'ok': true};
  }

  @override
  Future<Uint8List> getBytes(
    String path, {
    Map<String, String>? query,
    Duration timeout = Duration.zero,
  }) async => path == '/screenshot' && shot != null
      ? shot!
      : throw const ApiException('no frame', 404);
  static Uint8List? shot;
  @override
  Future<String> themeCss() async => '';
}

class FakeRepo extends DeckRepository {
  FakeRepo(FakeClient c)
    : super(const RigHost(url: 'http://rig:8765', label: 'evangelion'), c);
  final sent = <InputMessage>[];
  @override
  void start() {}
  @override
  void retryNow() {}
  @override
  bool send(InputMessage m) {
    sent.add(m);
    return true;
  }
}

final frame = DeckFrame.fromJson({
  'hypr': {
    'monitors': [
      {
        'name': 'eDP-1',
        'model': 'm',
        'w': 1920,
        'h': 1080,
        'refresh': 144,
        'active_ws': 3,
        'focused': true,
        'dpms': true,
      },
      {
        'name': 'HDMI-A-1',
        'model': 'm',
        'w': 2560,
        'h': 1440,
        'refresh': 60,
        'active_ws': 6,
        'focused': false,
        'dpms': true,
      },
    ],
    'windows': [
      {
        'address': '0x1',
        'title': 'nvim main.rs',
        'cls': 'kitty',
        'ws': 3,
        'monitor': 'eDP-1',
        'focused': true,
      },
      {
        'address': '0x2',
        'title': 'A browser tab with a really quite long page title',
        'cls': 'zen',
        'ws': 1,
        'monitor': 'eDP-1',
      },
      {
        'address': '0x3',
        'title': 'scratch',
        'cls': 'kitty',
        'ws': -98,
        'monitor': 'eDP-1',
      },
      {
        'address': '0x4',
        'title': 'Films',
        'cls': 'mpv',
        'ws': 6,
        'monitor': 'HDMI-A-1',
      },
    ],
    'active_window': {'class': 'kitty'},
  },
  'audio': {
    'volume': 69,
    'sinks': [
      {'id': 1, 'name': 'SYN-H200', 'active': true},
      {
        'id': 2,
        'name': 'Ryzen HD Audio Controller Analog Stereo',
        'active': false,
      },
    ],
    'sources': [
      {
        'id': 3,
        'name': 'Ryzen HD Audio Controller Analog Stereo',
        'active': true,
      },
    ],
    'now_playing': {
      'status': 'Paused',
      'title': 'Some Artist - A Rather Long Track Title To Wrap',
      'player': 'spotify',
      'art_key': '',
      'position_us': 63000000,
      'duration_us': 211000000,
    },
  },
  'telemetry': {
    'cpu': {'util': 37.2, 'temp': 63.0, 'mem_used': 11.2, 'mem_total': 15.0},
    'gpu': {
      'util': 12.0,
      'temp': 58.0,
      'vram_used': 1900.0,
      'vram_total': 4096.0,
    },
  },
  'sysinfo': {
    'tailscale': {
      'up': true,
      'self_name': 'evangelion',
      'online': 1,
      'total': 2,
    },
    'procs': [
      for (var i = 0; i < 8; i++)
        {
          'pid': i + 9,
          'name': 'process-number-$i',
          'mem': 126907600000.0,
          'mine': false,
        },
    ],
    'boot': 1700000000,
  },
});

class Rig {
  late FakeRepo repo;
  late DeckBloc deck;
  late NavCubit nav;
  late BindingsCubit bindings;
  late MacroBloc macros;
  late NoticeCubit notices;
  final boundary = GlobalKey();
}

Future<Rig> mount(
  WidgetTester t,
  Size size, {
  Widget? screen,
  double textScale = 1,
}) async {
  final rig = Rig();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('hyprhand/native'),
    (c) async => null,
  );
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final client = FakeClient();
  rig.repo = FakeRepo(client);
  final notices = NoticeCubit();
  rig.deck = DeckBloc(rig.repo, notices);
  rig.nav = NavCubit();
  rig.notices = notices;
  rig.bindings = BindingsCubit(prefs);
  rig.macros = MacroBloc(rig.deck, rig.bindings, notices);
  await t.pumpWidget(
    RepaintBoundary(
      key: rig.boundary,
      child: RepositoryProvider(
        create: (_) => Native(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => SettingsCubit(prefs)),
            BlocProvider(create: (_) => ThemeCubit(prefs)),
            BlocProvider.value(value: notices),
            BlocProvider(create: (_) => rig.bindings),
            BlocProvider(create: (_) => SessionBloc(HostStore(prefs))),
          ],
          child: PaletteScope(
            palette: Palette.green,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(Palette.green),
              builder: (c, child) => MediaQuery.withClampedTextScaling(
                minScaleFactor: textScale,
                maxScaleFactor: textScale,
                child: child!,
              ),
              home:
                  screen ??
                  MultiBlocProvider(
                    providers: [
                      BlocProvider(create: (_) => rig.deck),
                      BlocProvider(create: (_) => rig.nav),
                      BlocProvider(create: (_) => rig.macros),
                      BlocProvider(create: (_) => FleetCubit(client)),
                      BlocProvider(
                        create: (_) => CommandsCubit(client, notices),
                      ),
                      BlocProvider(
                        create: (c) =>
                            FilesCubit(client, c.read<Native>(), notices),
                      ),
                    ],
                    child: const Shell(),
                  ),
            ),
          ),
        ),
      ),
    ),
  );
  // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
  rig.deck.emit(
    DeckState(
      frame: frame,
      link: Link.online,
      hasFrame: true,
      brightness: const {'eDP-1': 28},
      context: ContextConfig.fromJson(const {
        'apps': {
          'kitty': {
            'label': 'Kitty',
            'show': 'focus',
            'controls': [
              {'label': 'New tab', 'key': 't', 'mods': 'CTRL'},
            ],
          },
        },
      }),
    ),
  );
  await t.pump(const Duration(milliseconds: 100));
  return rig;
}

Future<void> shoot(WidgetTester t, Rig rig, String name) async {
  expect(t.takeException(), isNull, reason: name);
  if (shots == null) return;
  await t.runAsync(() async {
    final b =
        rig.boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final img = await b.toImage();
    final d = await img.toByteData(format: ui.ImageByteFormat.png);
    await File('$shots/$name.png').writeAsBytes(d!.buffer.asUint8List());
    img.dispose();
  });
}

Future<void> unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 5));
}

void main() {
  setUpAll(() async {
    Future<void> font(String fam, List<String> files) async {
      final l = FontLoader(fam);
      for (final f in files) {
        l.addFont(File(f).readAsBytes().then((b) => ByteData.sublistView(b)));
      }
      await l.load();
    }

    await font(mono, [
      for (final w in ['Regular', 'Medium', 'SemiBold'])
        'assets/fonts/IBMPlexMono-$w.ttf',
    ]);
    await font(display, [
      for (final w in ['Medium', 'SemiBold', 'Bold'])
        'assets/fonts/ChakraPetch-$w.ttf',
    ]);
    final root = Platform.environment['FLUTTER_ROOT'];
    final icons = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) await font('MaterialIcons', [icons.path]);
  });

  const sizes = {
    'phone': (Size(412, 915), 1.0),
    'small': (Size(320, 600), 1.0),
    'land': (Size(915, 412), 1.0),
    'bigtext': (Size(412, 915), 1.5),
  };
  for (final e in sizes.entries) {
    for (final page in DeckPage.values) {
      testWidgets('${page.name} @ ${e.key}', (t) async {
        final rig = await mount(t, e.value.$1, textScale: e.value.$2);
        rig.nav.go(page);
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        await shoot(t, rig, '${page.name}-${e.key}');
        if (page == DeckPage.remote) {
          rig.bindings.add(
            PhoneButton.volumeUp,
            const ActionStep(StepKind.keys, ['ctrl', 'shift', 't']),
          );
          rig.bindings.add(
            PhoneButton.volumeUp,
            const ActionStep(StepKind.command, [
              'A command with a long name',
              'x',
            ]),
          );
          for (final tab in ['Keys', 'Type', 'Buttons']) {
            await t.tap(find.text(tab));
            await t.pump(const Duration(milliseconds: 300));
            await shoot(t, rig, 'remote-$tab-${e.key}');
          }
        }
        await unmount(t);
      });
    }
    testWidgets('connect @ ${e.key}', (t) async {
      const h = RigHost(url: 'http://192.168.1.20:8765', label: 'evangelion');
      final a = await mount(
        t,
        e.value.$1,
        textScale: e.value.$2,
        screen: const Scaffold(body: PickerScreen([h])),
      );
      await shoot(t, a, 'picker-${e.key}');
      await unmount(t);
      final b = await mount(
        t,
        e.value.$1,
        textScale: e.value.$2,
        screen: const Scaffold(
          body: LoginScreen(SessionLogin(h, error: 'invalid PIN')),
        ),
      );
      await t.pump(const Duration(milliseconds: 400));
      await shoot(t, b, 'login-${e.key}');
      await unmount(t);
    });
  }

  testWidgets('grabbed shot opens full screen', (t) async {
    FakeClient.shot = await t.runAsync(() async {
      final r = ui.PictureRecorder();
      final c = ui.Canvas(r);
      c.drawRect(
        const ui.Rect.fromLTWH(0, 0, 1920, 1080),
        ui.Paint()..color = const ui.Color(0xff203040),
      );
      c.drawCircle(
        const ui.Offset(960, 540),
        400,
        ui.Paint()..color = const ui.Color(0xffffaa00),
      );
      final img = await r.endRecording().toImage(1920, 1080);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      return d!.buffer.asUint8List();
    });
    for (final size in [const Size(400, 860)]) {
      final rig = await mount(t, size);
      rig.nav.go(DeckPage.files);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.text('Grab'));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await t.pump(const Duration(milliseconds: 300));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await t.pump();
      await t.ensureVisible(find.byType(Image).first);
      await t.tap(find.byType(Image).first);
      await t.pump(const Duration(seconds: 1));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await t.pump(const Duration(seconds: 1));
      await shoot(t, rig, 'viewer-${size.width.round()}');
      await t.tap(find.bySemanticsLabel('Close'));
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.bySemanticsLabel('Close'), findsNothing);
      await unmount(t);
    }
    FakeClient.shot = null;
  });

  testWidgets('drag a window onto a workspace moves it; tap focuses', (
    t,
  ) async {
    final rig = await mount(t, const Size(412, 915));
    final calls = (rig.repo.client as FakeClient).calls;
    await t.tap(find.text('nvim main.rs'));
    await t.pump();
    expect(calls.last.$1, '/hypr/focus');
    final g = await t.startGesture(t.getCenter(find.text('nvim main.rs')));
    await t.pump(const Duration(milliseconds: 450));
    final target = find.widgetWithText(GestureDetector, '5').first;
    await g.moveTo(t.getCenter(target));
    await t.pump();
    await g.up();
    await t.pump();
    expect(calls.last.$1, '/hypr/move');
    expect(calls.last.$2, {'address': '0x1', 'workspace': 5});
    await unmount(t);
  });

  testWidgets('back walks up, killing a process needs confirmation', (t) async {
    final rig = await mount(t, const Size(412, 915));
    final calls = (rig.repo.client as FakeClient).calls;
    rig.nav.go(DeckPage.system);
    await t.pump();
    await t.ensureVisible(find.byTooltip('End process-number-0'));
    await t.pump();
    await t.tap(find.byTooltip('End process-number-0'));
    await t.pump(const Duration(milliseconds: 400));
    expect(calls.where((c) => c.$1 == '/sys/kill'), isEmpty);
    await t.tap(find.text('End process'));
    await t.pump(const Duration(milliseconds: 400));
    expect(calls.where((c) => c.$1 == '/sys/kill').length, 1);
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 400));
    expect(rig.nav.state, DeckPage.more);
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 400));
    expect(rig.nav.state, DeckPage.deck);
    await unmount(t);
  });

  // ── hardware buttons ──

  Future<void> key(WidgetTester t, String method, [Object? args]) async {
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'hyprhand/native',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
    await t.pump();
    await t.pump();
  }

  Future<void> vol(WidgetTester t, int dir, {bool held = false}) =>
      key(t, 'volumeKey', {'dir': dir, 'held': held});

  testWidgets('assign through the editor, then press', (t) async {
    final rig = await mount(t, const Size(412, 915));
    rig.nav.go(DeckPage.remote);
    await t.pump();
    await t.tap(find.text('Buttons'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Assign').first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('ctrl'));
    await t.pump();
    await t.tap(find.text('tab'));
    await t.pump();
    await shoot(t, rig, 'step-editor');
    await t.tap(find.text('Save: Ctrl + Tab'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(rig.bindings.state.of(PhoneButton.volumeUp).steps, [
      const ActionStep(StepKind.keys, ['ctrl', 'tab']),
    ]);

    await vol(t, 1); // still off: plain rig volume
    expect(rig.repo.sent, isEmpty);
    expect((rig.repo.client as FakeClient).calls.last.$1, '/audio/volume');
    await t.tap(find.text('Buttons are OFF'));
    await t.pump();
    await vol(t, 1);
    expect(rig.repo.sent, [
      InputMessage.combo(const ['ctrl', 'tab']),
    ]);
    await vol(t, 1, held: true); // repeat is off
    expect(rig.repo.sent.length, 1);
    rig.bindings.setRepeat(PhoneButton.volumeUp, true);
    await vol(t, 1, held: true);
    expect(rig.repo.sent.length, 2);
    await unmount(t);
  });

  testWidgets('chain runs in order; turning off stops it midway', (t) async {
    final rig = await mount(t, const Size(412, 915));
    const b = PhoneButton.power;
    rig.bindings
      ..add(b, const ActionStep(StepKind.click, ['left']))
      ..add(b, const ActionStep(StepKind.wait, ['500']))
      ..add(b, const ActionStep(StepKind.text, ['hi']));
    await key(t, 'powerKey');
    expect(rig.repo.sent, isEmpty);
    rig.bindings.setEnabled(true);
    await key(t, 'powerKey');
    expect(rig.repo.sent, [InputMessage.click('left')]);
    await t.pump(const Duration(milliseconds: 600));
    expect(rig.repo.sent.last, InputMessage.text('hi'));
    rig.repo.sent.clear();
    await key(t, 'powerKey');
    rig.bindings.setEnabled(false);
    await t.pump(const Duration(milliseconds: 600));
    expect(rig.repo.sent, [InputMessage.click('left')]);
    await unmount(t);
  });

  testWidgets('commands match by content; missing ones abort the chain', (
    t,
  ) async {
    final rig = await mount(t, const Size(412, 915));
    const b = PhoneButton.volumeDown;
    rig.bindings
      ..setEnabled(true)
      ..add(
        b,
        const ActionStep(StepKind.command, [
          'Night light',
          'hyprctl reload && notify-send done',
        ]),
      )
      ..add(b, const ActionStep(StepKind.command, ['Gone', 'rm']))
      ..add(b, const ActionStep(StepKind.click, ['left']));
    await vol(t, -1);
    await t.pump(const Duration(milliseconds: 100));
    final calls = (rig.repo.client as FakeClient).calls;
    expect(calls.where((c) => c.$1 == '/commands/run').map((c) => c.$2), [
      {'id': 2},
    ]);
    expect(rig.notices.state!.text, contains('Gone'));
    expect(rig.repo.sent, isEmpty);
    await unmount(t);
  });

  test('bindings persist and survive junk', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final a = BindingsCubit(p)
      ..setEnabled(true)
      ..add(PhoneButton.power, const ActionStep(StepKind.wait, ['5']))
      ..add(PhoneButton.power, const ActionStep(StepKind.text, ['x']))
      ..move(PhoneButton.power, 1, -1);
    expect(BindingsCubit(p).state, a.state);
    expect(a.state.of(PhoneButton.power).steps.first.kind, StepKind.text);
    await p.setString(
      'bindings',
      '{"on":true,"power":{"steps":[{"k":"nope","a":["1"]},3,{"k":"command","a":["x"]}]}}',
    );
    expect(BindingsCubit(p).state.armed(PhoneButton.power), isFalse);
  });
}
