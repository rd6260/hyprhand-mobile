import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/bindings_cubit.dart';
import '../../blocs/commands_cubit.dart';
import '../../blocs/keyboard_cubit.dart' show KeyboardCubit, typeable;
import '../../blocs/macro_bloc.dart';
import '../../data/bindings.dart';
import '../../data/models.dart';
import '../palette.dart';
import '../widgets.dart';

/// Assign chains of actions to the phone's hardware buttons.
class ButtonsTab extends StatelessWidget {
  const ButtonsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.watch<BindingsCubit>().state;
    final cubit = context.read<BindingsCubit>();
    return ListView(
      children: [
        DeckButton(
          s.enabled ? 'Buttons are ON' : 'Buttons are OFF',
          icon: Icons.power_settings_new,
          height: 56,
          tone: s.enabled ? Tone.primary : Tone.normal,
          onTap: () => cubit.setEnabled(!s.enabled),
        ),
        const SizedBox(height: 6),
        Text(
          s.enabled
              ? 'Assigned buttons work on every page while hyprhand is open.'
              : 'Assignments are kept but do nothing until you turn this on.',
          style: TextStyle(fontSize: 12, height: 1.4, color: p.onVar),
        ),
        for (final b in PhoneButton.values) ...[
          const SizedBox(height: 14),
          _ButtonCard(b, s.of(b)),
        ],
        const SizedBox(height: 14),
      ],
    );
  }
}

class _ButtonCard extends StatelessWidget {
  const _ButtonCard(this.b, this.v);
  final PhoneButton b;
  final ButtonBinding v;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cubit = context.read<BindingsCubit>();
    final running = context.select((MacroBloc m) => m.state == b);
    Widget act(String tip, IconData i, VoidCallback? f, [Color? c]) =>
        IconButton(
          tooltip: tip,
          constraints: const BoxConstraints.tightFor(width: 40, height: 44),
          padding: EdgeInsets.zero,
          onPressed: f,
          icon: Icon(i, size: 18),
          color: c ?? p.onVar,
        );
    final n = v.steps.length;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(b.label),
          if (n == 0)
            Text(
              b == PhoneButton.power
                  ? 'Not assigned — locks the phone as usual.'
                  : 'Not assigned — changes volume as usual.',
              style: TextStyle(fontSize: 12, color: p.onVar),
            ),
          for (final (i, s) in v.steps.indexed)
            Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(fontSize: 12, color: p.secondary),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _edit(context, i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        s.describe,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
                if (n > 1) ...[
                  act(
                    'Move step ${i + 1} up',
                    Icons.arrow_upward,
                    i == 0 ? null : () => cubit.move(b, i, -1),
                  ),
                  act(
                    'Move step ${i + 1} down',
                    Icons.arrow_downward,
                    i == n - 1 ? null : () => cubit.move(b, i, 1),
                  ),
                ],
                act(
                  'Remove step ${i + 1}',
                  Icons.close,
                  () => cubit.removeAt(b, i),
                  Palette.danger,
                ),
              ],
            ),
          if (b != PhoneButton.power && n > 0)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Repeat while held',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                Switch(
                  value: v.repeat,
                  onChanged: (x) => cubit.setRepeat(b, x),
                ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DeckButton(
                  n == 0 ? 'Assign' : 'Add step',
                  icon: Icons.add,
                  onTap: () => _edit(context, null),
                ),
              ),
              if (n > 0) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: DeckButton(
                    'Test',
                    icon: Icons.play_arrow,
                    busy: running,
                    onTap: () => context.read<MacroBloc>().add(ChainTested(b)),
                  ),
                ),
              ],
            ],
          ),
          if (b == PhoneButton.power) ...[
            const SizedBox(height: 10),
            Text(
              'Android hides the power key from apps, so this reacts to the screen '
              'turning off and wakes it again. While assigned and ON, a '
              'standby face shows over the lock screen: anyone holding the phone can '
              'press your assigned buttons, but nothing else. A double press may still open the camera.',
              style: TextStyle(fontSize: 12, height: 1.4, color: p.secondary),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, int? i) async {
    final cubit = context.read<BindingsCubit>();
    final commands = context.read<CommandsCubit>()..load();
    final step = await deckSheet<ActionStep>(
      context,
      StepEditor(commands: commands, initial: i == null ? null : v.steps[i]),
    );
    if (step == null) return;
    if (i == null) return cubit.add(b, step);
    if (i < cubit.state.of(b).steps.length) cubit.replace(b, i, step);
  }
}

class StepEditor extends StatefulWidget {
  const StepEditor({super.key, required this.commands, this.initial});
  final CommandsCubit commands;
  final ActionStep? initial;
  @override
  State<StepEditor> createState() => _StepEditorState();
}

class _StepEditorState extends State<StepEditor> {
  late StepKind _kind = widget.initial?.kind ?? StepKind.keys;
  late final _mods = <String>{};
  String? _key, _choice;
  RigCommand? _command;
  final _text = TextEditingController();

  static const _keys = [
    'enter',
    'esc',
    'tab',
    'space',
    'backspace',
    'delete',
    'up',
    'down',
    'left',
    'right',
    'home',
    'end',
    'pageup',
    'pagedown',
  ];
  static final _all = [
    ..._keys,
    for (var i = 1; i <= 12; i++) 'f$i',
    ...'abcdefghijklmnopqrstuvwxyz0123456789'.split(''),
    'comma',
    'period',
    'slash',
    'semicolon',
    'quote',
    'minus',
    'equal',
    'leftbrace',
    'rightbrace',
    'backslash',
    'grave',
  ];

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    if (s == null) return;
    switch (s.kind) {
      case StepKind.keys:
        _mods.addAll(s.args.where(KeyboardCubit.order.contains));
        _key = s.args
            .where((k) => !KeyboardCubit.order.contains(k))
            .firstOrNull;
      case StepKind.text || StepKind.workspace || StepKind.wait:
        _text.text = s.args.first;
      case StepKind.command:
        _command = RigCommand(-1, s.args[0], s.args[1]);
      default:
        _choice = s.args.first;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  ActionStep? get _built {
    final n = int.tryParse(_text.text);
    ActionStep one(String v) => ActionStep(_kind, [v]);
    return switch (_kind) {
      StepKind.keys =>
        _key == null && _mods.isEmpty
            ? null
            : ActionStep(_kind, [
                for (final m in KeyboardCubit.order)
                  if (_mods.contains(m)) m,
                ?_key,
              ]),
      StepKind.text =>
        _text.text.isEmpty || !_text.text.runes.every(typeable)
            ? null
            : one(_text.text),
      StepKind.workspace => n == null || n < 1 ? null : one('$n'),
      StepKind.wait => n == null || n < 1 || n > 10000 ? null : one('$n'),
      StepKind.command =>
        _command == null
            ? null
            : ActionStep(_kind, [_command!.label, _command!.cmd]),
      _ => _choice == null ? null : one(_choice!),
    };
  }

  @override
  Widget build(BuildContext context) {
    final step = _built;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Action'),
        Seg<StepKind>(
          items: {for (final k in StepKind.values) k: k.label},
          value: _kind,
          onChanged: (k) => setState(() {
            _kind = k;
            _choice = null;
            _text.clear();
          }),
        ),
        const SizedBox(height: 16),
        _form(context),
        const SizedBox(height: 16),
        DeckButton(
          step == null ? 'Save' : 'Save: ${step.describe}',
          tone: Tone.primary,
          onTap: step == null ? null : () => Navigator.pop(context, step),
        ),
      ],
    );
  }

  Widget _choices(Map<String, String> items) => Seg<String>(
    items: items,
    value: _choice,
    onChanged: (v) => setState(() => _choice = v),
  );

  Widget _field(String hint, {bool number = false, String? error}) => TextField(
    controller: _text,
    onChanged: (_) => setState(() {}),
    autocorrect: false,
    keyboardType: number ? TextInputType.number : null,
    decoration: InputDecoration(
      hintText: hint,
      errorText: error,
      errorMaxLines: 2,
    ),
  );

  Widget _form(BuildContext context) => switch (_kind) {
    StepKind.keys => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Hold'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in KeyboardCubit.order)
              IntrinsicWidth(
                child: DeckButton(
                  m,
                  height: 42,
                  selected: _mods.contains(m),
                  onTap: () => setState(
                    () => _mods.contains(m) ? _mods.remove(m) : _mods.add(m),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const SectionLabel('Press'),
        SizedBox(
          height: 190,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in _all)
                  IntrinsicWidth(
                    child: DeckButton(
                      k,
                      height: 42,
                      selected: _key == k,
                      onTap: () => setState(() => _key = _key == k ? null : k),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
    StepKind.text => _field(
      'Text to type',
      error: _text.text.runes.every(typeable)
          ? null
          : "The rig's US layout can't type some of these characters",
    ),
    StepKind.click => _choices(const {
      'left': 'Left',
      'middle': 'Middle',
      'right': 'Right',
    }),
    StepKind.scroll => _choices(const {'up': 'Up', 'down': 'Down'}),
    StepKind.media => _choices(ActionStep.mediaLabels),
    StepKind.volume => _choices(ActionStep.volumeLabels),
    StepKind.workspace => _field('Workspace number', number: true),
    StepKind.wait => _field('Milliseconds (1–10000)', number: true),
    StepKind.command => BlocBuilder<CommandsCubit, CommandsState>(
      bloc: widget.commands,
      builder: (context, s) => s.items.isEmpty
          ? EmptyNote(
              s.error ??
                  (s.loading
                      ? 'Loading…'
                      : 'No commands yet. Add some on the Commands page.'),
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in s.items)
                  IntrinsicWidth(
                    child: DeckButton(
                      c.label,
                      height: 42,
                      selected:
                          _command?.label == c.label && _command?.cmd == c.cmd,
                      onTap: () => setState(() => _command = c),
                    ),
                  ),
              ],
            ),
    ),
  };
}
