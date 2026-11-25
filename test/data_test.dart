import 'package:flutter_test/flutter_test.dart';
import 'package:hyprhand_mobile/data/models.dart';
import 'package:hyprhand_mobile/ui/palette.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('host parsing', () {
    expect(RigHost.parse('192.168.1.20')!.url, 'http://192.168.1.20:8765');
    expect(RigHost.parse('eva:9000')!.url, 'http://eva:9000');
    expect(RigHost.parse('eva.tail1.ts.net')!.url, 'https://eva.tail1.ts.net');
    expect(RigHost.parse('eva.tail1.ts.net')!.label, 'eva');
    expect(
      RigHost.parse('https://eva.tail1.ts.net/x?y=1')!.url,
      'https://eva.tail1.ts.net',
    );
    expect(RigHost.parse('http://eva')!.url, 'http://eva');
    for (final bad in ['', 'a b', 'ftp://x', 'http://', 'javascript://x']) {
      expect(RigHost.parse(bad), isNull, reason: bad);
    }
  });

  test('frame parsing survives missing parts', () {
    expect(DeckFrame.fromJson(const {}), const DeckFrame());
    final f = DeckFrame.fromJson(const {
      'audio': {
        'volume': 40,
        'now_playing': {'duration_us': null},
      },
      'telemetry': {
        'cpu': {'util': 3, 'temp': null, 'mem_used': 1, 'mem_total': 16},
        'gpu': null,
      },
    });
    expect(f.audio.volume, 40);
    expect(f.telemetry.cpu!.temp, isNull);
    expect(f.telemetry.gpu, isNull);
  });

  test('process memory: sane percentages and bytes×100 servers', () {
    expect(const Proc(1, 'x', 12.5, false).fraction(16), .125);
    expect(
      const Proc(1, 'x', 126907600000, false).fraction(15),
      closeTo(.0788, .001),
    );
    expect(const Proc(1, 'x', 126907600000, false).fraction(0), 0);
  });

  test('workspaces: block per monitor plus occupied extras, no specials', () {
    const h = HyprInfo(
      monitors: [
        Monitor('A', '', 1, 1, 60, 1, true, true),
        Monitor('B', '', 1, 1, 60, 12, false, true),
      ],
      windows: [
        RigWindow('0x1', '', 'k', -98, 'A', false),
        RigWindow('0x2', '', 'k', 9, 'A', false),
      ],
    );
    expect(h.workspacesFor(0), [1, 2, 3, 4, 5, 9]);
    expect(h.workspacesFor(1), [6, 7, 8, 9, 10, 12]);
  });

  test('context visibility and calls', () {
    final c = ContextConfig.fromJson(const {
      'apps': {
        'mpv': {
          'label': 'MPV',
          'show': 'focus',
          'controls': [
            {'label': 'P', 'key': 'p'},
          ],
        },
        'obs': {'label': 'OBS', 'show': 'persist', 'controls': []},
      },
      'call_apps': ['discord'],
    });
    const h = HyprInfo(
      activeClass: 'kitty',
      windows: [RigWindow('0x1', '', 'obs', 1, 'A', false)],
    );
    expect(c.visible(h).map((a) => a.label), ['OBS']);
    expect(c.inCall(const AudioInfo(recording: ['Discord'])), isFalse);
    expect(c.inCall(const AudioInfo(recording: ['.discord-wrapped'])), isTrue);
  });

  test('palette css', () {
    final p = Palette.fromCss(
      ':root{--p-primary: #ffb000; --p-bg:#000;--p-outline: rgba(255,176,0,.18);--p-on: junk;}',
    );
    expect(p.primary, const Color(0xFFFFB000));
    expect(p.bg, const Color(0xFF000000));
    expect(p.outline.a, closeTo(.18, .01));
    expect(p.on, Palette.green.on);
    expect(Palette.parseColor('#11223380'), const Color(0x80112233));
    expect(Palette.parseColor('rgb(1 2 3 / 50%)')!.a, closeTo(.5, .01));
    expect(Palette.fromCss(''), Palette.green);
  });
}
