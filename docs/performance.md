# Performance Budgets and Baselines

**Status:** Implemented development baseline

CineLark records privacy-safe local intervals with monotonic time, OSLog, and Points
of Interest signposts. These budgets are regression signals during development; they
are not device-independent release claims or wall-clock CI gates.

## Budgets

| Metric | Target | Critical ceiling | Completion point |
| --- | ---: | ---: | --- |
| `appBootstrap` | 1,500 ms | 4,000 ms | Profile and Source restoration reaches ready |
| `cachedLibraryPage` | 150 ms | 400 ms | A safe cached page is applied to state |
| `refreshedLibraryPage` | 1,500 ms | 5,000 ms | Provider refresh is applied or fails |
| `mediaDetail` | 800 ms | 2,500 ms | Primary detail is applied or fails |
| `playbackFileLoad` | 3,000 ms | 10,000 ms | Matching IINA `fileLoaded` or terminal failure |
| `remoteCommand` | 100 ms | 300 ms | Command executes and its acknowledgement is queued |
| `focusMutation` | 16.67 ms | 33.34 ms | The active semantic surface accepts or rejects a move |

Every completed interval emits only its metric, elapsed milliseconds, bounded rating,
and bounded outcome. Item identifiers, search queries, URLs, credentials, profile
identities, and error descriptions are excluded. Artwork completion is intentionally
not part of semantic content readiness.

## Capture a local baseline

Build the Debug application, then run the capture script with an absolute bundle path:

```bash
xcodegen generate --spec apps/macos/project.yml
xcodebuild \
  -project apps/macos/CineLark.xcodeproj \
  -scheme CineLark \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

scripts/capture_performance_baseline.sh \
  "$PWD/build/DerivedData/Build/Products/Debug/CineLark.app" \
  120
```

During the capture, exercise one stable scenario: wait for Home readiness, open the
same library collection twice, open one media detail, start playback through IINA,
perform directional focus moves, and send a Remote command when a paired client is
available. Avoid changing provider or cache state between comparison runs.

Summarize the resulting NDJSON:

```bash
python3 scripts/summarize_performance_baseline.py \
  build/performance/cinelark-performance-YYYYMMDD-HHMMSS.ndjson
```

Use at least five runs on the same Mac, power mode, display refresh rate, provider,
and cache state. Compare median and P95 independently for successful samples; retain
failure/cancellation counts because a fast failure is not a successful interaction.

For focus, `focusMutation` measures CineLark's semantic UI path. Confirm presented
frame timing with the Instruments **Animation Hitches** and **Points of Interest**
tracks; reducer test timing is not a substitute for visual-frame evidence.

## Interpreting results

- `withinTarget` is the expected development envelope.
- `exceededTarget` is evidence to inspect, especially when P95 regresses repeatedly.
- `exceededCritical` is a severe local sample, not proof that CineLark alone caused a
  provider-bound delay.
- Compare like-for-like outcomes. Do not mix cache hits, refreshes, failures, and
  cancellations into one latency statistic.
- Revise budgets only with a recorded scenario and physical-device sample, not to make
  a regression disappear.
