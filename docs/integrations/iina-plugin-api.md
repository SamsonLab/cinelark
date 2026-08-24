# Verified IINA Plugin Capabilities

- **Status:** Verified source snapshot
- **Source:** `iina/iina`-compatible source at commit
  `50320a76d5f1ba5eb00afffe06088107aa6c3ba7`
- **Snapshot description:** `v1.4.2-build164-301-g50320a76`
- **Audit date:** 2026-08-20

This is the capability basis for CineLark's thin plugin. It records APIs visible
in the audited source, not a compatibility promise for every released IINA
version. CineLark must declare and test a minimum compatible IINA version before
release.

## 1. Plugin lifecycle and instances

IINA supports a normal per-player entry and an optional global entry.

The global API can create managed `PlayerCore` instances:

```javascript
const playerID = global.createPlayerInstance({
  url: "<opaque-playback-url>",
  label: "cinelark-session",
  disableWindowAnimation: false,
  disableUI: false,
  enablePlugins: false
});
```

Observed options:

| Option | Meaning |
| --- | --- |
| `url` | URL/path opened after creating the player |
| `label` | user label available to the child plugin instance |
| `disableWindowAnimation` | suppress player window animation |
| `disableUI` | disable standard IINA UI |
| `enablePlugins` | load all enabled plugins; otherwise load only this plugin |

CineLark disables unrelated IINA plugins in managed players. This keeps the
playback bridge isolated and prevents third-party code from observing opaque,
tokenized playback URLs.

The returned numeric ID addresses the child through
`global.postMessage(target, name, data)`. A null target broadcasts to all
managed children. Child instances use `global.postMessage(name, data)` to reach
the global controller; both sides register `global.onMessage` handlers.

The API does not expose a dedicated method to destroy one managed player from
the global controller. Plugin cleanup closes and shuts down all instances it
created.

## 2. Playback control

`iina.core` exposes:

```text
open(url)
osd(message)
pause()
resume()
stop()
seek(seconds, exact)
seekTo(seconds)
setSpeed(speed)
getChapters()
playChapter(index)
getHistory()
getRecentDocuments()
getVersion()
```

CineLark needs only URL open, transport, seek, and version checks. History and
recent-document APIs must not be used because tokenized URLs are sensitive.

### Status

Readable `core.status` properties:

```text
paused, idle, position, duration, speed
videoWidth, videoHeight, isNetworkResource
url, title
```

`position` and `duration` are seconds. The bridge must omit `status.url` from
messages and logs because it may contain a token.

### Window

`core.window` can read/control loaded, frame, fullscreen, picture-in-picture,
always-on-top, sidebar, screen, visibility, and miniaturization state. CineLark
initially needs fullscreen state only.

## 3. Tracks

`core.audio`, `core.subtitle`, and `core.video` expose track IDs, current track,
and track lists. Serialized tracks include:

```text
id, title, formattedTitle, lang, codec
isDefault, isForced, isSelected, isExternal
demuxW, demuxH, demuxChannelCount, demuxChannels
demuxSamplerate, demuxFPS
```

Additional controls include audio volume/mute/delay, subtitle ID/secondary ID
and delay, and external track loading. IINA/mpv owns track behavior; the bridge
only lists and selects tracks.

## 4. mpv API

`iina.mpv` exposes:

```text
getFlag(property)
getNumber(property)
getString(property)
getNative(property)
set(property, value)
command(commandName, args)
addHook(name, priority, callback)
```

This is sufficient for properties/events not covered by `core`, including
playlist and end-file behavior. Prefer the narrower `core` API when it provides
the required semantic operation.

### Playlist

The main entry exposes `playlist.list()`, `playlist.add(url, at)`,
`playlist.play`, and next/previous controls. `player.enqueue` retains
`playlist.add(url, -1)` for protocol compatibility. The `-1` must be explicit:
JavaScriptCore maps an omitted integer argument to `0` despite the Swift
implementation's default, which inserts the item before the playing entry.

The current coordinator does not enqueue future episodes. After natural EOF it
sends `player.stop` for the outgoing session followed by a new `player.play`,
matching a second manual in-app play action. The global plugin sends both to the
same managed player ID, and the existing player calls `core.open` to replace its
content. The incoming session cannot emit terminal events before its own
`file-loaded`; remaining callbacks from the outgoing media are ignored. A
replacement acknowledgement timeout reports a bridge error and never creates a
second player window.

The player sets mpv `keep-open=yes` before opening and confirms it again after
`file-loaded`, keeping IINA's normal close-at-end policy from destroying the
window before the next command arrives. URLs are never included in events or
logs.

## 5. Events

`event.on(name, callback)` returns a listener ID removed with
`event.off(name, id)`.

Supported naming forms are:

```text
iina.{event}
mpv.{event}
iina.{property}.changed
mpv.{property}.changed
```

Relevant verified events/properties include:

```text
iina.file-loaded
iina.file-started
iina.window-loaded
iina.window-will-close
mpv.end-file
mpv.eof-reached.changed
mpv.pause.changed
```

Arbitrary mpv property change listeners are registered lazily when using the
`mpv.{property}.changed` form. The bridge can observe position by sampling
`core.status.position`; existing plugin evidence notes that relying only on a
`time-pos` change event is not sufficient in all cases.

Generic `mpv.*` callbacks do not expose mpv's event detail object through the
public JavaScript plugin API. The bridge observes `mpv.eof-reached.changed` and
reads `mpv.getFlag("eof-reached")`, but also polls `core.status.position` and
`core.status.duration` every 500 ms because stock IINA can close without
delivering that callback. A sample within 1 ms of duration is treated as the
final decoded frame and emits natural completion immediately, without a second
timer or delay. `mpv.end-file`, pause-at-completion, and terminal-position
window closure remain idempotent fallback paths; an earlier pause remains
non-terminal.

## 6. Storage and credentials

`utils.keychainWrite(service, name, password)` and
`utils.keychainRead(service, name)` are available. IINA prefixes the Keychain
service with the plugin identifier.

Use Keychain only for bridge pairing material. Provider credentials and tokens
belong to CineLark for Mac and must not be copied into plugin preferences.

`preferences.get/set/sync` is suitable for non-secret configuration.

### IINA Open URL HTTP authentication

Stock IINA 1.4.4 can save HTTP credentials from its Open URL window, but this
is a separate path from the plugin Keychain API. It stores an Internet Password
with service `IINA Saved HTTP Password` and matches the exact URL host and port.
When matched, the window injects the credentials into URL userinfo before
calling `PlayerCore.openURL`.

If that load fails, IINA 1.4.4 copies the credential-bearing URL back into the
visible URL field. Automation and diagnostics can then observe the userinfo, so
this UI flow must not be used for repeatable smoke tests with production
credentials.

Managed-player `core.open` calls do not pass through that window and therefore
do not automatically load those credentials. Passwords.app website entries are
also not interchangeable with IINA's own saved item. Do not put HTTP credentials
in bridge payloads, playlist URLs, plugin preferences, fixtures, or diagnostics.

The UHDNow VOD route was tested with IINA HTTP authentication and no query
token; it did not load. Its provider-issued capability token remains required,
so IINA HTTP credentials are not a substitute for `playbackURL(for:)`.

## 7. Networking

### HTTP

`http.get/post/put/patch/delete/download` return JavaScript promises. Requests
require:

- plugin permission `network-request`
- the target host in `allowedDomains`

This is the preferred connection to the bundled Rust Bridge Helper: the plugin
performs bounded long-poll and event POST requests against a loopback-only local
endpoint. The provider API remains in the native app.

### WebSocket server

`iina.ws` exposes:

```text
createServer({ port })
startServer()
onStateUpdate(handler)
onNewConnection(handler)
onConnectionStateUpdate(handler)
onMessage(handler)
sendText(connectionID, string)
```

The implementation supports incoming text/binary data and ping/pong. Despite
its name, `sendText` passes UTF-8 bytes to a server method that marks the frame
as binary.

Security limitations in the audited implementation:

- TLS is explicitly disabled/TODO.
- `NWListener` is created by port without a loopback interface constraint.
- peer-to-peer networking is enabled.
- no stop-server API is exported to JavaScript.
- the selected bound endpoint/ephemeral port is not exposed.

These limitations are tracked in the bridge specification. The WebSocket server
is not the default CineLark transport and must not be described as
localhost-only.

## 8. Plugin UI

Available surfaces include:

- sidebar WebView
- video overlay WebView
- standalone window
- plugin menu items
- input listeners

The CineLark bridge should avoid duplicating the native library UI. A minimal
status/pairing window or menu item is appropriate; the Mac app owns browsing.

## 9. Permissions relevant to CineLark

Manifest permissions recognized by the audited source include:

```text
network-request
show-osd
show-alert
video-overlay
file-system
```

The plugin should request the minimum set. `network-request` is required for the
preferred outbound HTTP connection to the loopback Rust helper. Stock IINA
1.4.4 also gates `core.open` through `file-system`, including network URLs, so
the bridge must currently declare that permission even though its code never
reads or writes user files. Revisit this permission if IINA separates network
media opening from filesystem access. Allow only loopback hosts; provider
domains must not be listed unless the architecture changes through a reviewed
decision.

IINA HTTP promises resolve on an `NSURLSession` delegate queue, and the global
message hub invokes child listeners synchronously on its caller's queue. Calling
any IINA JavaScript API object—including the next `http` request, Keychain,
managed-player, or `core` APIs—directly from that continuation can trap inside
JavaScriptCore. Every such call after an async boundary must first hop to IINA's
main run loop through its `setTimeout`/`Timer` polyfill.

Stock IINA 1.4.4 does not safely invalidate that polyfill's pending timers when
it hot-reloads a global plugin instance. A callback retained by the replaced
JavaScript context can later call an API whose weak `pluginInstance` is already
nil, causing a process-level trap in `JavascriptAPIHttp.request`. CineLark must
therefore treat plugin installation or update as a restart boundary: fully quit
and reopen IINA before attempting playback. This limitation is independent of
the managed-player playlist and does not apply to a cleanly launched instance.

### Runtime diagnostics

The player and global entries log only lifecycle event names, redacted ID
prefixes, reasons, and routing decisions. Provider URLs, pairing material,
authentication headers, and media metadata are excluded. Swift logs the broker,
launcher, and coordinator boundaries under the `com.samsonlab.cinelark`
subsystem. Stream the combined path while reproducing a problem with:

```sh
scripts/observe_playback_logs.sh
```

## 10. Capability assessment

| Requirement | Current API | Assessment |
| --- | --- | --- |
| Create dedicated player | global managed player | Supported |
| Open opaque capability URL | `core.open` / create option | Supported |
| Reuse Open URL HTTP credential from managed player | none exposed | Gap |
| Native episode continuation | `playlist.add` / mpv advancement | Supported |
| Resume after load | file-loaded + `seekTo` | Supported |
| Pause/seek/stop/state | core/mpv APIs | Supported |
| Audio/subtitle inventory and selection | track sub-APIs | Supported |
| Playback lifecycle telemetry | IINA/mpv events | Supported |
| Secret storage | plugin-scoped Keychain | Supported |
| Rust helper IPC | outbound HTTP API | Supported; long-poll spike required |
| Native app IPC via IINA WebSocket | WebSocket server | Non-default; security unresolved |
| Loopback-only IINA listener | none exposed | Gap avoided by Rust helper |
| TLS WebSocket | none | Gap |
| Stop one WS server / managed player from global API | none exposed | Gap/non-blocking TBD |

## 11. Fork policy

Do not fork IINA for supported playback operations. The preferred Rust helper
uses only existing outbound HTTP and playback APIs. Consider a minimal,
upstreamable IINA change only if the helper/plugin spike proves that one of
these is required:

1. provide a WebSocket client or streaming outbound HTTP primitive;
2. improve outbound-request cancellation/timeouts;
3. bind the existing WebSocket server to loopback only;
4. provide a safer native-app IPC primitive.

Any such patch requires a separate ADR, compatibility tests, and an upstream PR
before CineLark depends on fork-only behavior.
