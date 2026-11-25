import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyprhand_mobile/blocs/keyboard_cubit.dart';
import 'package:hyprhand_mobile/blocs/trackpad.dart';
import 'package:hyprhand_mobile/data/input_message.dart';

void main() {
  late List<InputMessage> sent;
  late Trackpad t;
  setUp(() {
    sent = [];
    t = Trackpad(sent.add);
  });

  group('trackpad', () {
    test('tap is a left click, even with jitter', () {
      t.down(1, 50, 50, 0);
      t.move(1, 51, 50, 300, 200);
      t.up(1, 100);
      expect(sent, [InputMessage.click('left')]);
    });
    test('slow press does nothing', () {
      t.down(1, 50, 50, 0);
      t.up(1, 600);
      expect(sent, isEmpty);
    });
    test('cancelled tap does not click', () {
      t.down(1, 50, 50, 0);
      t.up(1, 50, cancelled: true);
      expect(sent, isEmpty);
    });
    test('two-finger tap is a right click', () {
      t.down(1, 50, 50, 0);
      t.down(2, 100, 50, 20);
      t.up(1, 120);
      t.up(2, 130);
      expect(sent, [InputMessage.click('right')]);
    });
    test('drag moves and never clicks', () {
      t.down(1, 50, 50, 0);
      t.move(1, 60, 50, 300, 200);
      t.up(1, 80);
      expect(sent.map((m) => m.json['t']), ['move']);
      expect(sent.first.json['dx'], greaterThan(30));
    });
    test('parallel fingers scroll naturally; setting inverts it', () {
      void pan() {
        t.down(1, 50, 50, 0);
        t.down(2, 100, 50, 5);
        for (var y = 50.0; y <= 110; y += 5) {
          t.move(1, 50, y, 300, 200);
          t.move(2, 100, y, 300, 200);
        }
        t.up(1, 400);
        t.up(2, 400);
      }

      pan();
      expect(sent, isNotEmpty);
      expect(
        sent.every((m) => m.json['t'] == 'scroll' && m.json['dy'] == 1),
        isTrue,
      );
      sent.clear();
      t.naturalScroll = false;
      pan();
      expect(sent.every((m) => m.json['dy'] == -1), isTrue);
    });
    test('pinch forwards contacts and always lifts', () {
      t.down(1, 100, 100, 0);
      t.down(2, 200, 100, 5);
      for (var d = 0.0; d <= 40; d += 4) {
        t.move(1, 100 - d, 100, 300, 200);
        t.move(2, 200 + d, 100, 300, 200);
      }
      t.up(1, 400);
      t.up(2, 410);
      expect(sent.every((m) => m.json['t'] == 'touch'), isTrue);
      expect((sent.first.json['f'] as List).length, 2);
      expect(sent.last.json['f'], isEmpty);
      expect(sent.where((m) => (m.json['f'] as List).isEmpty).length, 1);
    });
    test('disposing mid-pinch releases the fingers', () {
      t.down(1, 100, 100, 0);
      t.down(2, 200, 100, 5);
      for (var d = 0.0; d <= 40; d += 4) {
        t.move(1, 100 - d, 100, 300, 200);
        t.move(2, 200 + d, 100, 300, 200);
      }
      t.reset();
      expect(sent.last, InputMessage.touch(const []));
    });
  });

  group('keyboard', () {
    KeyboardCubit kb() => KeyboardCubit(sent.add);
    test('letters, shift and shifted symbols', () {
      kb()
        ..char('a')
        ..toggleMod('shift')
        ..char('a')
        ..char('a')
        ..toggleMod('shift')
        ..char('1', shifted: '!');
      expect(sent, [
        InputMessage.text('a'),
        InputMessage.text('A'),
        InputMessage.text('a'),
        InputMessage.text('!'),
      ]);
    });
    test('ctrl+shift+o keeps both modifiers and the base key', () {
      kb()
        ..toggleMod('shift')
        ..toggleMod('ctrl')
        ..char('o');
      expect(sent, [
        InputMessage.combo(const ['ctrl', 'shift', 'o']),
      ]);
    });
    test('locked modifier survives, one-shot does not', () {
      final k = kb()
        ..toggleMod('alt', lock: true)
        ..toggleMod('shift')
        ..special('tab')
        ..special('tab');
      expect(sent, [
        InputMessage.combo(const ['alt', 'shift', 'tab']),
        InputMessage.combo(const ['alt', 'tab']),
      ]);
      k.toggleMod('alt');
      expect(k.state.isOn('alt'), isFalse);
    });
    blocTest<KeyboardCubit, KeyboardState>(
      'caps flips with shift',
      build: kb,
      act: (k) => k
        ..toggleCaps()
        ..char('a')
        ..toggleMod('shift')
        ..char('a'),
      verify: (_) =>
          expect(sent, [InputMessage.text('A'), InputMessage.text('a')]),
    );
  });

  group('diffTyping', () {
    final bs = InputMessage.combo(const ['backspace']);
    test(
      'append',
      () => expect(diffTyping('he', 'hey'), [InputMessage.text('y')]),
    );
    test('delete', () => expect(diffTyping('hey', 'h'), [bs, bs]));
    test(
      'autocorrect',
      () =>
          expect(diffTyping('teh', 'the '), [bs, bs, InputMessage.text('he ')]),
    );
    test('untypeable characters never cause stray backspaces', () {
      expect(diffTyping('a', 'a😀'), isEmpty);
      expect(diffTyping('a😀', 'a'), isEmpty);
      expect(diffTyping('a😀b', 'a'), [bs]);
      expect(diffTyping('😀', '😁'), isEmpty);
    });
  });
}
