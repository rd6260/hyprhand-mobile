import 'package:equatable/equatable.dart';

/// Wire messages for /ws/input (see protocol::InputEvent).
class InputMessage extends Equatable {
  const InputMessage._(this.json);
  final Map<String, Object> json;

  factory InputMessage.move(int dx, int dy) =>
      InputMessage._({'t': 'move', 'dx': dx, 'dy': dy});
  factory InputMessage.scroll({int dx = 0, int dy = 0}) =>
      InputMessage._({'t': 'scroll', 'dx': dx, 'dy': dy});
  factory InputMessage.touch(List<List<double>> f) =>
      InputMessage._({'t': 'touch', 'f': f});
  factory InputMessage.click(String b) =>
      InputMessage._({'t': 'click', 'b': b});
  factory InputMessage.text(String s) =>
      InputMessage._({'t': 'text', 'text': s});
  factory InputMessage.combo(List<String> keys) =>
      InputMessage._({'t': 'combo', 'keys': keys});

  /// `type` is one of vmove, vclick, vrclick, vdown.
  factory InputMessage.video(
    String type,
    String monitor,
    double fx,
    double fy,
  ) => InputMessage._({'t': type, 'monitor': monitor, 'fx': fx, 'fy': fy});
  factory InputMessage.videoUp() => const InputMessage._({'t': 'vup'});

  @override
  List<Object?> get props => [json];
}
