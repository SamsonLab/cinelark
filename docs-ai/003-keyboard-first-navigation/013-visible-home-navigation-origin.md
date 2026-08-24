# 003.013 — Visible Home Navigation Origin

## Context

Home retains semantic keyboard selection independently from manual scrolling.
Scroll-wheel input also switches the coordinator to pointer modality, where a
Preview action can remain the last pointer target even after the first shelves
have left the shelf viewport. The next arrow command can therefore hand off to
that stale Preview target and move near the top of the graph instead of relative
to the visible shelves.

Horizontal shelf scrolling identifies the card lockup itself. Leading alignment
can place that target exactly at the scroll viewport boundary, leaving no room
for focus scale and stroke outside the card's nominal bounds.

## Decision

Semantic selection memory remains authoritative while its section is visible.
When it is not visible, arrow navigation derives a direction-aware origin from
the visible shelf boundary before applying the requested move. Horizontal card
targets include focus clearance in their scroll geometry without changing card
layout geometry.

## Change

- Track the Home shelf IDs currently visible in the vertical ScrollView.
- Treat Preview selection as a valid arrow origin only while the first shelf is
  visible; otherwise ignore stale Preview hover or keyboard state.
- For an offscreen origin, make Up start at the top visible shelf and Down at
  the bottom visible shelf, then move exactly one semantic section.
- Preserve section-local target memory when selecting the visible boundary.
- Give Continue Watching and poster cards an invisible 18-point leading scroll
  clearance target while preserving their existing margins and spacing.
- Keep confirmation-key pointer handoff behavior unchanged.

## Validation

- `xcodebuild -project apps/macos/CineLark.xcodeproj -scheme CineLark
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build -quiet` completed
  successfully.
- `git diff --check` completed successfully.
- Static inspection confirmed that visibility is read from semantic LazyVStack
  targets, the event-time closure reads the latest visibility binding, and
  scroll targets remain direct LazyHStack children.
- The 18-point wrapper clearance is offset by an 18-point leading-margin
  reduction and an 18-point spacing reduction, preserving the original 48-point
  first-card alignment and 26-point visual card gap.
- Account-backed runtime validation scrolled Home to approximately 47% through
  several populated shelves. Up selected the adjacent `欧美电影` shelf and moved
  the vertical offset only to approximately 36% instead of jumping to Preview.
- Six consecutive Right commands selected `暗影伊莉丝`; the selected poster and
  focus treatment remained fully inside the leading viewport boundary.

## Current state

Implemented on 2026-08-24 in Home and the two reusable Home shelf components.

Home records shelf visibility at a 15% threshold. A target remains the arrow
origin while its semantic section is visible. Otherwise Up rebases on the first
visible shelf and Down on the last visible shelf before applying one normal
section transition. Preview targets are eligible only while the first content
shelf is visible. Confirmation-key pointer handoff is unchanged.

The initial implementation retained a group-level `contentTopID` on the target
layout. Runtime validation showed that this collapsed visibility reporting to
the whole group, reproducing the Preview jump. The group ID was removed, and
Preview return now scrolls to the first real shelf ID instead.

Continue Watching and poster targets now contain leading focus clearance inside
their direct identified wrappers. Layout compensation keeps the existing card
positions and gaps while leading-aligned programmatic scrolling leaves the
selected surface inside the viewport.
