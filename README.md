# hyprhand mobile

Flutter Android client for [hyprhand](../hyprhand). Talks to the stock server: HTTP + `/ws` + `/ws/input`.

- `lib/data` – models, HTTP client, reconnecting sockets, storage, native bridge
- `lib/blocs` – all state (flutter_bloc) plus the pure trackpad/keyboard logic
- `lib/ui` – screens; palette comes from the rig's `/theme.css`
- `android/…/MainActivity.kt` – share target, volume keys, file picker, gallery save

```sh
flutter test
SHOTS=/some/dir flutter test test/screens_test.dart   # render every screen to PNG
flutter build apk --release --split-per-abi
```

Release builds are signed with the debug key until a signing config is added.
