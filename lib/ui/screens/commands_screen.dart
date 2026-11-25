import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/commands_cubit.dart';
import '../../data/models.dart';
import '../palette.dart';
import '../widgets.dart';

class CommandsScreen extends StatefulWidget {
  const CommandsScreen({super.key});
  @override
  State<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends State<CommandsScreen> {
  bool _manage = false;

  @override
  void initState() {
    super.initState();
    context.read<CommandsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CommandsCubit>();
    return BlocBuilder<CommandsCubit, CommandsState>(
      builder: (context, s) {
        return PageBody(
          onRefresh: cubit.load,
          children: [
            Row(
              children: [
                Expanded(
                  child: DeckButton(
                    _manage ? 'Done' : 'Manage',
                    icon: _manage ? Icons.check : Icons.tune,
                    selected: _manage,
                    onTap: () => setState(() => _manage = !_manage),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DeckButton(
                    'Add',
                    icon: Icons.add,
                    onTap: () => _edit(context, null),
                  ),
                ),
              ],
            ),
            if (s.error != null)
              EmptyNote(s.error!, onRetry: cubit.load)
            else if (s.loading)
              const EmptyNote('Loading…')
            else if (s.items.isEmpty)
              const EmptyNote(
                'No commands yet.\nAdd a shell command to run it with one tap.',
              )
            else if (_manage)
              for (final (i, c) in s.items.indexed)
                _row(context, c, i, s.items.length)
            else
              LayoutBuilder(
                builder: (context, box) {
                  final cols = (box.maxWidth / 150).floor().clamp(2, 5);
                  final w = (box.maxWidth - 10 * (cols - 1)) / cols;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final c in s.items)
                        SizedBox(
                          width: w,
                          child: DeckButton(
                            c.label,
                            height: 76,
                            busy: s.running.contains(c.id),
                            onTap: () => cubit.run(c),
                          ),
                        ),
                    ],
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, RigCommand c, int i, int n) {
    final p = context.pal;
    final cubit = context.read<CommandsCubit>();
    Widget act(String tip, IconData ic, VoidCallback? f, [Color? col]) =>
        IconButton(
          tooltip: tip,
          onPressed: f,
          icon: Icon(ic, size: 20),
          color: col ?? p.onVar,
        );
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.label,
            style: TextStyle(fontWeight: FontWeight.w600, color: p.on),
          ),
          Text(
            c.cmd,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: p.onVar),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              act(
                'Move up',
                Icons.arrow_upward,
                i == 0 ? null : () => cubit.move(c.id, -1),
              ),
              act(
                'Move down',
                Icons.arrow_downward,
                i == n - 1 ? null : () => cubit.move(c.id, 1),
              ),
              act('Edit', Icons.edit, () => _edit(context, c)),
              act('Delete', Icons.delete_outline, () async {
                if (await confirm(context, 'Delete “${c.label}”?', 'Delete')) {
                  cubit.delete(c.id);
                }
              }, Palette.danger),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, RigCommand? c) => deckSheet<void>(
    context,
    _CommandForm(cubit: context.read<CommandsCubit>(), initial: c),
  );
}

class _CommandForm extends StatefulWidget {
  const _CommandForm({required this.cubit, this.initial});
  final CommandsCubit cubit;
  final RigCommand? initial;
  @override
  State<_CommandForm> createState() => _CommandFormState();
}

class _CommandFormState extends State<_CommandForm> {
  late final _label = TextEditingController(text: widget.initial?.label);
  late final _cmd = TextEditingController(text: widget.initial?.cmd);
  bool _busy = false;

  @override
  void dispose() {
    _label.dispose();
    _cmd.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final ok = await widget.cubit.save(
      id: widget.initial?.id,
      label: _label.text,
      cmd: _cmd.text,
    );
    if (!mounted) return;
    ok ? Navigator.pop(context) : setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ready = _label.text.trim().isNotEmpty && _cmd.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(widget.initial == null ? 'New command' : 'Edit command'),
        TextField(
          controller: _label,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _cmd,
          onChanged: (_) => setState(() {}),
          minLines: 2,
          maxLines: 6,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Shell command',
            hintText: 'hyprctl reload',
          ),
        ),
        const SizedBox(height: 14),
        DeckButton(
          'Save',
          tone: Tone.primary,
          busy: _busy,
          onTap: ready ? _save : null,
        ),
      ],
    );
  }
}
