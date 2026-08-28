# TCA Learn

- **TCA baseline:** 1.26.1
- **Scope:** Validated CineLark-specific patterns only
- **Last reviewed:** 2026-08-27

This is a living engineering reference, not a work log or a substitute for the
official TCA documentation. Add an entry only after the pattern is implemented
and supported by a test or a reproducible runtime observation.

## Entry format

Each entry uses a stable `LNNN` identifier and contains:

- **Problem / context**
- **Pattern applied**
- **Why this boundary was chosen**
- **Minimal CineLark example**
- **Test evidence**
- **Reuse rule**
- **Version caveat**

## L001 — Split-view presentation and semantic navigation need different owners

- **Problem / context:** macOS could collapse the sidebar while entering a
  detail route. The detail lifecycle then wrote that presentation change back
  into shared navigation state, so returning changed the collection width and
  grid position.
- **Pattern applied:** `NavigationFeature.State` owns the saved sidebar
  preference and a `StackState<Path.State>`. `LibraryView` owns the responsive
  `NavigationSplitViewVisibility` locally. Only the explicit sidebar command
  sends `sidebarVisibilityChanged`; route push/pop never does.
- **Why this boundary was chosen:** sidebar preference and route identity are
  semantic, cross-page state. A width-driven collapse is transient window
  presentation and must not become a durable preference.
- **Minimal CineLark example:** opening `.media(MediaRouteFeature.State(...))`
  appends to `state.path`; it does not read or mutate
  `state.$sidebarVisible`.
- **Test evidence:** `NavigationFeatureTests.sidebarIsStableAcrossDetailNavigation`
  and `NavigationFeatureTests.selectingSectionClearsPath`.
- **Reuse rule:** if SwiftUI can derive a value from current geometry, keep the
  actual presentation value in the view. Put only user intent that must survive
  page identity changes in feature state.
- **Version caveat:** in TCA 1.26.1, `AppStorageKey` reports dotted keys as an
  issue because they cannot use efficient key-value observation. Use a valid
  key-path identifier such as `cinelarkSidebarVisible`.

## L002 — Wrap actor/plugin lifetimes in a value dependency, not in Store state

- **Problem / context:** plugin registries and account-bound runtimes have
  identity, internal caches, and long lifetimes. Storing them in observable TCA
  state would make equality, serialization, and tests depend on infrastructure.
- **Pattern applied:** `MediaSourcePlatform` and `CoreDataCatalogStore` remain
  actors. `MediaPlatformClient` exposes only `@Sendable` async closures to
  reducers; the composition root captures the live actors and tests replace the
  closures.
- **Why this boundary was chosen:** TCA coordinates when work happens, while
  the actor guarantees transport and persistence isolation. Neither layer
  impersonates the other.
- **Minimal CineLark example:** `SourceFeature` calls
  `mediaPlatform.descriptors()` and receives plain plugin descriptors as an
  internal action. The registry itself is never stored in `State`.
- **Test evidence:** `PluginRegistryTests.registryRejectsDuplicateStablePluginIDs`,
  the 55-test SwiftPM pass, and the macOS application build with live dependency
  composition.
- **Reuse rule:** when a dependency has a lifecycle or owns mutable resources,
  keep that owner below TCA and inject the smallest value-client surface needed
  by the feature.
- **Version caveat:** TCA 1.26.1 `DependencyKey` requires a `liveValue`; the
  composition root may still override that value for process-specific actors.

## L003 — Catalog data is infrastructure; IDs and projections are feature state

- **Problem / context:** a media catalog can contain thousands of records and
  Core Data objects. Copying the full catalog into Store state would inflate
  equality checks and couple reducers to persistence.
- **Pattern applied:** `LibraryFeature.State` stores the active `MediaQuery`,
  ordered `CatalogItemID` values, and a small `ItemSnapshot` dictionary. The
  Core Data catalog performs source isolation, locator normalization, and
  persistence outside TCA.
- **Why this boundary was chosen:** ordering and currently rendered labels are
  observable UI state; managed objects, indexes, and normalization rules are
  repository implementation details.
- **Minimal CineLark example:** a `MediaPage` internal action is projected into
  `itemIDs` plus title/kind/poster snapshots. The page and repository are not
  retained in state.
- **Test evidence:**
  `CoreDataCatalogStoreTests.catalogKeepsSourcesIsolatedAndSupportsMultipleLocators`
  and
  `CoreDataCatalogStoreTests.matchingContentKeysDoNotMergeWithoutExplicitCatalogIdentity`.
- **Reuse rule:** reducers should retain the minimum projection required to
  render and coordinate. Re-query the repository for authoritative records.
- **Version caveat:** `@ObservableState` makes accidental large-state ownership
  easy to observe but does not make it cheap; state-size discipline remains an
  application responsibility.

## L004 — Cached-first is an ordering guarantee, not two concurrent requests

- **Problem / context:** launching cache and source reads with `async let` made
  the UI faster in the best case, but allowed a slow cache result to arrive
  after fresh source data and overwrite it.
- **Pattern applied:** one cancellable `LibraryFeature` effect awaits and sends
  the cache projection first, checks cancellation, and only then starts the
  source refresh. Both responses also carry the full `MediaQuery` and are
  ignored when it no longer matches state.
- **Why this boundary was chosen:** “cached-first” is observable product
  semantics. It must be encoded by effect order, while query identity protects
  against late actions at the reducer boundary.
- **Minimal CineLark example:** `.view(.load(query))` returns an effect that
  sends `cachedPageLoaded(query, ...)` before
  `refreshedPageLoaded(query, ...)`, with `CancelID.query` using
  `cancelInFlight: true`.
- **Test evidence:** `LibraryFeatureTests.cachedFirstOrdering` asserts the exact
  `TestStore` receive order and final fresh projection.
- **Reuse rule:** if one result is allowed to replace another, make that order
  explicit. Use concurrency only for results that commute or have a revision
  policy that prevents older data from winning.
- **Version caveat:** TCA cancellation prevents future effect sends, but already
  delivered actions still need a query/revision guard in the reducer.

## L005 — Latest-wins needs cancellation and response identity

- **Problem / context:** a user can change search text or source while a
  provider ignores cooperative cancellation. Cancellation alone cannot prevent
  an already-produced result from reaching the reducer.
- **Pattern applied:** `SearchFeature` uses one feature-scoped cancellation ID,
  `cancelInFlight: true`, normalized search text, and a response action carrying
  both the term and full `MediaQuery`. The reducer accepts the response only if
  term and source still match state. Playback resolution additionally carries
  a generated request ID because two requests can target the same locator.
- **Why this boundary was chosen:** dependencies should cooperate with Swift
  cancellation, but the reducer is the final authority for whether an external
  result still belongs to current semantic state.
- **Minimal CineLark example:** `.queryChanged("latest")` replaces the pending
  debounce. `.response(term: "first", query: oldQuery, ...)` is ignored even if
  the old client returns after cancellation.
- **Test evidence:** `SearchFeatureTests.latestWins` uses `TestClock` and proves
  that only the latest term reaches the dependency. `PlaybackFeature` tests the
  request-scoped lifecycle used by descriptor resolution.
- **Reuse rule:** every replaceable effect needs both a cancellation identity
  and a semantic response identity. Treat cancellation as resource control,
  not as the sole correctness mechanism.
- **Version caveat:** TCA 1.26.1 cancellation IDs are reducer-local only by
  convention; use private feature-scoped IDs to avoid accidental collisions.

## L006 — TestClock turns retry policy into reducer behavior

- **Problem / context:** outbound Emby mirroring must retry without blocking
  local favorite/playback writes, and real sleeps would make reducer tests slow
  and nondeterministic.
- **Pattern applied:** the Profile reducer persists the failed queue entry with
  its next attempt, returns a value outcome, and schedules only the next
  `processMirrorQueue` action through the injected continuous clock. The queue
  and attempt count remain repository-owned.
- **Why this boundary was chosen:** the reducer owns retry orchestration and UI
  observability; the repository owns durable delivery state; the source plugin
  owns the remote command.
- **Minimal CineLark example:** attempt zero produces a two-second retry delay.
  Advancing `TestClock` by two seconds delivers the next processing action
  without waiting for wall time.
- **Test evidence:** `ProfileFeatureTests.mirrorRetry` verifies rescheduling,
  attempt increment, next-at calculation, and clock-controlled retry.
- **Reuse rule:** return a small outcome from worker effects and let the reducer
  schedule the next intent. Do not hide retry sleeps inside repository or
  transport actors when product state must coordinate them.
- **Version caveat:** a clock sleep is still a long-lived effect; assign a
  cancellation ID and replace it when queue context changes.

## L007 — Persisted context restoration is a two-phase bootstrap

- **Problem / context:** Profile selection can load before account-bound source
  runtimes are installed. Applying the selection immediately makes Library and
  Search query a source that the plugin platform cannot resolve.
- **Pattern applied:** `AppFeature` temporarily owns
  `pendingBootstrapSelection`. Profile loading triggers source restoration;
  only `sourcesRestored` projects the saved Profile/Source context into
  Navigation, Library, Search, and Playback.
- **Why this boundary was chosen:** bootstrap ordering is cross-feature
  application state. Neither Profile nor Source should directly mutate sibling
  state or know which consumers require the context.
- **Minimal CineLark example:** `.profile(.internal(.loaded))` stores the
  selection and sends `restoreSources`; `.source(.internal(.sourcesRestored))`
  clears the pending value and fans out scoped context actions.
- **Test evidence:** `AppFeatureTests.bootstrapAppliesContextAfterSourceRestore`
  verifies all four consumers receive the persisted IDs only after restoration.
- **Reuse rule:** when one dependency-backed feature must prepare resources for
  another, model the readiness boundary explicitly in the parent and coordinate
  through child output/internal actions.
- **Version caveat:** merged `.send` effects may arrive in any order. Consumers
  must not depend on sibling action ordering after the readiness boundary.

## L008 — Remove legacy ownership in the same vertical slice

- **Problem / context:** retaining both TCA state and an observable model during
  migration creates unclear write authority and makes back-navigation,
  favorites, and playback drift possible.
- **Pattern applied:** each feature migration moved the dependency call, state,
  and view binding together. Once Catalog-backed reducers rendered the path,
  the corresponding observable model and duplicate view were deleted.
- **Why this boundary was chosen:** a temporary dependency adapter is safe; two
  mutable UI sources of truth are not. Deleting ownership also makes repository
  searches an effective architectural regression check.
- **Minimal CineLark example:** `CatalogMediaDetailView` sends
  `MediaDetailFeature.Action`; it does not construct `MediaDetailModel` or call
  `MediaLibraryProvider` in a view task.
- **Test evidence:** the complete macOS test target passes after model/view
  deletion, the unsigned app builds, and repository search finds no legacy
  provider/model reference under macOS Sources or Tests.
- **Reuse rule:** migration completion requires deletion of the old state owner,
  not merely addition of a reducer. Infrastructure services may remain, but
  they must expose snapshots/actions rather than compete as UI state.
- **Version caveat:** Observation and TCA can coexist for local adapters in TCA
  1.26.1, so compiler success cannot detect accidental dual ownership; enforce
  the rule through feature boundaries and code search.

## L009 — Local-first means replacing remote user data at projection time

- **Problem / context:** media-source DTOs can include favorite and playback
  fields. Persisting local Profile state is insufficient if Catalog or detail
  views can still render those provider fields as a fallback.
- **Pattern applied:** `ProfileClient` returns a value snapshot keyed by
  `ProfileMediaKey`. `LibraryFeature` builds Favorites and Continue Watching
  from that snapshot and replaces `MediaSummary.userState` while ingesting
  Catalog pages. Detail and episode projections apply the same rule; search and
  person results clear remote user state until their destination loads Profile
  state.
- **Why this boundary was chosen:** provider user data remains useful only for
  the explicit import workflow. Feature projection is the last safe boundary
  before rendering and has the active Profile identity required to choose the
  correct state.
- **Minimal CineLark example:** a provider page may report `played = true`, but
  a local Profile state with 25 seconds progress is projected as unplayed at
  25% and becomes the sole Continue Watching entry.
- **Test evidence:**
  `LibraryFeatureTests.localProfileStateIsAuthoritative` sends contradictory
  provider and Profile values and verifies Catalog, Favorites, and Resume all
  render the local value.
- **Reuse rule:** when local-first is a product invariant, never use remote state
  as an implicit fallback. Import it explicitly into the local model or render
  the local default.
- **Version caveat:** TCA cannot prevent domain values from carrying provider
  state. Sanitize or replace it at every feature projection boundary and keep a
  regression test with intentionally conflicting inputs.

## L010 — CloudKit notifications become invalidation actions, not payload state

- **Problem / context:** `NSPersistentStoreRemoteChange` does not identify a
  ready-to-render Profile projection, and passing managed objects or persistent
  history transactions into TCA would couple reducers to Core Data.
- **Pattern applied:** the repository converts remote notifications to a
  coalesced `.external` change value. `ProfileFeature` turns it into an internal
  action and reloads repository values; `AppFeature` separately invalidates the
  active Library projection.
- **Why this boundary was chosen:** Core Data owns change observation and
  merging, while TCA owns which visible features must refresh. The action is an
  invalidation signal, not a second data transport.
- **Minimal CineLark example:**
  `.profile(.internal(.repositoryChanged(.external)))` schedules
  `.library(.view(.loadOverview))`; the next Profile snapshot supplies the
  active local favorite/playback values.
- **Test evidence:**
  `AppFeatureTests.externalProfileChangeRefreshesLibrary` verifies the parent
  invalidation path. Profile repository tests verify deterministic conflict
  resolution for the values reloaded after that signal.
- **Reuse rule:** translate infrastructure notifications into small domain
  invalidations and re-query the repository. Do not place managed objects,
  notification instances, or CloudKit records in feature state or actions.
- **Version caveat:** `NSPersistentStoreRemoteChange` is coalesced and may cover
  multiple entities. Reducers must tolerate redundant reloads and must not infer
  exact changed rows from one notification.

## L011 — AsyncSequence ownership includes replacement and termination

- **Problem / context:** Remote gateway snapshots live for the application
  lifetime. Re-entering bootstrap or recreating the subscription without
  cancellation can leave multiple consumers projecting the same coordinator.
- **Pattern applied:** `RemoteClient` exposes a bounded snapshot
  `AsyncStream`; `RemoteFeature` iterates it in one effect with a private
  cancellation ID and `cancelInFlight: true`. The live stream cancels its
  Observation task from `continuation.onTermination`.
- **Why this boundary was chosen:** the coordinator owns transport lifetime and
  replay policy; the reducer owns whether this feature currently consumes the
  stream and how each value becomes observable state.
- **Minimal CineLark example:** a second `.appAppeared` replaces the first
  snapshot effect. Terminating that effect terminates the first stream before
  the second consumer begins projecting values.
- **Test evidence:** `RemoteFeatureTests.replacesSnapshotSubscription` starts a
  non-terminating first stream, replaces it, and verifies exactly one
  termination callback and two subscription attempts.
- **Reuse rule:** every feature-owned `AsyncSequence` loop needs an explicit
  cancellation ID, a documented buffer/replay policy in its dependency, and a
  termination path that releases the underlying observer or task.
- **Version caveat:** canceling a TCA effect only releases upstream resources if
  the sequence and its continuation propagate termination correctly; test the
  dependency adapter, not just reducer state.

## L012 — Destructive dependency work needs a preflight delegate boundary

- **Problem / context:** clearing the Catalog directly could race with active
  Library or Search effects. A source response that completed just after the
  purge would immediately repopulate data the user had explicitly cleared.
- **Pattern applied:** `CacheFeature` sends `.delegate(.willClear)` before it
  calls `CacheClient.clearAll()`. `AppFeature` converts that child output into
  Library/Search cancellation actions and a Navigation path reset. Only after
  the delegate action is processed does the concatenated clear effect begin.
- **Why this boundary was chosen:** the cache dependency owns deletion, but it
  cannot see or cancel feature-scoped effects. The parent reducer is the first
  layer that owns the coordination relationship without exposing sibling state
  to the child.
- **Minimal CineLark example:** `.clearConfirmed` concatenates usage
  cancellation, `.delegate(.willClear)`, and the async clear command. Success
  then emits `.delegate(.didClear)` before refreshing reported usage.
- **Test evidence:** `CacheFeatureTests.clearAndReload` verifies the exact
  pre-clear delegate, clear completion, post-clear delegate, and refreshed
  usage order. The full macOS suite passes with the parent fan-out composed.
- **Reuse rule:** when a destructive command invalidates work owned by sibling
  features, emit a preflight delegate and let the nearest common parent cancel
  or dismiss those writers before invoking infrastructure. A post-completion
  notification alone is too late.
- **Version caveat:** in TCA 1.26.1, use `.concatenate` for this causal boundary;
  `.merge` does not guarantee that the parent processes preflight output before
  the destructive effect starts.

## L013 — A system-owned Settings scene is not application presentation state

- **Problem / context:** Profiles/Sources and Remote were each presented by a
  main-window toolbar button and local sheet state, while
  `AppFeature.showsSourceManager` duplicated one presentation in TCA. Adding
  more configuration would keep expanding both the browsing shell and root
  presentation state.
- **Pattern applied:** the macOS `Settings` scene owns whether its window is
  visible. `CineLarkSettingsView` composes existing Profile, Source, Remote, and
  Cache scoped stores without adding a settings reducer. Only semantic state
  that survives the window boundary—active selection and the pending
  stop-playback decision—remains in `AppFeature`.
- **Why this boundary was chosen:** opening a system preferences window is
  transient platform presentation. Profile/Source selection changes application
  context and playback, so it remains reducer-owned regardless of which window
  initiated it.
- **Minimal CineLark example:** `SettingsLink` opens the system scene directly;
  selecting a Source still sends `ProfileFeature.view.selectSource`, and a live
  playback session projects `pendingSelection` into the Settings confirmation
  alert.
- **Test evidence:** the full macOS suite passes after removing
  `showsSourceManager` and its actions. Repository checks confirm no duplicate
  source-manager/Remote sheet state or `LanguageMenu` presentation remains.
- **Reuse rule:** do not mirror platform-owned scene visibility in TCA unless
  reducers must coordinate that visibility as business behavior. Compose the
  same scoped stores in another scene and retain only cross-scene semantic
  decisions in application state.
- **Version caveat:** a future requirement to deep-link to a specific Settings
  category may justify a small scene-selection value. It still should not make
  `AppFeature` the owner of whether the system Settings window exists.

## L014 — Application readiness is a semantic parent-owned barrier

- **Problem / context:** the first root implementation sent
  `bootstrapCompleted` from `appeared`, so Library could render before CloudKit
  had resolved the active Profile or Source runtimes had been restored. Elapsed
  lifecycle time was being treated as business readiness.
- **Pattern applied:** `ProfileFeature.State` retains the value-typed
  `ProfileBootstrapResolution`. `AppFeature` maps `waitingForCloud` and
  `requiresChoice` to distinct root resolution surfaces, and routes
  `localOnly`/`synchronize` through Source restoration. `sourcesRestored` is the
  sole transition to `BootstrapState.ready`.
- **Why this boundary was chosen:** Profile owns its resolution state and Source
  owns runtime installation. Only the parent owns the fact that both are
  prerequisites for the application shell, so neither child mutates sibling
  state or declares the whole app ready.
- **Minimal CineLark example:** receiving
  `.profile(.internal(.loaded(.requiresChoice(...))))` changes root bootstrap to
  `.resolvingProfile` without applying Library context. After a resolution
  action reloads `.synchronize`, the parent restores sources and then fans out
  the selected context.
- **Test evidence:**
  `AppFeatureTests.bootstrapWaitsForProfileResolution` proves unresolved Profile
  state cannot reveal Library, while
  `AppFeatureTests.bootstrapAppliesContextAfterSourceRestore` proves Source
  restoration is the final readiness transition.
- **Reuse rule:** model readiness as the conjunction of named semantic
  prerequisites in their nearest common parent. Never use a lifecycle callback
  or an arbitrary delay as proof that dependency-backed bootstrap completed.
- **Version caveat:** TCA 1.26.1 scopes child reducers after the parent reducer;
  the parent may coordinate on the same child action, but tests should assert
  the resulting parent barrier and child state together when exact ordering is
  relevant.

## L015 — A dependency change stream must not cancel the write that triggered it

- **Problem / context:** Profile bootstrap writes a provisional Profile,
  selection, promotion, or merge through the repository. Those writes emit the
  same `AsyncStream` invalidations consumed by `ProfileFeature`. Immediately
  starting a latest-wins reload would cancel the still-running bootstrap effect
  that caused the invalidation; merge could complete before selection and then
  the competing reload could create a replacement provisional Profile.
- **Pattern applied:** while `isLoading` is true, repository invalidations set
  `needsReloadAfterCurrentLoad` instead of launching another load. The terminal
  loaded action clears that flag and starts exactly one follow-up reload. The
  existing feature-scoped cancellation ID still handles independent user reloads.
- **Why this boundary was chosen:** the repository correctly reports all
  changes without knowing which consumer caused them. The reducer owns effect
  intent and is therefore the right place to distinguish an invalidation from
  permission to replace the in-flight transaction orchestration.
- **Minimal CineLark example:** `.repositoryChanged(.profiles)` received during
  `resolveProfile(.mergeIntoCloud(...))` records a deferred reload. Only after
  `.loaded(.success(...))` completes the selection transaction does one new
  `profiles.load()` begin.
- **Test evidence:**
  `ProfileFeatureTests.repositoryInvalidationDefersReload` verifies that an
  invalidation during load emits no competing effect and produces one reload
  after the terminal response.
- **Reuse rule:** if a dependency stream echoes mutations initiated by the same
  feature, do not blindly apply `cancelInFlight` to every echo. Coalesce echoes
  behind the active command, or tag revisions/origins when concurrent refresh
  semantics require more precision.
- **Version caveat:** TCA cancellation is doing exactly what it promises here;
  changing cancellation IDs only hides the race and can allow two loads to
  mutate state concurrently. The reducer needs an explicit coalescing policy.

## L016 — Persist one semantic lifecycle edge as one domain write bundle

- **Problem / context:** a playback edge updates the Resume projection, media
  snapshot, viewing-session aggregate, device activity, and one immutable
  event. Separate dependency calls could partially persist or let provider
  reporting race ahead of CineLark's local viewing memory.
- **Pattern applied:** `PlaybackFeature` owns lightweight active-session
  accounting and converts each started/checkpoint/pause/resume/stop/completion
  edge into one value-typed `ProfilePlaybackWrite`. `ProfileClient` stamps the
  bundle once, and the repository saves every local component in one Core Data
  transaction before the effect attempts provider reporting.
- **Why this boundary was chosen:** the reducer knows the semantic lifecycle
  edge, the dependency client owns mutation authorship, the repository owns
  atomic persistence, and the media plugin owns only the independent remote
  protocol command. None of those responsibilities belongs in Store state.
- **Minimal CineLark example:** `.progressTick` accepts only a positive player
  position delta of at most 30 seconds, updates the active session projection,
  persists a `.checkpoint` write bundle, and then sends Emby Progress.
- **Test evidence:** `PlaybackFeatureTests.lifecycleReporting` verifies the
  started/checkpoint/completed sequence and local-first session projection.
  `PlaybackFeatureTests.pauseAwareWatchAccounting` proves paused movement and
  large seeks do not increase watched seconds. Repository tests prove atomic
  facts remain idempotent through updates, promotion, and merge.
- **Reuse rule:** when one user intent creates several durable projections of
  the same fact, inject one domain write value and let the repository define
  the transaction. Keep transport reporting as a subsequent, independently
  recoverable effect.
- **Version caveat:** effect ordering in TCA 1.26.1 is causal only inside the
  same `.run` operation with explicit `await`. Separate merged effects do not
  establish local-before-remote ordering.

## L017 — Keep rebuildable fact volume below TCA state

- **Problem / context:** viewing insights need all durable sessions plus related
  metadata, but putting those repository rows in Store state would duplicate
  ownership, increase observation/equality cost, and expose calendar-dependent
  derivation to SwiftUI.
- **Pattern applied:** `InsightsClient` accepts explicit Profile, period, and
  reference-date query identity. A pure service loads repository facts and
  returns one compact `ViewingInsightsSnapshot`; `InsightsFeature` stores only
  that snapshot and loading/query state. Each response carries request, Profile,
  and period identity in addition to feature-scoped cancellation.
- **Why this boundary was chosen:** the repository owns fact volume, the pure
  projector owns calendar and ranking semantics, TCA owns latest-wins effect
  orchestration, and SwiftUI owns only presentation. No layer needs a second
  mutable copy of sessions.
- **Minimal CineLark example:** selecting `.quarter` cancels the current Insights
  load. A late `.month` result is ignored unless its request ID, Profile ID, and
  period all still match state.
- **Test evidence:** `ViewingInsightsProjectorTests` verifies deterministic
  time-zone-aware ranges and compact rankings. `InsightsFeatureTests` verifies
  initial load, period/Profile replacement, and stale-response rejection.
  `AppFeatureTests.externalProfileChangeRefreshesLibrary` verifies that a
  repository invalidation refreshes the visible projection.
- **Reuse rule:** when UI needs a rebuildable summary over potentially large
  durable facts, inject a query-shaped dependency that returns a compact value.
  Combine cancellation with semantic response identity whenever context can
  change before an effect finishes.
- **Version caveat:** in TCA 1.26.1, `cancelInFlight` prevents cooperative old
  effects from continuing, but it does not prove that an external dependency
  stopped work or that a response cannot arrive. Reducer guards remain the
  correctness boundary.

## L018 — Model legacy dependency identity as recoverable feature state

- **Problem / context:** a retired media-source plugin ID can still exist in
  local persistence, but silently coercing its URL and credentials into a new
  runtime risks data loss, invalid authentication, and invisible bootstrap
  failure.
- **TCA pattern applied:** the pure plugin layer returns a value-typed
  `SourceMigrationProposal`. `SourceFeature` converts it into semantic
  `migrationProposals` state, presents an explicit reconnect intent, and runs
  standard validation/authentication through dependency clients. The old
  persisted row remains authoritative until the replacement save succeeds.
- **Why this boundary was chosen:** the plugin registry knows identity
  compatibility, the reducer owns user-visible recovery state and effect
  sequencing, and the repository owns atomic replacement. Neither the registry
  nor bootstrap code is allowed to infer user consent.
- **Minimal CineLark example:** a persisted
  `com.samsonlab.cinelark.uhdnow` source becomes **Reconnect as Emby**. The setup
  reuses its `SourceID`, treats the stripped `/api/v1` URL only as an editable
  suggestion, and removes the old Keychain session only after the canonical
  Emby configuration is saved.
- **Test evidence:** `SourceFeatureTests` verifies proposal restoration without
  runtime installation, preserved identity and post-save cleanup on success,
  and retention of the legacy source after failed validation. Registry and Emby
  package tests verify unique alias ownership and pure proposal construction.
- **Reuse rule:** when persisted dependency identity outlives its implementation,
  represent recovery as explicit feature state. Preserve the durable record
  until a verified replacement transaction completes; cleanup follows the
  commit and must not be the transaction's authority.
- **Version caveat:** TCA 1.26.1 gives the reducer deterministic action/effect
  ordering, but it cannot make two external stores atomic. Keep cleanup
  idempotent and order repository persistence before best-effort secret removal.

## L019 — Child delegates must carry leaf semantic identity

- **Problem / context:** `MediaDetailFeature` displays a series route and emits
  playback delegates for selected episodes. The first implementation inherited
  the surrounding series kind, so Profile playback facts could classify the
  exact episode locator as a series even though the domain supported episodes.
- **TCA pattern applied:** the child action that owns the selected leaf constructs
  a complete delegate payload with the episode locator and `.episode` kind. The
  parent coordinates playback without re-deriving identity from route context.
- **Why this boundary was chosen:** the detail child knows which hierarchy item
  the user selected, while the parent owns cross-feature orchestration. Moving
  identity inference downstream would couple Playback and Profile to navigation
  shape and permit the locator and kind to disagree.
- **Minimal CineLark example:** `.view(.episodeSelected(episode))` emits
  `.delegate(.play(locator: episodeLocator, kind: .episode, ...))` even though
  the feature's root item is a series.
- **Test evidence:** `MediaDetailFeatureTests.episodePlaybackIdentity` asserts
  the exact delegate payload, including leaf locator, episode kind, and Profile
  metadata. The full unsigned macOS test command passes with the correction.
- **Reuse rule:** when a child selection crosses a feature boundary, send the
  exact semantic identity of the selected leaf. Never make a parent or sibling
  infer it from the route, collection, or container that presented the child.
- **Version caveat:** TCA 1.26.1 enum actions guarantee payload shape, not
  semantic agreement between fields. Use `TestStore` to assert the complete
  delegate payload for heterogeneous hierarchies.

## L020 — Credential-bearing presentation resources stay below Store state

- **Problem / context:** Emby artwork needs an account authorization header,
  but list/detail/Insights state must remain value-typed and safe to inspect,
  persist, diff, or log. Resolving an `ArtworkDescriptor` in a reducer would put
  a token-bearing value in presentation state and perform work even on cache
  hits.
- **TCA pattern applied:** Feature state keeps only semantic identity—the media
  locator, artwork kind, and secret-free fallback URL. A value-typed dependency
  client is injected at the composition root, and Kingfisher invokes it inside
  an async request modifier only when transport is required. No View `.task`
  or reducer action carries the descriptor.
- **Why this boundary was chosen:** TCA owns observable business state and
  effect orchestration; the image pipeline owns cache lookup and network request
  construction. The latter is the first layer that knows whether authorization
  is needed and can keep it ephemeral.
- **Minimal CineLark example:** `ViewingInsightTitle` retains an optional
  `MediaLocatorID`, while `ArtworkRequestModifier` resolves the account-bound
  descriptor after a cache miss and attaches headers to one request.
- **Test evidence:** `ArtworkRequestTests` verifies ephemeral header injection,
  unsafe URL/origin rejection, and credential-free cache identity.
  `platformRoutesArtworkThroughTheAccountBoundRuntime` verifies capability
  routing, and the full unsigned macOS suite passes with authenticated artwork
  enabled across Library, Detail, and Insights.
- **Reuse rule:** Store only the stable identity needed to reacquire a protected
  presentation resource. Resolve credentials at the narrowest transport
  boundary and never return them through an Action or store them in Feature
  state merely to drive a View.
- **Version caveat:** TCA 1.26.1 dependency clients do not automatically prevent
  sensitive return values from entering State. The boundary depends on the
  client being consumed by transport infrastructure instead of a reducer.

## L021 — Recovery paths must re-enter the original readiness barrier

- **Problem / context:** a pending initial CloudKit import is not ordinary
  loading. Users need to continue with a provisional local Profile, but letting
  that button set the application directly to ready would bypass account-bound
  Source restoration and create a second bootstrap path.
- **TCA pattern applied:** `ProfileFeature` persists the provisional selection
  and emits its existing `selectionChanged` delegate. While
  `AppFeature.BootstrapState` is `.waitingForCloud`, the parent routes that
  delegate back through `SourceFeature.restoreSources`; only
  `sourcesRestored` transitions to `.ready` and applies context.
- **Why this boundary was chosen:** the child owns the local-first selection,
  Source owns runtime installation, and the parent owns their conjunction. The
  recovery intent changes which prerequisite is acceptable, not who owns
  readiness.
- **Minimal CineLark example:** **Continue Offline** selects the Local-store
  `ProfileID`. It does not publish the Profile or reveal Library immediately;
  the same Source-restoration response used by normal bootstrap completes the
  transition.
- **Test evidence:**
  `ProfileFeatureTests.continueOffline` verifies the provisional selection and
  delegate. `AppFeatureTests.bootstrapWaitsForCloudWithRecovery` verifies that
  Library stays hidden before the choice, then becomes ready only after the
  emitted actions traverse Source restoration.
- **Reuse rule:** a recovery or degraded-mode action may relax a prerequisite,
  but it must re-enter the same parent-owned completion barrier as the primary
  path. Do not add a second action that directly marks the application ready.
- **Version caveat:** TCA 1.26.1 processes the parent reducer before scoped child
  reducers for an incoming action, while child effects emit later actions.
  Assert the completed action chain rather than relying on incidental same-pass
  mutation ordering.
