# CineLark TV Experience System

- **Status:** Accepted
- **Platform:** macOS 26+
- **Reference lane:** Apple TV-inspired, CineLark-owned
- **Design method:** Design-first, system-locked iteration

## 1. Goal

Create a cinematic, TV-first media library that is comfortable from a couch and
remains precise with a Mac keyboard, trackpad, or mouse.

Success means:

- Content, not chrome, owns the visual hierarchy.
- Every primary action is reachable through deterministic directional movement.
- Focus is unmistakable at television distance and never jumps after loading.
- Home answers “what should I watch?” before exposing library taxonomy.
- Returning from detail restores the prior item, shelf, and scroll position.
- Reduced Motion, keyboard access, pointer interaction, and VoiceOver remain
  first-class behaviors.

## 2. Format

- **Minimum window:** 960 × 640 points
- **Default window:** 1440 × 900 points
- **Primary composition:** 16:10 desktop, adaptive through 16:9 fullscreen
- **Content safe margins:** 40 points compact, 56 points regular
- **Shelf edge behavior:** Keep the next card partially visible to communicate
  horizontal continuation.

## 3. Layout

### 3.1 App shell

- Replace the permanently consuming split-view sidebar with a floating,
  translucent navigation panel over the content plane.
- Keep only Home, Movies, TV Series, Favorites, and Search at the top level.
- Move provider collections into Movies and TV Series instead of presenting an
  unbounded top-level navigation list.
- Keep account, language, refresh, and sign-out actions in a compact utility
  group at the bottom.
- The panel expands for navigation and collapses to a compact rail when content
  regains focus. Opening or closing it must not reflow the content.

### 3.2 Home

1. Edge-to-edge cinematic hero driven by the first resumable title, falling back
   to the first popular title.
2. Title or logo, compact metadata, one-line synopsis, primary play/resume,
   secondary details, and favorite action.
3. Continue Watching landscape shelf overlapping the hero fade.
4. Popular and provider collection shelves using portrait poster lockups.
5. No standalone page title, explanatory subtitle, or collection-help block.

Hero selection follows stable focus or pointer intent within the first-viewport
Continue Watching and Popular shelves; it does not auto-advance. Once the hero
leaves the viewport, deeper shelves browse independently and must not mutate the
hidden hero. Returning above the fold restores the previous featured selection.
A short debounce prevents background flashing while the pointer crosses a shelf.

### 3.3 Browse and collections

- Use one cinematic category header and a horizontal collection filter.
- Use a dense adaptive portrait grid with partial trailing content where useful.
- Keep sort as a secondary glass utility, not as the dominant toolbar element.
- Preserve pagination and the selected collection when returning from detail.

### 3.4 Search

- Present a large in-content search field near the top rather than hiding search
  in the window toolbar.
- Use landscape result cards for higher vertical density and easier title
  scanning.
- Preserve debounced remote search and clear loading, empty, and failure states.

### 3.5 Detail

- Let backdrop artwork fill the opening viewport with directional gradients for
  text contrast.
- Prefer supplied logo artwork; otherwise render the title in SF Pro Display.
- Keep the primary action first and visually dominant. Favorite and version
  controls are secondary.
- Use one canonical episode presentation: season filter followed by landscape
  episode cards. Remove duplicate numbered pills plus rows.
- Keep cast as a horizontal person shelf.
- Use matched artwork geometry and stable navigation restoration.

### 3.6 Playback options

- Present versions as an immersive glass sheet over artwork.
- Make the recommended/default version immediately playable.
- Keep codec, color, tracks, size, download, and link actions behind progressive
  disclosure.
- Preserve all existing playback, resume, link, and download behavior.

### 3.7 Favorites, people, and sign-in

- Favorites use the same category header, filters, and lockups as the library.
- Person detail uses a cinematic identity header and the standard media shelf or
  grid primitives.
- Sign-in uses a restrained full-bleed artwork atmosphere with one centered
  credential surface. It must remain readable without remote imagery.

## 4. Type System

Use the system San Francisco family only.

| Role | Size | Weight | Notes |
| --- | ---: | --- | --- |
| Hero title | 52–64 | Bold | Tight leading; maximum two lines |
| Page title | 38–44 | Bold | No rounded design variant |
| Section title | 24–28 | Semibold | Clear shelf boundary |
| Card title | 15–17 | Semibold | One line by default |
| Metadata | 12–14 | Medium | Monospaced digits where useful |
| Body | 15–17 | Regular | Maximum readable width 680 points |

Typography must scale with accessibility settings. Do not use tracking on body
copy. Uppercase is limited to short semantic labels.

## 5. Color and Material

- **Background:** near-black content canvas, not uniform pure black
- **Primary text:** white at high emphasis
- **Secondary text:** adaptive white at 62–72% emphasis
- **Focus accent:** luminous neutral white
- **Progress accent:** CineLark blue
- **Favorite semantic:** orange only
- **Success/watched semantic:** green only

Use glass only for navigation, compact controls, badges, and modal surfaces.
Cards remain artwork-led. Use native macOS 26 Liquid Glass APIs throughout; do
not implement compatibility fallbacks or a custom shader imitation.

## 6. Imagery and Lockups

### Portrait lockup

- Poster aspect ratio: source-driven, normalized near 2:3
- Regular width: 168–196 points
- Radius: 16 points
- Focus: 1.055 scale, 2-point lift, brighter edge, deeper soft shadow
- Title and metadata move with the artwork and remain unobscured

### Landscape lockup

- Aspect ratio: 16:9
- Regular width: 300–340 points
- Radius: 18 points
- Progress belongs at the bottom inside the artwork
- Play appears as a focused action, not as a permanently dominant overlay

### Focus transition

- Enter: 220 ms spring-like ease
- Exit: 160 ms ease-out
- Hero/background crossfade: 280 ms
- Reduced Motion: opacity and edge emphasis only; no scale, lift, or matched
  geometry travel

## 7. Interaction Model

- Unify keyboard focus, remote-style directional selection, hover, and press
  visuals through one interaction primitive.
- Arrow keys move semantically within shelves and grids. At a boundary, movement
  transfers to the nearest valid control in the adjacent section.
- Return activates; Escape goes back or dismisses the active overlay.
- Tab remains compatible with macOS full keyboard access.
- Pointer hover may preview hero content but must not steal keyboard focus.
- Focus identity is item-ID based so image completion and pagination cannot move
  selection.
- Scroll positions are bound to stable IDs and restored on back navigation.

## 8. Copy Hierarchy

Render existing localized product copy exactly. Reorganize it by priority:

1. title or logo
2. year, rating, duration or season count
3. one concise synopsis
4. primary play/resume action
5. secondary actions and state
6. technical metadata on demand

Do not expose provider or implementation terminology in primary browsing UI.

## 9. Constraints

```text
FONT  SF PRO
STYLE  CINEMATIC CONTENT-FIRST
MODE  DARK
ACCENT  ONE SEMANTIC ACCENT PER STATE
MOTION  RESTRAINED SPATIAL FOCUS
```

- Keep macOS 26 as the deployment target.
- Use public SwiftUI and AppKit APIs only.
- Preserve provider, caching, playback, favorites, localization, and security
  boundaries.
- Do not add a design dependency or third-party animation framework.
- Do not persist tokenized artwork or playback URLs outside existing policy.

## 10. Negative Prompt

- No Apple logos, Apple-owned artwork, copied product strings, or private APIs
- No generic purple gradients or decorative glass on every surface
- No permanently expanded taxonomy sidebar
- No auto-advancing hero carousel
- No hover-only action or state
- No invisible focus ring
- No focus jump after asynchronous image or page loading
- No duplicated episode navigation
- No motion when Reduce Motion is enabled
- No backend or playback semantic changes hidden inside the UI redesign

## 11. Screen-by-Screen Acceptance

| Surface | Required result |
| --- | --- |
| Launch | Branded atmospheric loading state; no blank black flash |
| Sign-in | One readable credential surface; keyboard-first completion |
| Home | Hero plus Continue Watching visible in the first viewport |
| Movies/Series | Collection filter, sort utility, deterministic poster grid |
| Collection | Stable focus and pagination without content jumps |
| Favorites | Shared media primitives and a clear media/people switch |
| Search | In-content search, landscape results, debounced updates |
| Detail | Cinematic hero, dominant play/resume, simplified episodes |
| Person | Identity hero and consistent works browsing |
| Versions | Default action first, technical detail progressively disclosed |
| Error/Empty | Contextual retry or recovery without abandoning navigation |

## 12. Validation

- Build with Swift 6 strict concurrency and deployment target macOS 26.
- Run all `CineLarkKit` tests.
- Verify English and Simplified Chinese at 960 × 640, 1440 × 900, and fullscreen.
- Verify keyboard-only directional traversal for every interactive surface.
- Verify pointer hover does not steal focus and back navigation restores context.
- Verify Increase Contrast, Reduce Transparency, Reduce Motion, and VoiceOver.
- Compare reference screenshots for layout, hierarchy, focus visibility, clipping,
  and first-viewport information density.

## 13. Reference Pack

Local screenshots and Apple-provided public reference media live in the
gitignored `refs/design/apple-tv/` directory.

Primary public references:

- [Migrate your TVML app to SwiftUI](https://developer.apple.com/videos/play/wwdc2024/10207/)
- [Redesigned Apple TV app elevates the viewing experience](https://www.apple.com/newsroom/2023/12/redesigned-apple-tv-app-elevates-the-viewing-experience/)
- [Apple TV brings a beautiful redesign and enhanced home entertainment experience](https://www.apple.com/newsroom/2025/06/apple-tv-brings-a-beautiful-redesign-and-enhanced-home-entertainment-experience/)
