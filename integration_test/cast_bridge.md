# 2-emulator cast bridge (QA harness)

Reusable recipe for exercising the second-screen **cast** flow across **two
emulators** (Android TV receiver + phone sender) without relying on mDNS, which
is not reliable between two NAT'd emulators. A small **dart-define-gated debug
hook** in `lib/` bypasses discovery and pins the receiver's wss port so it can be
`adb`-forwarded/reversed.

> The `lib/` hooks are **DEBUG-ONLY and must NOT ship**. They are inert when the
> dart-defines are unset (production builds pass none). This doc includes how to
> **re-apply** and how to **revert** them. As of the QA run they are reverted;
> git is clean of the hook lines.

Devices used here:
- `emulator-5554` = `tv_1080p` (Android TV) → **receiver**
- `emulator-5556` = `phone_compact` → **sender**

Host tool paths in this lab: `adb` = `/home/debian/android-lab/sdk/platform-tools/adb`,
`flutter` = `/home/debian/android-lab/flutter/bin/flutter`.

---

## 1. The debug hook (apply to `lib/`, revert after)

### `lib/services/cast/tv_receiver_service.dart` — pin the wss port + print it
Inside `Future<int> start(...)`, resolve the bind port from a dart-define and
print the bound port + PIN:

```dart
const debugRecvPort = int.fromEnvironment('CAST_RECV_PORT');
final bindPort = debugRecvPort > 0 ? debugRecvPort : 0;
// ... bindSecure(InternetAddress.anyIPv4, bindPort, ctx, shared: true)  (and bind())
if (debugRecvPort > 0) {
  print('CAST_RECV_BOUND=${_server!.port} pin=${pin}'); // read the PIN from logcat
}
```

### `lib/controllers/cast_sender_controller.dart` — skip discovery, connect direct
At the top of `beginCast(...)` right after `_set(CastPhase.discovering);`:

```dart
const debugHost = String.fromEnvironment('CAST_DEBUG_HOST');
const debugPort = int.fromEnvironment('CAST_DEBUG_PORT');
if (debugHost.isNotEmpty && debugPort > 0) {
  await connectTo(CastDevice(
      name: 'debug-bridge', host: debugHost, port: debugPort, secure: true));
  return;
}
```

Unset dart-defines → `debugRecvPort == 0` and `debugHost.isEmpty` → **identical to
shipped** (ephemeral port, normal mDNS discovery).

### Revert
```bash
cd /home/debian/workspace/rensi-iptv
git checkout -- lib/services/cast/tv_receiver_service.dart lib/controllers/cast_sender_controller.dart
```

---

## 2. Build the PROFILE app with the bridge and install on both

```bash
cd /home/debian/workspace/rensi-iptv
flutter build apk --profile \
  --dart-define=CAST_RECV_PORT=47700 \
  --dart-define=CAST_DEBUG_HOST=127.0.0.1 \
  --dart-define=CAST_DEBUG_PORT=47700
APK=build/app/outputs/flutter-apk/app-profile.apk
adb -s emulator-5554 install -r -d "$APK"   # TV (receiver)
adb -s emulator-5556 install -r -d "$APK"   # phone (sender)
```

## 3. Wire the port bridge

The phone connects to `127.0.0.1:47700`; that must reach the TV's receiver:47700.
```bash
adb -s emulator-5554 forward tcp:47700 tcp:47700   # host:47700 → TV:47700
adb -s emulator-5556 reverse tcp:47700 tcp:47700   # phone:47700 → host:47700
```
Chain: `phone 127.0.0.1:47700 → (reverse) host:47700 → (forward) TV:47700`.
TLS is end-to-end phone↔TV over the forwarded TCP; the sender does TOFU + PIN
proof, so cert pinning still holds.

## 4. Launch the TV app and read the PIN

```bash
adb -s emulator-5554 logcat -c
adb -s emulator-5554 shell monkey -p info.breisner.rensi.iptv -c android.intent.category.LAUNCHER 1
sleep 12
adb -s emulator-5554 logcat -d | grep -aoE 'CAST_RECV_BOUND=[0-9]+ pin=[0-9]+' | tail -1
# → CAST_RECV_BOUND=47700 pin=882440
```
`TvReceiverHost` (the app's home on a TV) auto-starts the receiver, so the app
just needs to be foregrounded. The 6-digit PIN is stable for the life of that app
process.

## 5. Restore the real backup on the phone (both lists + TMDb)

The app's export/restore JSON (`schemaVersion, playlists[], settings, credentials.tmdb`)
lives at `…/uploads/<session>/…-rensiiptvbackup*.json`. Restore it via the app's
own **Settings → Restore backup** (import decrypts creds into secure storage). A
raw DB inject cannot recreate the secure-storage secrets, so use the in-app
import. Push the file first:
```bash
adb -s emulator-5556 push <backup>.json /sdcard/Download/rensi_backup.json
```
(then import from the app UI).

## 6. Drive the cast

Two options:
- **Real app UI** (fullest fidelity): open a VOD on the phone → cast → the bridge
  connects to the TV → enter the PIN → the TV plays.
- **Sender integration test** (`integration_test/cast_bridge_test.dart`, used by
  the QA run): drives the REAL `CastSenderController` across the bridge to the
  live TV app, serving the multitrack clip from the host range server
  (`scratchpad/range_server.py`, path-agnostic so a receiver-built VOD URL
  `…/movie/u/p/123.mp4` resolves). Run on the phone:

```bash
# range server on the host (serves build/qa_vod, path-agnostic → qa_big.mp4)
python3 scratchpad/range_server.py build/qa_vod 8199 &

PIN=$(adb -s emulator-5554 logcat -d | grep -aoE 'pin=[0-9]+' | tail -1 | cut -d= -f2)
flutter test integration_test/cast_bridge_test.dart -d emulator-5556 \
  --dart-define=CAST_DEBUG_HOST=127.0.0.1 --dart-define=CAST_DEBUG_PORT=47700 \
  --dart-define=CAST_PIN=$PIN
```

Screenshot the TV framebuffer at the printed `CAST_MARK_*` hold windows with
`adb -s emulator-5554 exec-out screencap -p > out.png`.

## 7. Tear down

```bash
adb -s emulator-5554 forward --remove tcp:47700
adb -s emulator-5556 reverse --remove tcp:47700
git checkout -- lib/services/cast/tv_receiver_service.dart lib/controllers/cast_sender_controller.dart
```
