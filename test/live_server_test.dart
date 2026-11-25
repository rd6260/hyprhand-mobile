import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hyprhand_mobile/blocs/config_cubit.dart';
import 'package:hyprhand_mobile/blocs/deck_bloc.dart';
import 'package:hyprhand_mobile/blocs/notice_cubit.dart';
import 'package:hyprhand_mobile/data/deck_repository.dart';
import 'package:hyprhand_mobile/data/hypr_client.dart';
import 'package:hyprhand_mobile/data/models.dart';
import 'package:hyprhand_mobile/ui/palette.dart';

/// Opt-in, against a throwaway server:
/// LIVE_RIG=http://127.0.0.1:8899 LIVE_PIN=… flutter test test/live_server_test.dart
/// Never sends input or changes desktop state (it does edit config and upload).
void main() {
  final url = Platform.environment['LIVE_RIG'];
  test(
    'real hyprhand server',
    () async {
      HttpOverrides.global = null;
      final c = HyprClient(Uri.parse(url!));
      await c.login(Platform.environment['LIVE_PIN']!);
      final bloc = DeckBloc(
        DeckRepository(RigHost(url: url, label: 'live'), c),
        NoticeCubit(),
      )..add(const DeckResumed());
      final s = await bloc.stream
          .firstWhere(
            (s) =>
                s.frame.hypr.monitors.isNotEmpty &&
                s.frame.telemetry.cpu != null &&
                s.frame.sys.procs.isNotEmpty,
          )
          .timeout(const Duration(seconds: 20));
      final mon = s.frame.hypr.monitors.first;
      expect(mon.w, greaterThan(0));
      expect(
        s.frame.sys.procs.first.fraction(s.frame.telemetry.cpu!.memTotal),
        inInclusiveRange(0.0, 1.0),
      );
      expect(
        Palette.fromCss(await c.themeCss()).primary,
        Palette.green.primary,
      );
      expect(await c.inputAvailable(), isTrue);

      final cfg = ConfigCubit(c);
      await cfg.open('modes');
      expect(
        await cfg.save('[{"name":"T","steps":[{"type":"bogus"}]}]'),
        isFalse,
      ); // server rejects
      expect(await cfg.save('[{"name":"T","steps":[]}]'), isTrue);
      expect((await c.call('/modes/run', {'id': 'T'}))['steps'], isEmpty);

      final d = await Directory.systemTemp.createTemp();
      final f = await File('${d.path}/x').writeAsBytes(List.filled(1500000, 7));
      expect((await c.upload(f, 'x.bin'))['size'], 1500000);
      await f.writeAsBytes(List.filled(3000000, 7));
      await expectLater(c.upload(f, 'big2.bin'), throwsA(isA<ApiException>()));
      await d.delete(recursive: true);
      await bloc.close();
    },
    skip: url == null ? 'set LIVE_RIG' : false,
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
