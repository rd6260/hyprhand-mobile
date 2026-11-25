import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/hypr_client.dart';
import '../ui/palette.dart';

class ThemeState extends Equatable {
  const ThemeState({this.palette = Palette.green, this.profile = 'green'});
  final Palette palette;
  final String profile;

  ThemeState copyWith({Palette? palette, String? profile}) => ThemeState(
    palette: palette ?? this.palette,
    profile: profile ?? this.profile,
  );
  @override
  List<Object?> get props => [palette, profile];
}

/// The rig owns the theme: colours come from its live theme.css, so a matugen
/// palette ("auto") re-skins the app too. The last one is cached for startup.
class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit(this._p)
    : super(
        ThemeState(palette: Palette.fromCss(_p.getString('theme_css') ?? '')),
      );
  final SharedPreferences _p;

  Future<void> load(HyprClient c) async {
    try {
      final j = await c.getJson('/theme') as Map;
      if (isClosed) return;
      emit(state.copyWith(profile: '${j['profile'] ?? 'green'}'));
      await _css(c);
    } on ApiException {
      // keep whatever we have
    }
  }

  Future<void> _css(HyprClient c) async {
    final css = await c.themeCss();
    if (isClosed) return;
    emit(state.copyWith(palette: Palette.fromCss(css)));
    final end = css.indexOf('}');
    await _p.setString('theme_css', end < 0 ? '' : css.substring(0, end + 1));
  }

  Future<void> setProfile(HyprClient c, String profile) async {
    await c.call('/theme', {'profile': profile});
    if (isClosed) return;
    emit(state.copyWith(profile: profile));
    await _css(c);
  }
}
