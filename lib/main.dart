import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/host_store.dart';
import 'data/native.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final f in ['IBMPlexMono', 'ChakraPetch']) {
      yield LicenseEntryWithLineBreaks([
        f,
      ], await rootBundle.loadString('assets/fonts/OFL-$f.txt'));
    }
  });
  // Whole app full screen: bars come back on an edge swipe, then hide again.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final prefs = await SharedPreferences.getInstance();
  final native = Native();
  // Asked before the first frame, so a locked phone never flashes the deck.
  final locked = await native.isLocked();
  runApp(
    HyprhandApp(
      prefs: prefs,
      store: HostStore(prefs),
      native: native,
      locked: locked,
    ),
  );
}
