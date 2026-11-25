import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Settings extends Equatable {
  const Settings({
    this.sensitivity = 3.0,
    this.naturalScroll = true,
    this.haptics = true,
    this.keepAwake = true,
    this.volumeKeys = true,
    this.scanlines = true,
  });
  final double sensitivity;
  final bool naturalScroll, haptics, keepAwake, volumeKeys, scanlines;

  Settings copyWith({
    double? sensitivity,
    bool? naturalScroll,
    bool? haptics,
    bool? keepAwake,
    bool? volumeKeys,
    bool? scanlines,
  }) => Settings(
    sensitivity: sensitivity ?? this.sensitivity,
    naturalScroll: naturalScroll ?? this.naturalScroll,
    haptics: haptics ?? this.haptics,
    keepAwake: keepAwake ?? this.keepAwake,
    volumeKeys: volumeKeys ?? this.volumeKeys,
    scanlines: scanlines ?? this.scanlines,
  );

  @override
  List<Object?> get props => [
    sensitivity,
    naturalScroll,
    haptics,
    keepAwake,
    volumeKeys,
    scanlines,
  ];
}

class SettingsCubit extends Cubit<Settings> {
  SettingsCubit(this._p) : super(_load(_p));
  final SharedPreferences _p;

  static Settings _load(SharedPreferences p) {
    const d = Settings();
    return Settings(
      sensitivity: p.getDouble('s.sens') ?? d.sensitivity,
      naturalScroll: p.getBool('s.natural') ?? d.naturalScroll,
      haptics: p.getBool('s.haptics') ?? d.haptics,
      keepAwake: p.getBool('s.awake') ?? d.keepAwake,
      volumeKeys: p.getBool('s.volkeys') ?? d.volumeKeys,
      scanlines: p.getBool('s.scan') ?? d.scanlines,
    );
  }

  void update(Settings s) {
    emit(s);
    _p.setDouble('s.sens', s.sensitivity);
    _p.setBool('s.natural', s.naturalScroll);
    _p.setBool('s.haptics', s.haptics);
    _p.setBool('s.awake', s.keepAwake);
    _p.setBool('s.volkeys', s.volumeKeys);
    _p.setBool('s.scan', s.scanlines);
  }
}
