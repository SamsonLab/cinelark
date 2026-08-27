# CineLark Emby Postman Kit

This kit exercises the Emby v1 surface currently consumed by CineLark. It can
target either the bundled local fixture server or a real Emby-compatible
server, including a reverse-proxy base path.

## Files

- `CineLark-Emby.postman_collection.json` — requests, variable extraction, and
  response assertions.
- `CineLark-Emby-Local-Mock.postman_environment.json` — safe local defaults.
- `CineLark-Emby-Server.postman_environment.json` — empty real-server template.
- `emby_mock_server.py` — dependency-free, loopback-only fixture server.

## Local fixture workflow

Start the server from the repository root:

```bash
python3 tools/postman/emby_mock_server.py
```

Then:

1. Import the collection and `CineLark Emby — Local Mock` environment into
   Postman.
2. Select the local environment.
3. Run `00 Bootstrap` first. Authentication stores `server_id`, `user_id`, and
   `access_token` in the selected environment.
4. Run individual folders or the full collection.
5. Use `99 Local Mock Control / Read Mock State` to inspect mutations and
   `Reset Mock State` to restore deterministic defaults.

The local fixture listens only on `127.0.0.1:8097`. Its credentials are
`mock` / `mock`, and its token is intentionally non-secret.

## Real Emby workflow

Import and duplicate `CineLark Emby — Server Template`, then set:

- `base_url` — the complete Emby API base, for example
  `https://media.example.com/emby` or a reverse-proxy path such as
  `https://example.com/media/emby`.
- `username` and `password` — a test Emby user.
- Optional item variables when the automatic first-item selection does not
  match the desired fixture.

Run `00 Bootstrap`, followed by read-only folders. The `04 User State
Mutations` and `03 Playback Lifecycle` folders change remote user state, so use
a dedicated test account when running them against a real server.

Tokens are stored only in the local Postman environment. Do not commit an
exported environment containing populated credentials or tokens.

## Coverage

| CineLark capability | Requests |
| --- | --- |
| Validation | `System/Info/Public` |
| Authentication | `Users/AuthenticateByName` |
| Collections | `Users/{user}/Views` |
| Browse/search | `Users/{user}/Items` |
| Latest/resume/import | `Items/Latest`, `Items/Resume`, favorite query |
| Detail hierarchy | item, seasons, episodes, person, person works |
| Playback resolution | `Items/{item}/PlaybackInfo` |
| Playback check-ins | Playing, Progress, Stopped |
| Mirror mutations | FavoriteItems and PlayedItems |
| Artwork | Primary and Backdrop image requests |

The fixture is intentionally a contract simulator, not an Emby implementation.
It validates CineLark request/response shapes and deterministic state changes;
it does not stream media, transcode, discover over UDP, or scrape metadata.
