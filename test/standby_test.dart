import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyprhand_mobile/blocs/lock_cubit.dart';
import 'package:hyprhand_mobile/blocs/notice_cubit.dart';
import 'package:hyprhand_mobile/blocs/settings_cubit.dart';
import 'package:hyprhand_mobile/data/native.dart';
import 'package:hyprhand_mobile/ui/palette.dart';
import 'package:hyprhand_mobile/ui/standby.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

final shots = Platform.environment['SHOTS'];
final boundary = GlobalKey();

void main() {
  late NoticeCubit notices;
  late List<String> native;
  var taps = 0;

  Future<void> send(WidgetTester t, String m, [Object? a]) async {
    await t.binding.defaultBinaryMessenger.handlePlatformMessage(
      'hyprhand/native',
      const StandardMethodCodec().encodeMethodCall(MethodCall(m, a)),
      (_) {},
    );
    await t.pump();
  }

  Future<void> mount(
    WidgetTester t, {
    Size size = const Size(412, 915),
    bool still = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    native = [];
    taps = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('hyprhand/native'),
      (c) async {
        native.add(c.method);
        return null;
      },
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    notices = NoticeCubit();
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: RepositoryProvider(
          create: (_) => Native(),
          child: MultiBlocProvider(
            providers: [
              BlocProvider(create: (_) => SettingsCubit(prefs)),
              BlocProvider.value(value: notices),
              BlocProvider(
                lazy: false,
                create: (c) => LockCubit(c.read<Native>()),
              ),
            ],
            child: StandbyBackBlocker(
              child: PaletteScope(
                palette: Palette.green,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: buildTheme(Palette.green),
                  builder: (c, child) => MediaQuery(
                    data: MediaQuery.of(c).copyWith(disableAnimations: still),
                    child: StandbyGate(child: child!),
                  ),
                  home: Builder(
                    builder: (c) => Scaffold(
                      body: Center(
                        child: TextButton(
                          onPressed: () {
                            taps++;
                            showDialog<void>(
                              context: c,
                              builder: (_) => const AlertDialog(
                                content: TextField(autofocus: true),
                              ),
                            );
                          },
                          child: const Text('SECRET DECK'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  Future<void> shoot(WidgetTester t, String name) async {
    expect(t.takeException(), isNull);
    if (shots == null) return;
    await t.runAsync(() async {
      final b =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage();
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      await File('$shots/$name.png').writeAsBytes(d!.buffer.asUint8List());
    });
  }

  Future<void> done(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  }

  setUpAll(() async {
    for (final (f, n) in [
      (mono, 'IBMPlexMono-Regular'),
      (display, 'ChakraPetch-Medium'),
    ]) {
      final l = FontLoader(f)
        ..addFont(
          File('assets/fonts/$n.ttf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        );
      await l.load();
    }
  });

  testWidgets('locking hides and disables everything, dialogs included', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    await mount(t);
    await t.tap(find.text('SECRET DECK'));
    await t.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
    await send(t, 'locked', true);
    await t.pump(const Duration(milliseconds: 100));
    expect(native, contains('standbyShown'));
    expect(find.byType(Standby), findsOneWidget);
    expect(find.text('SECRET DECK').hitTestable(), findsNothing);
    expect(find.byType(AlertDialog).hitTestable(), findsNothing);
    expect(find.bySemanticsLabel('SECRET DECK'), findsNothing);
    expect(t.testTextInput.isVisible, isFalse);
    for (final o in [const Offset(206, 457), const Offset(5, 5)]) {
      await t.tapAt(o);
      await t.pump();
    }
    expect(taps, 1);
    await t.binding.handlePopRoute(); // back must not close the dialog beneath
    await t.pump(const Duration(milliseconds: 400));
    await send(t, 'locked', false);
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(Standby), findsNothing);
    expect(find.byType(AlertDialog).hitTestable(), findsOneWidget);
    semantics.dispose();
    await done(t);
  });

  /// How many pixels are lit (the screen must be truly black when idle).
  Future<int> lit(WidgetTester t) async => (await t.runAsync(() async {
    final b =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage();
    final d = (await img.toByteData())!;
    var n = 0;
    for (var i = 0; i < d.lengthInBytes; i += 4) {
      if (d.getUint8(i) + d.getUint8(i + 1) + d.getUint8(i + 2) > 12) n++;
    }
    return n;
  }))!;

  testWidgets('black until pressed, then black again; failures stay vague', (
    t,
  ) async {
    await mount(t);
    await send(t, 'locked', true);
    await t.pump();
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 1));
    expect(await lit(t), 0);
    expect(t.binding.hasScheduledFrame, isFalse); // no idle animation
    final plays = {
      'up': ('volumeKey', {'dir': 1, 'held': false}),
      'down': ('volumeKey', {'dir': -1, 'held': false}),
      'power': ('powerKey', null),
    };
    for (final e in plays.entries) {
      await send(t, e.value.$1, e.value.$2);
      if (e.key == 'power') await send(t, 'screenOn');
      await t.pump(const Duration(milliseconds: 16));
      for (final ms in [90, 260, 300]) {
        await t.pump(Duration(milliseconds: ms));
        await shoot(t, 'standby-${e.key}-$ms');
        expect(await lit(t), greaterThan(2000), reason: e.key);
      }
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(await lit(t), 0);
      expect(t.binding.hasScheduledFrame, isFalse);
    }
    notices.error('Power: “my secret command” is no longer on this rig');
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('secret'), findsNothing);
    await shoot(t, 'standby-fail');
    expect(await lit(t), greaterThan(2000));
    for (var i = 0; i < 200; i++) {
      await send(t, 'volumeKey', {'dir': 1, 'held': true});
    }
    expect(t.takeException(), isNull);
    await done(t);
  });

  testWidgets('every further power press plays again, once the screen is on', (
    t,
  ) async {
    await mount(t);
    await send(t, 'locked', true);
    await t.pump();
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(seconds: 1));
    for (var i = 0; i < 4; i++) {
      await send(t, 'powerKey'); // the screen is off: nothing may be spent yet
      await t.pump(const Duration(milliseconds: 600));
      expect(await lit(t), 0);
      if (i < 3) {
        await send(t, 'screenOn');
      } else {
        await t.pump(const Duration(milliseconds: 1000)); // never reported
      }
      await t.pump(const Duration(milliseconds: 16));
      await t.pump(const Duration(milliseconds: 300));
      expect(await lit(t), greaterThan(2000), reason: 'press $i');
      await send(t, 'screenOn'); // a stray wake must not replay it
      await t.pump(const Duration(seconds: 2));
      await t.pump();
      expect(await lit(t), 0);
    }
    await done(t);
  });

  for (final (n, s) in [
    ('land', const Size(915, 412)),
    ('small', const Size(320, 480)),
  ]) {
    testWidgets('fits $n, and reduced motion', (t) async {
      await mount(t, size: s, still: n == 'small');
      await send(t, 'locked', true);
      await send(t, 'powerKey');
      await send(t, 'screenOn');
      await t.pump(const Duration(milliseconds: 16));
      await t.pump(const Duration(milliseconds: 16));
      await t.pump(const Duration(milliseconds: 350));
      expect(
        await lit(t),
        greaterThan(2000),
      ); // the press that locked the phone
      await shoot(t, 'standby-$n');
      await done(t);
    });
  }
}
