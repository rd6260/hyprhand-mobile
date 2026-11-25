import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'blocs/bindings_cubit.dart';
import 'blocs/commands_cubit.dart';
import 'blocs/deck_bloc.dart';
import 'blocs/files_cubit.dart';
import 'blocs/fleet_cubit.dart';
import 'blocs/lock_cubit.dart';
import 'blocs/macro_bloc.dart';
import 'blocs/nav_cubit.dart';
import 'blocs/notice_cubit.dart';
import 'blocs/session_bloc.dart';
import 'blocs/settings_cubit.dart';
import 'blocs/theme_cubit.dart';
import 'data/host_store.dart';
import 'data/native.dart';
import 'ui/palette.dart';
import 'ui/screens/connect_screen.dart';
import 'ui/shell.dart';
import 'ui/standby.dart';
import 'ui/widgets.dart';

class HyprhandApp extends StatelessWidget {
  const HyprhandApp({
    super.key,
    required this.prefs,
    required this.store,
    required this.native,
    this.locked = false,
  });
  final bool locked;
  final SharedPreferences prefs;
  final HostStore store;
  final Native native;

  @override
  Widget build(BuildContext context) => RepositoryProvider.value(
    value: native,
    child: MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SettingsCubit(prefs)),
        BlocProvider(create: (_) => ThemeCubit(prefs)),
        BlocProvider(create: (_) => BindingsCubit(prefs)),
        BlocProvider(create: (_) => NoticeCubit()),
        BlocProvider(
          lazy: false,
          create: (_) => LockCubit(native, locked: locked),
        ),
        BlocProvider(
          create: (_) => SessionBloc(store)..add(const SessionStarted()),
        ),
      ],
      child: const StandbyBackBlocker(child: _App()),
    ),
  );
}

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) {
    final palette = context.select((ThemeCubit c) => c.state.palette);
    return PaletteScope(
      palette: palette,
      child: MaterialApp(
        title: 'hyprhand',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(palette),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: palette.surface,
          ),
          child: Stack(
            children: [
              Positioned.fill(child: StandbyGate(child: child!)),
              if (context.select((SettingsCubit c) => c.state.scanlines))
                const Positioned.fill(child: Scanlines()),
            ],
          ),
        ),
        home: const _Root(),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) => BlocListener<NoticeCubit, Notice?>(
    listener: (context, n) {
      if (n == null) return;
      final p = context.pal;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: p.high,
            duration: Duration(seconds: n.error ? 4 : 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: n.error ? Palette.danger : p.primary),
            ),
            content: Text(
              n.text,
              style: TextStyle(
                fontFamily: mono,
                fontSize: 13,
                color: n.error ? Palette.danger : p.on,
              ),
            ),
          ),
        );
    },
    child: BlocConsumer<SessionBloc, SessionState>(
      // Sheets and dialogs belong to the session that opened them.
      listener: (context, _) =>
          Navigator.of(context).popUntil((r) => r.isFirst),
      builder: (context, s) => switch (s) {
        SessionLoading() => const Scaffold(body: SizedBox.expand()),
        SessionPicking(:final hosts) => Scaffold(body: PickerScreen(hosts)),
        SessionLogin() => Scaffold(
          body: LoginScreen(s, key: ValueKey(s.host.url)),
        ),
        SessionActive(:final repo) => MultiBlocProvider(
          key: ObjectKey(repo),
          providers: [
            BlocProvider(create: (c) => DeckBloc(repo, c.read<NoticeCubit>())),
            BlocProvider(
              create: (c) => MacroBloc(
                c.read<DeckBloc>(),
                c.read<BindingsCubit>(),
                c.read<NoticeCubit>(),
              ),
            ),
            BlocProvider(create: (_) => NavCubit()),
            BlocProvider(create: (_) => FleetCubit(repo.client)),
            BlocProvider(
              create: (c) => CommandsCubit(repo.client, c.read<NoticeCubit>()),
            ),
            BlocProvider(
              create: (c) => FilesCubit(
                repo.client,
                c.read<Native>(),
                c.read<NoticeCubit>(),
              ),
            ),
          ],
          child: const Shell(),
        ),
      },
    ),
  );
}
