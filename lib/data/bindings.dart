import 'package:equatable/equatable.dart';

import 'models.dart';

enum PhoneButton {
  volumeUp('Volume up'),
  volumeDown('Volume down'),
  power('Power');

  const PhoneButton(this.label);
  final String label;
}

enum StepKind {
  keys('Keys'),
  text('Type text'),
  click('Mouse click'),
  scroll('Scroll'),
  media('Media'),
  volume('Volume'),
  workspace('Workspace'),
  command('Command'),
  wait('Wait');

  const StepKind(this.label);
  final String label;
}

/// One link of a chain. [args] is kind-specific: the chord for keys, a single
/// value otherwise, and label + shell text for saved commands.
class ActionStep extends Equatable {
  const ActionStep(this.kind, this.args);
  final StepKind kind;
  final List<String> args;

  String get describe => switch (kind) {
    StepKind.keys => args.map(_cap).join(' + '),
    StepKind.text => 'Type “${args.first}”',
    StepKind.click => '${_cap(args.first)} click',
    StepKind.scroll => 'Scroll ${args.first}',
    StepKind.media => mediaLabels[args.first] ?? args.first,
    StepKind.volume => volumeLabels[args.first] ?? args.first,
    StepKind.workspace => 'Workspace ${args.first}',
    StepKind.command => 'Run ${args.first}',
    StepKind.wait => 'Wait ${args.first} ms',
  };

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static const mediaLabels = {
    'play-pause': 'Play / pause',
    'next': 'Next track',
    'previous': 'Previous track',
  };
  static const volumeLabels = {
    'up': 'Volume +5',
    'down': 'Volume −5',
    'mute': 'Toggle speaker mute',
    'mic': 'Toggle mic mute',
  };

  Json toJson() => {'k': kind.name, 'a': args};

  static ActionStep? fromJson(Object? v) {
    if (v is! Map || v['a'] is! List) return null;
    final kind = StepKind.values.where((k) => k.name == v['k']).firstOrNull;
    final args = [for (final a in v['a'] as List) '$a'];
    if (kind == null || args.isEmpty) return null;
    if (kind == StepKind.command && args.length != 2) return null;
    return ActionStep(kind, args);
  }

  @override
  List<Object?> get props => [kind, args];
}

class ButtonBinding extends Equatable {
  const ButtonBinding({this.steps = const [], this.repeat = false});
  final List<ActionStep> steps;

  /// Run again while the button is held (volume buttons only).
  final bool repeat;

  Json toJson() => {
    'repeat': repeat,
    'steps': [for (final s in steps) s.toJson()],
  };
  factory ButtonBinding.fromJson(Object? v) {
    if (v is! Map) return const ButtonBinding();
    return ButtonBinding(
      repeat: v['repeat'] == true,
      steps: [
        for (final s in v['steps'] is List ? v['steps'] as List : const [])
          ?ActionStep.fromJson(s),
      ],
    );
  }

  @override
  List<Object?> get props => [steps, repeat];
}
