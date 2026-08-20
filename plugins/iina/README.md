# CineLark IINA Bridge

A minimal provider-neutral IINA plugin that connects outbound to the bundled
CineLark Rust broker. It never receives provider credentials and never logs or
persists playback URLs.

## Responsibilities

- discover the broker only on the reserved loopback port range;
- authenticate requests and envelopes with the Keychain-provisioned bridge key;
- create a managed IINA player for `player.play`;
- apply resume after `iina.file-loaded`;
- map transport commands to public IINA APIs;
- emit sanitized state, position, track, EOF, and close events.

## Development

```sh
npm test
npm run package
```

The package command writes `dist/CineLark.iinaplgz`. The release archive and
pairing key are installed/provisioned by CineLark; users do not edit plugin
preferences or configure a port.
