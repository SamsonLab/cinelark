# CineLark Remote

CineLark Remote is the focused iOS/Android couch controller for CineLark on
Mac. It does not access media providers or play media locally.

## Features

- QR pairing over certificate-pinned local WSS with explicit Mac approval
- named multi-Mac selection with device credentials in iOS Keychain or Android
  Keystore-backed storage
- reconnect and revocation recovery
- remote Mac login with username, password, and optional verification code
- semantic section, direction, select, and back navigation
- revisioned search text entry and commit
- IINA transport, scrub, speed, volume, fullscreen, episode, audio, subtitle,
  and close-player controls through the authoritative Mac coordinator

The wire contract lives in
[`docs/interfaces/remote-protocol.md`](../../docs/interfaces/remote-protocol.md).

## Development

```sh
fvm flutter analyze
fvm flutter test
fvm flutter build ios --simulator --no-codesign
fvm flutter build apk --debug
```

The phone and Mac must be on the same local network. Open **Remote** in the Mac
app, scan the displayed code, and approve the phone on the Mac. Android routes
the Remote WSS socket over the active Wi-Fi network directly, including while a
device-wide VPN is enabled.

## Physical-device release smoke

Run this matrix on both a real iPhone and Android phone against a signed Mac
build before release:

1. Deny camera and local-network access once, restore permission, then pair by
   scanning a fresh code and approving the exact device shown on the Mac.
2. Submit valid, invalid, and verification-code login flows; confirm passwords
   are not restored after backgrounding or relaunching the phone.
3. Exercise every section, direction, select, back, search update, search
   commit, and search cancel operation from signed-out through playback.
4. Exercise pause/resume, relative seek, scrub, rate, volume/mute, fullscreen,
   previous/next, every audio/subtitle option, subtitle disable, and close plus
   CineLark activation in a stock compatible IINA installation.
5. Background and resume the phone, sleep and wake the Mac, and change Wi-Fi;
   verify reconnect or an explicit recoverable disconnected state.
6. Revoke the connected phone on the Mac and verify that it immediately loses
   control, removes only that Mac credential, and returns to device selection.
7. On Android, enable a device-wide VPN that captures all app UIDs and verify
   that pairing and reconnect still reach the Mac over the Wi-Fi network.
