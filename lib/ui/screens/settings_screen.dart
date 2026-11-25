import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/deck_bloc.dart';
import '../../blocs/notice_cubit.dart';
import '../../blocs/session_bloc.dart';
import '../../blocs/settings_cubit.dart';
import '../../blocs/theme_cubit.dart';
import '../../data/hypr_client.dart';
import '../palette.dart';
import '../widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.watch<SettingsCubit>().state;
    final t = context.watch<ThemeCubit>().state;
    final set = context.read<SettingsCubit>().update;
    final theme = context.read<ThemeCubit>();
    final repo = context.read<DeckBloc>().repo;
    final notices = context.read<NoticeCubit>();
    Future<void> guard(Future<void> f) async {
      try {
        await f;
      } on ApiException catch (e) {
        notices.error(e);
      }
    }

    Widget toggle(String title, String sub, bool v, ValueChanged<bool> f) =>
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14)),
                  Text(sub, style: TextStyle(fontSize: 12, color: p.onVar)),
                ],
              ),
            ),
            Switch(value: v, onChanged: f),
          ],
        );

    return PageBody(
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Theme (shared with the rig)'),
              Seg<String>(
                items: const {
                  'green': 'Green',
                  'amber': 'Amber',
                  'ice': 'Ice',
                  'auto': 'Auto',
                },
                value: t.profile,
                onChanged: (v) => guard(theme.setProfile(repo.client, v)),
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('This phone'),
              toggle(
                'Volume keys control the rig',
                'While hyprhand is open',
                s.volumeKeys,
                (v) => set(s.copyWith(volumeKeys: v)),
              ),
              toggle(
                'Keep screen on',
                'While hyprhand is open',
                s.keepAwake,
                (v) => set(s.copyWith(keepAwake: v)),
              ),
              toggle(
                'Haptics',
                'Buzz on taps and keys',
                s.haptics,
                (v) => set(s.copyWith(haptics: v)),
              ),
              toggle(
                'Natural scrolling',
                'Content follows your fingers',
                s.naturalScroll,
                (v) => set(s.copyWith(naturalScroll: v)),
              ),
              toggle(
                'Scanlines',
                'CRT overlay',
                s.scanlines,
                (v) => set(s.copyWith(scanlines: v)),
              ),
              const SizedBox(height: 8),
              Text(
                'Trackpad speed ${s.sensitivity.toStringAsFixed(1)}×',
                style: const TextStyle(fontSize: 14),
              ),
              Slider(
                value: s.sensitivity,
                min: 1,
                max: 6,
                divisions: 20,
                onChanged: (v) => set(s.copyWith(sensitivity: v)),
              ),
            ],
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(repo.host.label),
              Text(
                repo.host.url,
                style: TextStyle(fontSize: 12, color: p.onVar),
              ),
              if (repo.host.insecure)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Plain HTTP: your PIN and keystrokes can be read by others on '
                    'this network. Use the Tailscale HTTPS address where you can.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: p.secondary,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              DeckButton(
                'Switch rig',
                icon: Icons.swap_horiz,
                onTap: () =>
                    context.read<SessionBloc>().add(const SwitchRigPressed()),
              ),
              const SizedBox(height: 8),
              DeckButton(
                'Log out',
                icon: Icons.logout,
                tone: Tone.danger,
                onTap: () => context.read<SessionBloc>().add(const LoggedOut()),
              ),
            ],
          ),
        ),
        DeckButton(
          'Open-source licences',
          onTap: () =>
              showLicensePage(context: context, applicationName: 'hyprhand'),
        ),
      ],
    );
  }
}
