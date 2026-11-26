import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/bindings_cubit.dart';
import '../blocs/deck_bloc.dart';
import '../blocs/files_cubit.dart';
import '../blocs/fleet_cubit.dart';
import '../blocs/macro_bloc.dart';
import '../blocs/nav_cubit.dart';
import '../blocs/session_bloc.dart';
import '../blocs/settings_cubit.dart';
import '../blocs/theme_cubit.dart';
import '../data/bindings.dart';
import '../data/deck_socket.dart';
import '../data/native.dart';
import 'palette.dart';
import 'screens/audio_screen.dart';
import 'screens/commands_screen.dart';
import 'screens/config_screen.dart';
import 'screens/deck_screen.dart';
import 'screens/files_screen.dart';
import 'screens/modes_screen.dart';
import 'screens/remote_screen.dart';
import 'screens/screen_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/system_screen.dart';
import 'widgets.dart';

const _icons = {
  DeckPage.deck: Icons.grid_view,
  DeckPage.remote: Icons.touch_app,
  DeckPage.audio: Icons.graphic_eq,
  DeckPage.commands: Icons.terminal,
  DeckPage.more: Icons.more_horiz,
  DeckPage.screen: Icons.cast,
  DeckPage.files: Icons.folder_copy,
  DeckPage.modes: Icons.auto_awesome_mosaic,
  DeckPage.system: Icons.memory,
  DeckPage.config: Icons.data_object,
  DeckPage.settings: Icons.settings,
};

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  late final Native _native = context.read<Native>();
  final _subs = <StreamSubscription<Object?>>[];
  late final BindingsCubit _bindings = context.read<BindingsCubit>();
  Timer? _pauseTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final bloc = context.read<DeckBloc>()..add(const DeckResumed());
    context.read<ThemeCubit>().load(bloc.repo.client);
    context.read<FleetCubit>().load();
    final nav = context.read<NavCubit>();
    final macros = context.read<MacroBloc>();
    _subs.addAll([
      _native.volumeKeys.listen((d) {
        final (dir, held) = d;
        final button = dir > 0 ? PhoneButton.volumeUp : PhoneButton.volumeDown;
        if (_bindings.state.armed(button)) {
          macros.add(ButtonPressed(button, held: held));
        } else {
          bloc.add(VolumeNudged(dir * 5));
        }
      }),
      _native.powerKey.listen((_) {
        if (_bindings.state.armed(PhoneButton.power)) {
          macros.add(const ButtonPressed(PhoneButton.power));
        }
      }),
      _native.shareReady.listen((_) => _takeShare()),
      _native.shortcuts.listen(nav.goNamed),
    ]);
    _native.takeShortcut().then((s) {
      if (s != null && mounted) nav.goNamed(s);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeShare());
    _applyKeys();
  }

  void _applyKeys() {
    final s = context.read<SettingsCubit>().state;
    final b = _bindings.state;
    final power = b.armed(PhoneButton.power);
    // A screen timeout would look exactly like a power press.
    _native.keepAwake(s.keepAwake || power);
    _native.captureKeys(
      up: s.volumeKeys || b.armed(PhoneButton.volumeUp),
      down: s.volumeKeys || b.armed(PhoneButton.volumeDown),
      power: power,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final bloc = context.read<DeckBloc>();
    if (s == AppLifecycleState.resumed) {
      _pauseTimer?.cancel();
      // Some dialogs and the lock screen bring the system bars back.
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      bloc.add(const DeckResumed());
    } else if (s == AppLifecycleState.paused) {
      _pauseTimer?.cancel();
      // A power press pauses us first; keep the sockets up for its chain.
      _pauseTimer = _bindings.state.armed(PhoneButton.power)
          ? Timer(
              const Duration(seconds: 15),
              () => bloc.add(const DeckPaused()),
            )
          : null;
      if (_pauseTimer == null) bloc.add(const DeckPaused());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _pauseTimer?.cancel();
    _native.keepAwake(false);
    _native.captureKeys();
    super.dispose();
  }

  /// Sharing always asks first: any app can send us a share intent.
  Future<void> _takeShare() async {
    final share = await _native.takeShare();
    if (share == null || !mounted) return;
    if (share.files.isEmpty && (share.text ?? '').isEmpty) return;
    final files = context.read<FilesCubit>();
    await deckSheet<void>(
      context,
      _ShareSheet(share: share, files: files, nav: context.read<NavCubit>()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = context.watch<NavCubit>().state;
    final nav = context.read<NavCubit>();
    return MultiBlocListener(
      listeners: [
        BlocListener<SettingsCubit, Settings>(listener: (_, _) => _applyKeys()),
        BlocListener<BindingsCubit, BindingsState>(
          listener: (_, _) => _applyKeys(),
        ),
      ],
      child: PopScope(
        canPop: page == DeckPage.deck,
        onPopInvokedWithResult: (did, _) {
          if (!did) nav.back();
        },
        child: LayoutBuilder(
          builder: (context, box) {
            // Keyboard insets shrink the height, so compare the real window.
            final size = MediaQuery.sizeOf(context);
            final wide = size.width > size.height && size.width >= 600;
            final content = Column(
              children: [
                if (page != DeckPage.deck && !(wide && page == DeckPage.remote))
                  PageTitle(
                    page.label,
                    onBack: page.underMore ? nav.back : null,
                  ),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(page),
                    child: _page(page, wide),
                  ),
                ),
              ],
            );
            return Stack(
              children: [
                Scaffold(
                  body: SafeArea(
                    bottom: wide,
                    child: Column(
                      children: [
                        const _LinkBanner(),
                        Expanded(
                          child: wide
                              ? Row(
                                  children: [
                                    Expanded(child: content),
                                    _Rail(page),
                                  ],
                                )
                              : content,
                        ),
                      ],
                    ),
                  ),
                  bottomNavigationBar: wide ? null : _BottomNav(page),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _page(DeckPage page, bool wide) => switch (page) {
    DeckPage.deck => DeckScreen(wide: wide),
    DeckPage.remote => RemoteScreen(wide: wide),
    DeckPage.audio => AudioScreen(wide: wide),
    DeckPage.commands => const CommandsScreen(),
    DeckPage.more => const _More(),
    DeckPage.screen => const ScreenScreen(),
    DeckPage.files => const FilesScreen(),
    DeckPage.modes => const ModesScreen(),
    DeckPage.system => const SystemScreen(),
    DeckPage.config => const ConfigScreen(),
    DeckPage.settings => const SettingsScreen(),
  };
}

class _LinkBanner extends StatelessWidget {
  const _LinkBanner();
  @override
  Widget build(BuildContext context) {
    final (link, has) = context.select(
      (DeckBloc b) => (b.state.link, b.state.hasFrame),
    );
    if (link == Link.online || (link == Link.connecting && !has)) {
      return const SizedBox.shrink();
    }
    final p = context.pal;
    return GestureDetector(
      onTap: () => context.read<DeckBloc>().add(const DeckResumed()),
      child: Container(
        width: double.infinity,
        color: Color.alphaBlend(p.secondary.withValues(alpha: .18), p.bg),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          link == Link.offline
              ? 'Rig unreachable — retrying. Tap to retry now.'
              : 'Reconnecting…',
          style: TextStyle(fontSize: 12, color: p.secondary),
        ),
      ),
    );
  }
}

bool _lit(DeckPage item, DeckPage page) =>
    item == page || (item == DeckPage.more && page.underMore);

class _BottomNav extends StatelessWidget {
  const _BottomNav(this.page);
  final DeckPage page;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.outline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final d in DeckPage.values.where((x) => !x.underMore))
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _lit(d, page),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      tick(context);
                      context.read<NavCubit>().go(d);
                    },
                    child: SizedBox(
                      height: 60,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _icons[d],
                            size: 22,
                            color: _lit(d, page) ? p.primary : p.onVar,
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              d.label,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: display,
                                fontSize: 11,
                                color: _lit(d, page) ? p.primary : p.onVar,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Landscape dock: icons only.
class _Rail extends StatelessWidget {
  const _Rail(this.page);
  final DeckPage page;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: 68,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(left: BorderSide(color: p.outline)),
      ),
      child: SafeArea(
        left: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final d in DeckPage.values.where((x) => !x.underMore))
              Semantics(
                button: true,
                selected: _lit(d, page),
                label: d.label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    tick(context);
                    context.read<NavCubit>().go(d);
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: _lit(d, page)
                          ? p.primary.withValues(alpha: .14)
                          : null,
                    ),
                    child: Icon(
                      _icons[d],
                      size: 24,
                      color: _lit(d, page) ? p.primary : p.onVar,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _More extends StatelessWidget {
  const _More();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = box.maxWidth > 560 ? 3 : 2;
      return GridView.count(
        padding: const EdgeInsets.all(14),
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: cols == 3 ? 2 : 1.5,
        children: [
          for (final d in DeckPage.values.where((x) => x.underMore))
            DeckButton(
              d.label,
              icon: _icons[d],
              onTap: () => context.read<NavCubit>().go(d),
            ),
          DeckButton(
            'Log out',
            icon: Icons.logout,
            tone: Tone.danger,
            onTap: () async {
              final session = context.read<SessionBloc>();
              if (await confirm(context, 'Log out of this rig?', 'Log out')) {
                session.add(const LoggedOut());
              }
            },
          ),
        ],
      );
    },
  );
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({
    required this.share,
    required this.files,
    required this.nav,
  });
  final NavCubit nav;
  final SharePayload share;
  final FilesCubit files;

  static const _images = ['.png', '.jpg', '.jpeg', '.gif', '.webp'];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final text = share.text?.trim() ?? '';
    final isUrl = RegExp(r'^https?://\S+$').hasMatch(text);
    final single = share.files.length == 1 ? share.files.first : null;
    // Server request bodies are capped at 2 MB, and this route reports no size
    // to verify against — so only offer it when the image safely fits.
    final clipImage =
        single != null &&
        single.size < 2000000 &&
        _images.any(single.name.toLowerCase().endsWith);
    void act(Future<void> Function() f) {
      Navigator.pop(context);
      f();
    }

    Widget btn(
      String l,
      IconData i,
      Future<void> Function() f, {
      bool main = false,
    }) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DeckButton(
        l,
        icon: i,
        tone: main ? Tone.primary : Tone.normal,
        onTap: () => act(f),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Send to the rig'),
        for (final f in share.files.take(5))
          Text(
            '${f.name} · ${(f.size / 1048576).toStringAsFixed(2)} MB',
            overflow: TextOverflow.ellipsis,
          ),
        if (share.files.length > 5)
          Text(
            'and ${share.files.length - 5} more',
            style: TextStyle(color: p.onVar),
          ),
        if (text.isNotEmpty)
          Text(text, maxLines: 4, overflow: TextOverflow.ellipsis),
        if (share.files.isNotEmpty) ...[
          if (clipImage)
            btn(
              'Save and copy image',
              Icons.content_copy,
              () => files.shareImage(single),
              main: true,
            ),
          btn('Save to ~/hyprhand-drop', Icons.save_alt, () async {
            nav.go(DeckPage.files);
            await files.upload(share.files);
          }, main: !clipImage),
        ],
        if (isUrl)
          btn(
            'Open on the rig',
            Icons.open_in_browser,
            () => files.openOnRig(text),
            main: share.files.isEmpty,
          ),
        if (text.isNotEmpty)
          btn(
            'Copy to rig clipboard',
            Icons.content_paste,
            () => files.sendClip(text),
            main: !isUrl && share.files.isEmpty,
          ),
      ],
    );
  }
}
