import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/deck_bloc.dart';
import '../../data/models.dart';
import '../palette.dart';
import '../widgets.dart';

class SystemScreen extends StatelessWidget {
  const SystemScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final sys = context.select((DeckBloc b) => b.state.frame.sys);
    final t = context.select((DeckBloc b) => b.state.frame.telemetry);
    final total = t.cpu?.memTotal ?? 0;
    return PageBody(
      children: [
        if (t.cpu != null || t.gpu != null)
          Panel(
            child: Column(
              children: [
                if (t.cpu case final c?) ...[
                  Meter(
                    'CPU',
                    c.util / 100,
                    '${c.util.round()}%${c.temp == null ? '' : ' · ${c.temp!.round()}°'}',
                  ),
                  Meter(
                    'RAM',
                    c.memTotal == 0 ? 0 : c.memUsed / c.memTotal,
                    '${c.memUsed.toStringAsFixed(1)}/${c.memTotal.toStringAsFixed(0)}G',
                  ),
                ],
                if (t.gpu case final g?) ...[
                  Meter(
                    'GPU',
                    g.util / 100,
                    '${g.util.round()}% · ${g.temp.round()}°',
                  ),
                  Meter(
                    'VRAM',
                    g.vramTotal == 0 ? 0 : g.vramUsed / g.vramTotal,
                    '${(g.vramUsed / 1024).toStringAsFixed(1)}/${(g.vramTotal / 1024).toStringAsFixed(0)}G',
                  ),
                ],
              ],
            ),
          ),
        Panel(
          child: Row(
            children: [
              Icon(
                Icons.hub,
                size: 18,
                color: sys.tailscaleUp ? p.primary : p.onVar,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sys.tailscaleUp
                      ? 'Tailscale up · ${sys.tailscaleSelf ?? ''} · ${sys.peersOnline}/${sys.peersTotal} peers online'
                      : 'Tailscale down',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        DeckButton(
          'Lock the rig',
          icon: Icons.lock_outline,
          onTap: () async {
            final b = context.read<DeckBloc>();
            if (await confirm(context, 'Lock the rig with hyprlock?', 'Lock')) {
              b.add(const LockRequested());
            }
          },
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Top processes by memory'),
              if (sys.procs.isEmpty) const EmptyNote('Waiting for data…'),
              for (final x in sys.procs) _ProcRow(x, x.fraction(total)),
            ],
          ),
        ),
      ],
    );
  }
}

class Meter extends StatelessWidget {
  const Meter(this.label, this.value, this.text, {super.key});
  final String label, text;
  final double value;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = value >= .9
        ? Palette.danger
        : (value >= .8 ? p.secondary : p.primary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(label, style: TextStyle(fontSize: 12, color: p.onVar)),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: value.clamp(0, 1),
              minHeight: 8,
              color: c,
              backgroundColor: p.high,
            ),
          ),
          SizedBox(
            width: 96,
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcRow extends StatelessWidget {
  const _ProcRow(this.x, this.frac);
  final Proc x;
  final double frac;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        Expanded(
          child: Text(
            x.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        SizedBox(
          width: 70,
          child: LinearProgressIndicator(
            value: frac.clamp(0, 1),
            minHeight: 8,
            color: p.primary,
            backgroundColor: p.high,
          ),
        ),
        SizedBox(
          width: 54,
          child: Text(
            '${(frac * 100).toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: p.primary),
          ),
        ),
        IconButton(
          tooltip: 'End ${x.name}',
          icon: const Icon(Icons.close, size: 18, color: Palette.danger),
          onPressed: () async {
            final b = context.read<DeckBloc>();
            if (await confirm(
              context,
              'Send SIGTERM to ${x.name} (pid ${x.pid})? Unsaved work in it may be lost.',
              'End process',
            )) {
              b.add(ProcessKilled(x));
            }
          },
        ),
      ],
    );
  }
}
