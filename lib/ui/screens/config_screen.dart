import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/config_cubit.dart';
import '../../blocs/deck_bloc.dart';
import '../../blocs/fleet_cubit.dart';
import '../../blocs/theme_cubit.dart';
import '../palette.dart';
import '../widgets.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  late final _cubit = ConfigCubit(context.read<DeckBloc>().repo.client);
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cubit.open('commands');
  }

  @override
  void dispose() {
    _cubit.close();
    _text.dispose();
    super.dispose();
  }

  Future<void> _open(String section) async {
    final s = _cubit.state;
    if (s.text != null && _text.text != s.text) {
      if (!await confirm(
        context,
        'Discard your changes to ${s.section}?',
        'Discard',
      )) {
        return;
      }
    }
    _cubit.open(section);
  }

  Future<void> _save() async {
    final bloc = context.read<DeckBloc>();
    final theme = context.read<ThemeCubit>(),
        fleet = context.read<FleetCubit>();
    if (!await _cubit.save(_text.text)) return;
    bloc.add(const ContextReloaded());
    theme.load(bloc.repo.client);
    fleet.load();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return BlocConsumer<ConfigCubit, ConfigState>(
      bloc: _cubit,
      listenWhen: (a, b) => b.text != null && a.text != b.text,
      listener: (_, s) => _text.text = s.text!,
      builder: (context, s) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final n in ConfigCubit.sections)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: DeckButton(
                        n,
                        height: 42,
                        selected: n == s.section,
                        onTap: () => _open(n),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: s.text == null
                  ? Center(
                      child: s.error
                          ? EmptyNote(
                              s.status ?? '',
                              onRetry: () => _cubit.open(s.section),
                            )
                          : const EmptyNote('Loading…'),
                    )
                  : TextField(
                      controller: _text,
                      expands: true,
                      maxLines: null,
                      autocorrect: false,
                      enableSuggestions: false,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontSize: 13, height: 1.45),
                    ),
            ),
            if (s.status != null && s.text != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  s.status!,
                  style: TextStyle(
                    fontSize: 12,
                    color: s.error ? Palette.danger : p.primary,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DeckButton('Reload', onTap: () => _open(s.section)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DeckButton(
                    'Save',
                    tone: Tone.primary,
                    busy: s.busy && s.text != null,
                    onTap: s.text == null ? null : _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
