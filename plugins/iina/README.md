# CineLark IINA Bridge

A minimal provider-neutral IINA plugin that connects outbound to the bundled
CineLark Rust broker. It never receives provider credentials and never logs or
persists playback URLs.

## Responsibilities

- discover the broker only on the reserved loopback port range;
- authenticate requests and envelopes with the Keychain-provisioned bridge key;
- create one managed IINA player and reuse it across replacement/next-episode playback;
- load the user's enabled IINA plugins in that managed player;
- apply resume after `iina.file-loaded`;
- map transport commands to public IINA APIs on IINA's main run loop;
- emit sanitized state, position, track, EOF, and close events.

IINA 1.4.4 resolves HTTP promises on an `NSURLSession` delegate queue, while
its JavaScript API objects are main-run-loop-bound. The plugin uses IINA's timer
polyfill before every subsequent HTTP, Keychain, managed-player, or `core`
operation. IINA also gates `core.open` behind
the `file-system` permission even for network URLs; the bridge requests that
permission but does not read or write user files. Enabled third-party plugins
share IINA's player context and may inspect the opaque playback URL, so they
must be treated as trusted code.

Broker discovery happens before Keychain access, and a successfully read pairing
key is cached only for the lifetime of the IINA process. IINA therefore asks for
Keychain authorization only when CineLark is reachable and does not repeat the
prompt during automatic reconnects. Users can choose **Always Allow** to retain
that explicit authorization across IINA launches.

## Development

```sh
npm test
npm run package
```

The package command writes `dist/CineLark.iinaplgz`. The release archive and
pairing key are installed/provisioned by CineLark; users do not edit plugin
preferences or configure a port.
