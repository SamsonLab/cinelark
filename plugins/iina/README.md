# CineLark IINA Bridge

A minimal provider-neutral IINA plugin that connects outbound to the bundled
CineLark Rust broker. It never receives provider credentials and never logs or
persists playback URLs.

## Responsibilities

- discover the broker only on the reserved loopback port range;
- authenticate requests and envelopes with the Keychain-provisioned bridge key;
- create a managed IINA player for `player.play`;
- apply resume after `iina.file-loaded`;
- map transport commands to public IINA APIs on IINA's main run loop;
- emit sanitized state, position, track, EOF, and close events.

IINA 1.4.4 resolves HTTP promises on an `NSURLSession` delegate queue, while
managed-player and `core.open` calls must run on the main run loop. The plugin
uses IINA's timer polyfill for this queue hop. IINA also gates `core.open` behind
the `file-system` permission even for network URLs; the bridge requests that
permission but does not read or write user files.

## Development

```sh
npm test
npm run package
```

The package command writes `dist/CineLark.iinaplgz`. The release archive and
pairing key are installed/provisioned by CineLark; users do not edit plugin
preferences or configure a port.
