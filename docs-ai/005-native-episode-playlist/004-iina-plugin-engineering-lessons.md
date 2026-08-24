# 005.004 — IINA Plugin Engineering Lessons

## Context

Native episode continuation crossed four independently asynchronous boundaries:
CineLark provider requests, the authenticated bridge, IINA's global plugin, and
the per-player JavaScript instance backed by mpv. The first implementation was
plausible in unit tests but stopped at natural EOF in stock IINA 1.4.4.

The failure was not one bug. Several mismatches between Swift, JavaScriptCore,
mpv, IINA lifecycle behavior, and the smoke-test environment obscured each
other. This record preserves the resulting engineering invariants for future
IINA plugin work.

The maintained API and security contract remains
[`docs/integrations/iina-plugin-api.md`](../../docs/integrations/iina-plugin-api.md).

## Failure map

| Symptom | Actual cause | Misleading evidence | Permanent rule |
| --- | --- | --- | --- |
| Natural EOF stopped instead of advancing | `playlist.add(url)` inserted at index `0`; the playing item became the last entry | The Node mock treated an omitted index as append | Pass `playlist.add(url, -1)` explicitly and model JavaScriptCore conversion in tests |
| Installed plugin crashed several seconds after update | A timer from the replaced global plugin called an IINA API after its weak native owner was released | The crash happened after the new plugin appeared installed | Treat install/update as a full IINA restart boundary |
| Queue disappeared before future URLs were ready | Four seconds of telemetry silence was treated as definitive player termination | IINA was still visibly playing | Probe with `player.requestState`, then apply a second timeout before finalization |
| Tokenless VOD URL did not load with saved HTTP credentials | UHDNow still required its provider-issued capability token | IINA exposes an HTTP Authentication UI | Keep provider capability URL generation in CineLark; HTTP auth is not a substitute |
| HTTP credential appeared in diagnostics | IINA injected credentials into URL userinfo and copied the failed URL back into the visible field | The password field itself remained masked | Never automate the Open URL authentication UI with production credentials |
| A correct source change seemed ineffective | The smoke test launched an older `/Applications` build | The installed plugin itself was already 0.1.9 | Verify both app binary and plugin versions before runtime diagnosis |

## Engineering invariants

### 1. JavaScript-exported defaults are not JavaScript defaults

IINA 1.4.4 implements playlist insertion in Swift as an exported method with a
default `at = -1`. `JSExport` does not publish the Swift default expression.
When JavaScript omits the integer, JavaScriptCore converts the missing argument
to `0`.

Therefore:

```javascript
playlist.add(url);     // Inserts at index 0 in stock IINA 1.4.4.
playlist.add(url, -1); // Appends after the current playlist tail.
```

Mocks must reproduce the exported runtime contract, including surprising
conversion behavior. A friendlier mock is a liability when the compatibility
edge is the behavior under test.

### 2. Separate player-session identity from playlist-item identity

One managed IINA player owns one stable bridge `sessionID`. Every episode keeps
an independent `playbackID` for progress, resume, completion, and refill logic.

The per-player plugin maps mpv's active playlist entry back to its descriptor by
URL, with playlist index as a fallback. `player.fileLoaded`, position, ended,
and closed events carry the active item `playbackID`; they do not infer item
identity from the stable session ID.

### 3. Provider work must not gate native EOF advancement

CineLark discovers the logical episode order and keeps at most two future
capability URLs in IINA. mpv owns the actual EOF transition. Completion
reporting and provider state propagation occur asynchronously after the old
item ends.

This preserves immediate continuation without resolving an entire season of
short-lived capability URLs in advance.

### 4. All IINA JavaScript API calls require main-run-loop discipline

IINA HTTP promises resolve on an `NSURLSession` delegate queue. The global
message hub invokes child listeners synchronously on the caller's queue. A
continuation must hop through IINA's timer polyfill before calling `http`,
Keychain, global-player, managed-player, or `core` APIs.

The bridge uses `setTimeout(..., 0)` as the documented queue hop around those
calls. This is a native API constraint, not cosmetic scheduling.

### 5. Plugin hot reload is not a safe lifecycle boundary

Stock IINA 1.4.4 can retain timers from the replaced JavaScript context. A
later callback may enter an API object whose weak `pluginInstance` is already
nil and trap in native code.

Plugin installation and update must therefore follow this sequence:

1. Fully quit IINA.
2. Replace or install the plugin payload.
3. Verify `Info.json` and installed source hashes.
4. Launch a clean IINA process.

Do not use hot reload as proof that a packaged global plugin is safe.

### 6. Telemetry silence is not a terminal playback event

The coordinator previously finalized playback after four seconds without a
position or state event. That could cancel queue discovery while media was
still playing.

The watchdog now sends `player.requestState` after the first silence interval.
Only a second interval without a response finalizes the sampled state and
clears the queue. Explicit EOF, window-close, stop, and IINA termination remain
the authoritative terminal signals.

### 7. Open URL credentials and plugin playback are different paths

IINA's Open URL window stores an Internet Password under its own service and
matches the exact host and port. It injects a match into URL userinfo before
opening the media. A managed-player `core.open` call bypasses this window and
does not automatically reuse that credential.

Provider credentials must not be copied into bridge payloads, playlist URLs,
plugin preferences, or fixtures. UHDNow playback continues to use the opaque
capability URL produced by `playbackURL(for:)`.

### 8. Capability URLs must remain opaque and redacted

The same URL is needed internally for playlist identity, but must never appear
in logs or emitted state. Tests may preserve the observed host, path, media IDs,
and query shape while replacing the secret token value with `<redacted>`.

IINA menus and accessibility trees can expose complete playlist URLs. Runtime
inspection must filter URLs before returning diagnostics.

### 9. Version alignment is part of the protocol

The following versions must move together:

- plugin `Info.json`;
- plugin `package.json`;
- global-plugin handshake constant;
- native launcher's minimum installed plugin version;
- installation and packaging tests.

Otherwise an old plugin can pass discovery while retaining incompatible
playlist behavior.

## Five-second real EOF smoke test

The shortest meaningful live test uses real adjacent episodes without waiting
for normal remaining playback time:

1. Fully restart IINA with the packaged plugin.
2. Run the current CineLark build, not a stale installed app.
3. Start a real episode through CineLark so capability URLs are generated by the
   authenticated provider session.
4. Wait until logs show logical queue discovery and two successful enqueues.
5. Confirm the IINA playlist order is current episode, next episode, then the
   following episode.
6. Seek the current episode to `duration - 5 seconds`.
7. Let natural EOF occur; do not invoke `Next Media` manually.
8. Verify the next episode loads with its own playback ID and queue refill adds
   another future item.
9. Confirm the old episode's stopped report completes asynchronously.

The 2026-08-24 smoke run used real adjacent UHDNow episodes. CineLark discovered
nine remaining items and enqueued two within one second. The user confirmed the
five-second natural-EOF continuation in stock IINA 1.4.4.

## Validation checklist for future IINA plugin changes

- Unit harness matches JavaScriptCore argument conversion.
- Playlist append asserts the explicit `-1` index.
- Events contain playback IDs but never source URLs.
- Async IINA API calls hop to the main run loop.
- Plugin package and native minimum versions match.
- Installed source hashes match the package.
- IINA is fully restarted after plugin replacement.
- Current app binary timestamp/path is verified.
- Real fixture contains no credential or capability-token value.
- Live smoke uses natural EOF from `duration - 5 seconds`.

## Current state

Plugin 0.1.9 explicitly appends native playlist entries. CineLark maintains a
two-item rolling future queue, probes silent telemetry before finalization, and
keeps provider capability URL generation outside IINA. The remaining live gap
is a season-boundary EOF transition.
