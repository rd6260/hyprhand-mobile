import 'package:equatable/equatable.dart';
import 'package:material_ui/material_ui.dart';

/// Phosphor colours, mirroring the server's `--p-*` CSS variables.
class Palette extends Equatable {
  const Palette({
    required this.primary,
    required this.secondary,
    required this.on,
    required this.onPrimary,
    required this.onVar,
    required this.bg,
    required this.surface,
    required this.high,
    required this.low,
    required this.outline,
  });
  final Color primary, secondary, on, onPrimary, onVar;
  final Color bg, surface, high, low, outline;

  static const danger = Color(0xFFFF5252);

  static const green = Palette(
    primary: Color(0xFF33FFA0),
    secondary: Color(0xFFFFB000),
    on: Color(0xFFE4F7ED),
    onPrimary: Color(0xFF001A0D),
    onVar: Color(0xFF7FA98E),
    bg: Color(0xFF000000),
    surface: Color(0xFF0A0F0C),
    high: Color(0xFF111A14),
    low: Color(0xFF060D09),
    outline: Color(0x2E33FFA0),
  );

  /// Anything missing or unreadable falls back to green.
  factory Palette.fromCss(String css) {
    final v = <String, Color>{};
    for (final m in RegExp(r'--p-([a-z-]+)\s*:\s*([^;}]+)').allMatches(css)) {
      final c = parseColor(m[2]!);
      if (c != null) v.putIfAbsent(m[1]!, () => c);
    }
    const g = green;
    return Palette(
      primary: v['primary'] ?? g.primary,
      secondary: v['secondary'] ?? g.secondary,
      on: v['on'] ?? g.on,
      onPrimary: v['on-primary'] ?? g.onPrimary,
      onVar: v['on-var'] ?? g.onVar,
      bg: v['bg'] ?? g.bg,
      surface: v['surface'] ?? g.surface,
      high: v['high'] ?? g.high,
      low: v['low'] ?? g.low,
      outline: v['outline'] ?? g.outline,
    );
  }

  static Color? parseColor(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.startsWith('#')) {
      var h = s.substring(1);
      if (h.length == 3 || h.length == 4) {
        h = h.split('').map((c) => c + c).join();
      }
      if (h.length == 6) h = '${h}ff';
      final n = h.length == 8 ? int.tryParse(h, radix: 16) : null;
      if (n == null) return null;
      return Color(((n & 0xFF) << 24) | (n >> 8)); // rgba → argb
    }
    final m = RegExp(r'^rgba?\(([^)]+)\)$').firstMatch(s);
    if (m == null) return null;
    final p = m[1]!
        .split(RegExp(r'[,\s/]+'))
        .where((x) => x.isNotEmpty)
        .toList();
    if (p.length < 3) return null;
    final rgb = [for (final x in p.take(3)) double.tryParse(x)];
    if (rgb.contains(null)) return null;
    var a = 1.0;
    if (p.length > 3) {
      a = p[3].endsWith('%')
          ? (double.tryParse(p[3].replaceAll('%', '')) ?? 100) / 100
          : double.tryParse(p[3]) ?? 1;
    }
    int ch(double? x) => x!.round().clamp(0, 255);
    return Color.fromRGBO(ch(rgb[0]), ch(rgb[1]), ch(rgb[2]), a.clamp(0, 1));
  }

  /// Counter-colour for the CPU dials: amber unless the theme is already warm.
  Color get counter {
    final hue = HSVColor.fromColor(primary).hue;
    return (hue - 41).abs() < 40
        ? const Color(0xFF33FFA0)
        : const Color(0xFFFFB000);
  }

  Color tint(double a) => Color.alphaBlend(primary.withValues(alpha: a), bg);

  @override
  List<Object?> get props => [
    primary,
    secondary,
    on,
    onPrimary,
    onVar,
    bg,
    surface,
    high,
    low,
    outline,
  ];
}

class PaletteScope extends InheritedWidget {
  const PaletteScope({super.key, required this.palette, required super.child});
  final Palette palette;
  @override
  bool updateShouldNotify(PaletteScope old) => old.palette != palette;
}

extension PaletteContext on BuildContext {
  Palette get pal =>
      dependOnInheritedWidgetOfExactType<PaletteScope>()?.palette ??
      Palette.green;
}

const mono = 'IBMPlexMono';
const display = 'ChakraPetch';

ThemeData buildTheme(Palette p) {
  OutlineInputBorder border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: c),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: mono,
    scaffoldBackgroundColor: p.bg,
    splashFactory: NoSplash.splashFactory,
    colorScheme: ColorScheme.dark(
      primary: p.primary,
      onPrimary: p.onPrimary,
      secondary: p.secondary,
      surface: p.surface,
      onSurface: p.on,
      onSurfaceVariant: p.onVar,
      outline: p.outline,
      error: Palette.danger,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: p.primary,
      inactiveTrackColor: p.high,
      thumbColor: p.primary,
      overlayColor: p.primary.withValues(alpha: .12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: p.low,
      hintStyle: TextStyle(color: p.onVar.withValues(alpha: .7)),
      labelStyle: TextStyle(color: p.onVar),
      border: border(p.outline),
      enabledBorder: border(p.outline),
      focusedBorder: border(p.primary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.primary : p.onVar,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.tint(.22) : p.low,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.primary : p.outline,
      ),
    ),
  );
}
