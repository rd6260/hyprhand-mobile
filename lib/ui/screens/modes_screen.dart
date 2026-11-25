import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/deck_bloc.dart';
import '../../blocs/modes_cubit.dart';
import '../palette.dart';
import '../widgets.dart';

class ModesScreen extends StatelessWidget {
  const ModesScreen({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => ModesCubit(c.read<DeckBloc>().repo.client)..load(),
    child: BlocBuilder<ModesCubit, ModesState>(
      builder: (context, s) {
        final cubit = context.read<ModesCubit>();
        final p = context.pal;
        return PageBody(
          onRefresh: cubit.load,
          children: [
            if (s.error != null)
              EmptyNote(s.error!, onRetry: cubit.load)
            else if (s.loading)
              const EmptyNote('Loading…')
            else if (s.items.isEmpty)
              const EmptyNote('No modes yet.\nAdd them under Config → modes.')
            else
              for (final m in s.items)
                DeckButton(
                  m.label,
                  height: 72,
                  busy: s.running == m.id,
                  onTap: s.running == null ? () => cubit.run(m) : null,
                ),
            if (s.output.isNotEmpty)
              Panel(
                child: Text(
                  '\$ ${s.output.join('\n  ')}',
                  style: TextStyle(fontSize: 13, height: 1.5, color: p.primary),
                ),
              ),
          ],
        );
      },
    ),
  );
}
