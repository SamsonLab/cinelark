# 003 — Keyboard-First Application Navigation: Action Log

## Timeline

| Date | Change | Ref |
| --- | --- | --- |
| 2026-08-24 | Replaced the single directional callback with an ordered navigation-surface stack. | Working tree |
| 2026-08-24 | Moved shortcut lifecycle reconciliation to application activation and termination boundaries. | Working tree |
| 2026-08-24 | Moved the shared navigation legend from the library split view to the application root overlay. | Working tree |
| 2026-08-24 | Added model-backed focus graphs to Home and movie or series details. | Working tree |
| 2026-08-24 | Added directional control to playback sheets, favorite people, person details, and category or favorite filters. | Working tree |
| 2026-08-24 | Unified semantic selection outlines and suppressed stale native-focus presentation while keyboard navigation is active. | Working tree |
| 2026-08-24 | Added last-input-wins pointer and keyboard modalities so hover and semantic selection cannot render together. | Working tree |
| 2026-08-24 | Restricted NSEvent property reads to their valid event families, restoring uninterrupted pointer delivery. | Working tree |
| 2026-08-24 | Added typed pointer-to-keyboard selection handoff while preserving last-input-only presentation. | Working tree |
| 2026-08-24 | Separated physical pointer intent from geometry-driven SwiftUI hover transitions. | Working tree |
| 2026-08-24 | Standardized cross-section navigation to enter every destination at target index zero. | Working tree |
| 2026-08-24 | Replaced fixed section origins with per-section last-valid selection memory after interaction review. | Working tree |
| 2026-08-24 | Kept empty filter surfaces navigable, added Search `Command-F`, focus-safe grid spacing, and selected-filter auto-scrolling. | Working tree |
| 2026-08-24 | Moved poster top-alignment to focus-safe wrapper targets so scaled artwork cannot be clipped. | Working tree |
| 2026-08-24 | Built, tested, and exercised navigation, activation, modal restoration, and lifecycle recovery in the running app. | Working tree |
| 2026-08-24 | Made the Home preview sticky and scroll-responsive, then aligned keyboard scrolling to semantic shelf headings. | Working tree |

## Outcome & current state (as of 2026-08-24)

`ShortcutCoordinator` now retains registered navigation surfaces by owner and
dispatches to the most recently registered visible surface. Updating an existing
surface does not promote it above a presented child. Removing a playback sheet
therefore restores its detail route and selection without re-registering the
parent.

The coordinator installs application activation observers together with its
local event monitor. Resigning active cancels Command-hold state and hides help;
becoming active ensures the monitor exists and starts from a clean modifier
state. `RootView` owns the shared help overlay, while application termination is
the only normal path that stops the coordinator.

Home models hero actions, Continue Watching, popular content, collections, and
View All actions as semantic sections. Left and Right move within a shelf; Up
and Down restore the adjacent shelf's own last valid target. An unvisited or
invalidated shelf starts at its first target. The selected section is top-
aligned and its horizontal content is leading-aligned.

Home now keeps its preview outside the shelves' scrolling lifetime. Vertical
scrolling contracts it to an adaptive compact height, shifts its content upward,
and removes the initial shelf overlap before controls can collide. The backdrop
extends into the detail column's top safe area. Continue Watching owns a heading
anchor, and keyboard scrolling performs a post-collapse alignment pass so every
selected shelf heading remains visible below the sticky preview.

Media details model primary playback, favorite state, movie versions, seasons,
episodes, expansion, and cast. Vertical lists advance item by item and scroll
the selected row to the top. Playback-option sheets temporarily own direction,
Return, Space, Escape, and Backspace. Person details, favorite people, category
filters, and favorite tabs reuse the poster-grid leading-action contract.

Semantic keyboard selection is the only focus treatment rendered after the
custom route becomes active. Native SwiftUI focus remains available for
accessibility and ordinary Tab navigation but is visually suppressed so stale
focus cannot produce a second selected outline. A compact `Confirm` badge makes
the Return or Space action explicit on dynamic content. Parent selection is
temporarily hidden while its playback sheet is presented and restored on
dismissal.

Selection presentation now follows the most recently handled input modality.
Pointer movement, clicks, drags, scrolling, and card hover hide semantic
keyboard presentation without destroying its position. A handled directional,
confirmation, back, or fixed shortcut restores keyboard presentation and
suppresses stale hover state. This keeps mouse and keyboard control mutually
exclusive while allowing either mode to resume naturally.

The local AppKit monitor now dispatches the original `NSEvent` before reading
type-specific properties. Keyboard-only fields are accessed only for keyboard
events, and swipe deltas only for swipe events. Pointer movement therefore no
longer triggers an AppKit assertion before SwiftUI can receive hover input.

Pointer and keyboard targets now retain independent lifecycle state but exchange
semantic context when the active control mode changes. A directional key starts
from the currently hovered target and performs its movement in the same event;
Return or Space activates that target. When pointer input resumes, the control
actually under the cursor becomes active again. The modality still owns visual
presentation exclusively, so the handoff never produces simultaneous outlines.

Input modality is now driven only by actual AppKit pointer events or handled
keyboard commands. SwiftUI hover entry caused by scrolling or relayout can
update hit-test state only after pointer modality is active; it cannot claim
pointer ownership. Hover exit still clears stale pointer targets. A stationary
cursor therefore cannot interrupt a keyboard-driven scroll or replace its
preview selection.

Search retains a fallback directional surface even without results and exposes
`Command-F` for deterministic input recovery. Empty Favorites and category
collections keep their filter actions active, seeded from the currently active
filter. Search and Favorites first rows have additional focus-scale clearance,
and shared horizontal filters scroll their semantic selection into view.

Cross-section state is retained per semantic section rather than derived from
the source column or reset to index zero. Keyboard movement and pointer handoff
both refresh that memory. Model changes remove stale identifiers before the next
transition.

## Validation

- `xcodebuild -project apps/macos/CineLark.xcodeproj -scheme CineLark
  -configuration Debug -destination 'platform=macOS' build
  CODE_SIGNING_ALLOWED=NO` succeeded after the final implementation changes.
- `swift test --package-path packages/apple/CineLarkKit` passed all 36 tests in
  six suites.
- `git diff --check` reported no whitespace errors.
- In a freshly launched build, Home established a selection on the first arrow
  event, moved from Hero to Continue Watching and Popular Now, top-aligned each
  new section, and opened the selected poster with Return.
- A series detail traversed hero actions, season, and episode rows. Episode 2
  displayed the only outline and `Confirm` badge; a stale native focus on
  Episode 5 no longer rendered a second selected state.
- Return on the selected episode opened playback options. Down selected its
  version, Escape dismissed the sheet, and the next Down resumed at Episode 3,
  confirming parent-route restoration.
- `Command-2` opened Movies. Up moved from its poster grid to the collection
  filters, Right selected the adjacent filter, and Return loaded it.
- After activating Finder and returning to CineLark, `Command-1` still returned
  to Home, confirming monitor recovery across application activation.
- A fresh Home launch presented no semantic confirmation badge. Directional
  input restored exactly one semantic outline and one `Confirm` badge while the
  previous pointer position remained unchanged.
- The event-field fix rebuilt successfully, passed all 36 package tests, and
  launched the latest Debug application with directional navigation intact.
- Home retained exactly one visible selection while switching from keyboard to
  pointer input, and subsequent directional input continued through the same
  shelf graph. Code-level validation confirmed the first directional or
  confirmation event reads the current pointer target before changing modality.
- With the pointer parked over Home's poster shelf, three consecutive Right
  commands scrolled the shelf and advanced the `Confirm` selection through
  three cards. Cards moving beneath the stationary pointer did not restore
  hover presentation or interrupt the keyboard route.
- From the third Continue Watching target, Down entered Popular Now. After
  moving within Popular Now, Up restored the same third Continue Watching item,
  confirming independent per-section memory.
- In Favorites, Up and Right selected the empty Movies tab. After activation,
  one Right and Return directly selected and activated the empty People tab,
  confirming that empty surfaces preserve their active leading control.
- Search returned a populated result grid for `奥特曼`; after directional
  navigation, `Command-F` selected the query text and restored input focus.
- In a narrow TV Series window, repeated Right commands scrolled the category
  filter row through its later categories while retaining the selected filter
  in the visible viewport.
- Search and Favorites retained complete top corners and focus strokes on the
  selected poster. Favorites preserved the same clearance after Down scrolled a
  lower row to the viewport top.

## Deviations from plan

The implementation expanded the initial page list to include category and
favorite filters because poster-only directional control left a core browsing
operation dependent on pointer input.

The original plan expected selected controls to reuse the shared focus surface.
Runtime verification exposed that independent native `FocusState` values could
retain a second outline. Presentation now explicitly prioritizes semantic
selection whenever a custom keyboard route is active, while keeping native
focus behavior underneath.

No geometry-based navigation engine was introduced. All routes remain derived
from stable model identities and explicit section order.

The first handoff implementation copied pointer state and expected the movement
closure to observe that write immediately. SwiftUI state transactions can defer
the observable binding update until after the current event. Movement and
activation therefore use the pointer binding as their immediate starting context
and keep the copy callback for retained keyboard state.

The fixed index-zero section-entry rule was also superseded in the same working
tree. It was predictable but imposed repeated traversal cost. Stable section-
local memory now provides deterministic restoration without source-column
coupling.

## Open questions

- The available UI automation API cannot synthesize a physical one-second
  modifier hold, so Command help timing still needs one manual keyboard pass.
- Trackpad swipe-back still requires one manual gesture pass on physical
  hardware.
- The available UI automation API cannot synthesize an arbitrary raw pointer
  hover, so last-input pointer takeover still needs one manual cursor pass.
- Sort menus remain keyboard-accessible through native focus and activation;
  they are intentionally not converted into directional model targets.
