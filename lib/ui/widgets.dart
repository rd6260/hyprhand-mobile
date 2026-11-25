import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/settings_cubit.dart';
import 'palette.dart';

void tick(BuildContext c) {
  if (c.read<SettingsCubit>().state.haptics) HapticFeedback.selectionClick();
}

/// Amber section title trailing into a rule.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: display,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 1.6,
              color: p.secondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: p.outline)),
        ],
      ),
    );
  }
}

/// Framed surface with the deck's corner ticks.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return CustomPaint(
      foregroundPainter: _Ticks(p.primary.withValues(alpha: .55)),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [p.surface, p.low],
          ),
        ),
        child: child,
      ),
    );
  }
}

class _Ticks extends CustomPainter {
  _Ticks(this.c);
  final Color c;
  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = c
      ..style = PaintingStyle.stroke;
    const i = 3.0, l = 11.0;
    canvas.drawPath(
      Path()
        ..moveTo(i, i + l)
        ..lineTo(i, i)
        ..lineTo(i + l, i)
        ..moveTo(s.width - i - l, s.height - i)
        ..lineTo(s.width - i, s.height - i)
        ..lineTo(s.width - i, s.height - i - l),
      paint,
    );
  }

  @override
  bool shouldRepaint(_Ticks o) => o.c != c;
}

enum Tone { normal, primary, danger }

class DeckButton extends StatefulWidget {
  const DeckButton(
    this.label, {
    super.key,
    this.icon,
    this.onTap,
    this.tone = Tone.normal,
    this.selected = false,
    this.busy = false,
    this.height = 48,
  });
  final String? label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Tone tone;
  final bool selected, busy;
  final double height;
  @override
  State<DeckButton> createState() => _DeckButtonState();
}

class _DeckButtonState extends State<DeckButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final p = context.pal, w = widget;
    final on = w.onTap != null && !w.busy;
    final filled = w.tone == Tone.primary;
    final accent = w.tone == Tone.danger ? Palette.danger : p.primary;
    final lit = _down || w.selected;
    final fg = filled
        ? p.onPrimary
        : (lit || w.tone == Tone.danger ? accent : p.on);
    return Semantics(
      button: true,
      enabled: on,
      selected: w.selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: on
            ? () {
                tick(context);
                w.onTap!();
              }
            : null,
        child: Opacity(
          opacity: on || w.busy ? 1 : .4,
          child: Container(
            constraints: BoxConstraints(minHeight: w.height, minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled
                  ? p.primary.withValues(alpha: _down ? 1 : .88)
                  : lit
                  ? Color.alphaBlend(accent.withValues(alpha: .18), p.bg)
                  : p.high,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: lit ? accent : p.outline),
              boxShadow: lit
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: .28),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (w.busy)
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else if (w.icon != null)
                  Icon(w.icon, size: 20, color: fg),
                if ((w.busy || w.icon != null) && w.label != null)
                  const SizedBox(width: 8),
                if (w.label != null)
                  Flexible(
                    child: Text(
                      w.label!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: display,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: .5,
                        color: fg,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Terminal segmented control.
class Seg<T> extends StatelessWidget {
  const Seg({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });
  final Map<T, String> items;
  final T? value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final e in items.entries)
        IntrinsicWidth(
          child: DeckButton(
            e.value,
            height: 42,
            selected: e.key == value,
            onTap: () => onChanged(e.key),
          ),
        ),
    ],
  );
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    final list = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(14),
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) => children[i],
    );
    return onRefresh == null
        ? list
        : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.onBack, this.trailing});
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 0),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: Icon(Icons.chevron_left, color: p.onVar),
            ),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontFamily: display,
                fontWeight: FontWeight.w700,
                fontSize: 17,
                letterSpacing: 3,
                color: p.primary,
                shadows: [
                  Shadow(
                    color: p.primary.withValues(alpha: .45),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.onRetry});
  final String text;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.pal.onVar, height: 1.5),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 14),
          DeckButton('Try again', onTap: onRetry),
        ],
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String action) async {
  final p = context.pal;
  return await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: p.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: p.outline),
          ),
          content: Text(title, style: TextStyle(color: p.on, height: 1.4)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('Cancel', style: TextStyle(color: p.onVar)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(
                action,
                style: const TextStyle(color: Palette.danger),
              ),
            ),
          ],
        ),
      ) ??
      false;
}

Future<T?> deckSheet<T>(BuildContext context, Widget child) {
  final p = context.pal;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: p.surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      side: BorderSide(color: p.outline),
    ),
    builder: (c) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          18,
          16,
          16 + MediaQuery.viewInsetsOf(c).bottom,
        ),
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}

/// Static CRT scanlines; painted once and never hit-tested.
class Scanlines extends StatelessWidget {
  const Scanlines({super.key});
  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(painter: _ScanPainter(), size: Size.infinite),
    ),
  );
}

class _ScanPainter extends CustomPainter {
  const _ScanPainter();
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0x1A000000);
    for (var y = 2.0; y < s.height; y += 3) {
      c.drawRect(Rect.fromLTWH(0, y, s.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
