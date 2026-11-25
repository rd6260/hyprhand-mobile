import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/deck_bloc.dart';
import '../../data/models.dart';
import '../palette.dart';
import '../widgets.dart';
import 'audio_screen.dart';

class DeckScreen extends StatelessWidget {
  const DeckScreen({super.key, required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final hypr = context.select((DeckBloc b) => b.state.frame.hypr);
    final hasFrame = context.select((DeckBloc b) => b.state.hasFrame);
    final cards = [
      for (var i = 0; i < hypr.monitors.length; i++)
        MonitorCard(index: i, hypr: hypr, fill: wide),
    ];
    final Widget body;
    if (cards.isEmpty) {
      body = Center(
        child: EmptyNote(
          hasFrame
              ? 'No monitors reported.\nIs Hyprland running on the rig?'
              : 'Waiting for the rig…',
        ),
      );
    } else if (wide) {
      body = Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, c) in cards.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: c),
            ],
          ],
        ),
      );
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => cards[i],
      );
    }
    return Column(
      children: [
        Expanded(child: body),
        const ContextStrip(),
        if (!wide) const MiniPlayer(),
      ],
    );
  }
}

class MonitorCard extends StatelessWidget {
  const MonitorCard({
    super.key,
    required this.index,
    required this.hypr,
    required this.fill,
  });
  final int index;
  final HyprInfo hypr;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final m = hypr.monitors[index];
    final bloc = context.read<DeckBloc>();
    final windows = hypr.windows.where((w) => w.monitor == m.name).toList();
    final tiles = [for (final w in windows) WindowTile(w)];
    return Panel(
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${m.name} · ${m.w}×${m.h} · ${m.refresh}Hz',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.onVar),
                ),
              ),
              if (m.focused) Icon(Icons.circle, size: 8, color: p.primary),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in hypr.workspacesFor(index))
                WorkspaceKey(
                  id: id,
                  active: m.activeWs == id,
                  occupied: windows.any((w) => w.ws == id),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _MonitorControls(m),
          const SizedBox(height: 6),
          if (tiles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No windows here',
                style: TextStyle(color: p.onVar, fontSize: 12),
              ),
            )
          else if (fill)
            Expanded(
              child: ListView(padding: EdgeInsets.zero, children: tiles),
            )
          else
            ...tiles,
          if (tiles.isNotEmpty && !fill)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Hold a window, then drop it on a workspace',
                style: TextStyle(
                  color: p.onVar.withValues(alpha: .7),
                  fontSize: 11,
                ),
              ),
            ),
          if (!m.dpms)
            DeckButton(
              'Display is off — wake',
              tone: Tone.primary,
              onTap: () => bloc.add(DpmsSet(m.name, true)),
            ),
        ],
      ),
    );
  }
}

class WorkspaceKey extends StatelessWidget {
  const WorkspaceKey({
    super.key,
    required this.id,
    required this.active,
    required this.occupied,
  });
  final int id;
  final bool active, occupied;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final size = MediaQuery.sizeOf(context).width < 360 ? 46.0 : 50.0;
    final bloc = context.read<DeckBloc>();
    return DragTarget<RigWindow>(
      onWillAcceptWithDetails: (d) => d.data.ws != id,
      onAcceptWithDetails: (d) {
        tick(context);
        bloc.add(WindowMoved(d.data.address, id));
      },
      builder: (context, over, _) => Semantics(
        button: true,
        selected: active,
        label: 'Workspace $id',
        excludeSemantics: true,
        onTap: () => bloc.add(WorkspaceFocused(id)),
        child: GestureDetector(
          onTap: () {
            tick(context);
            bloc.add(WorkspaceFocused(id));
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? p.primary.withValues(alpha: .88) : p.high,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                width: over.isNotEmpty ? 2.5 : 1,
                color: over.isNotEmpty
                    ? p.secondary
                    : occupied
                    ? p.primary.withValues(alpha: .6)
                    : p.outline,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: p.primary.withValues(alpha: .4),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Text(
              '$id',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: active ? p.onPrimary : (occupied ? p.on : p.onVar),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WindowTile extends StatelessWidget {
  const WindowTile(this.w, {super.key});
  final RigWindow w;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final ws = w.ws;
    final tile = Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: w.focused ? p.tint(.14) : p.high,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: w.focused ? p.primary : p.outline),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              ws == null ? '' : (ws < 0 ? 'S' : '$ws'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: p.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              w.display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: w.focused ? p.primary : p.on,
              ),
            ),
          ),
          if (w.title.isNotEmpty && w.cls.isNotEmpty) ...[
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 90),
              child: Text(
                w.cls,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: p.onVar),
              ),
            ),
          ],
        ],
      ),
    );
    return LongPressDraggable<RigWindow>(
      data: w,
      delay: const Duration(milliseconds: 350),
      hapticFeedbackOnStart: true,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: PaletteScope(
        palette: p,
        child: FractionalTranslation(
          translation: const Offset(-.5, -1.2),
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 220,
              child: Opacity(opacity: .92, child: tile),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: .35, child: tile),
      child: GestureDetector(
        onTap: () {
          tick(context);
          context.read<DeckBloc>().add(WindowFocused(w.address));
        },
        child: tile,
      ),
    );
  }
}

class _MonitorControls extends StatefulWidget {
  const _MonitorControls(this.m);
  final Monitor m;
  @override
  State<_MonitorControls> createState() => _MonitorControlsState();
}

class _MonitorControlsState extends State<_MonitorControls> {
  double? _drag;
  @override
  Widget build(BuildContext context) {
    final p = context.pal, m = widget.m;
    final bloc = context.read<DeckBloc>();
    final pct = context.select((DeckBloc b) => b.state.brightness[m.name]);
    final v = _drag ?? pct?.toDouble();
    return Row(
      children: [
        IconButton(
          tooltip: m.dpms ? 'Turn display off' : 'Turn display on',
          onPressed: () => bloc.add(DpmsSet(m.name, !m.dpms)),
          icon: Icon(
            m.dpms ? Icons.desktop_windows : Icons.desktop_access_disabled,
            size: 20,
            color: m.dpms ? p.primary : Palette.danger,
          ),
        ),
        if (v != null) ...[
          Icon(Icons.brightness_6, size: 18, color: p.onVar),
          Expanded(
            child: Slider(
              value: v.clamp(0, 100),
              max: 100,
              onChanged: (x) => setState(() => _drag = x),
              onChangeEnd: (x) {
                setState(() => _drag = null);
                bloc.add(BrightnessSet(m.name, x.round()));
              },
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${v.round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: p.onVar),
            ),
          ),
        ],
      ],
    );
  }
}

/// Per-app shortcut buttons and call controls from the rig's context config.
class ContextStrip extends StatelessWidget {
  const ContextStrip({super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return BlocBuilder<DeckBloc, DeckState>(
      buildWhen: (a, b) =>
          a.context != b.context ||
          a.frame.hypr != b.frame.hypr ||
          a.frame.audio.recording != b.frame.audio.recording ||
          a.frame.audio.micMuted != b.frame.audio.micMuted,
      builder: (context, s) {
        final bloc = context.read<DeckBloc>();
        final f = s.frame;
        final call = s.context.inCall(f.audio);
        final win = call ? s.context.callWindow(f.hypr, f.audio) : null;
        final apps = s.context.visible(f.hypr);
        if (!call && apps.isEmpty) return const SizedBox.shrink();
        Widget label(String t) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            t.toUpperCase(),
            style: TextStyle(
              fontFamily: display,
              fontSize: 11,
              letterSpacing: 1.2,
              color: p.secondary,
            ),
          ),
        );
        Widget gap(Widget w) =>
            Padding(padding: const EdgeInsets.only(right: 6), child: w);
        return Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.outline)),
          ),
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            children: [
              if (call) ...[
                Center(child: label('Call')),
                gap(
                  DeckButton(
                    f.audio.micMuted ? 'Unmute' : 'Mute',
                    height: 42,
                    tone: f.audio.micMuted ? Tone.danger : Tone.normal,
                    onTap: () => bloc.add(const MuteToggled(mic: true)),
                  ),
                ),
                if (win != null)
                  gap(
                    DeckButton(
                      'Go to call',
                      height: 42,
                      onTap: () => bloc.add(WindowFocused(win.address)),
                    ),
                  ),
              ],
              for (final a in apps) ...[
                Center(child: label(a.label)),
                for (final c in a.controls)
                  gap(
                    DeckButton(
                      c.label,
                      height: 42,
                      onTap: () => bloc.add(ContextKeyPressed(a.cls, c)),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
