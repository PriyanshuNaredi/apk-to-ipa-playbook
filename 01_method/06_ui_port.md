# Stage 6 — UI port

Screens, in navigation order, against the parity spec. The mechanics are mostly
`04_patterns/COMPOSE_TO_SWIFTUI.md`; this file is about *process* and the layout traps that a
mapping table cannot warn you about.

## Order of work

1. **Shell first**: the screen switch, back behaviour, and the shared chrome (bars, scrims).
2. **Then leaf screens** in the order a new user hits them: empty state → search → forecast →
   settings/cities → map.
3. **Metric detail last** — it is the screen everything else links into.

Porting the map early is tempting and usually wrong: it is the only screen with unknown work, so
it belongs in stage 7 with its own budget.

## The layout traps, in the order they bit

**1. A view-builder is not a container.** Compose's `Column` inside a card composable stacks
children; a SwiftUI `@ViewBuilder` returning a tuple of views paints each child with the
modifier applied by the caller. Result: every child looked like its own card. Fix: wrap content
in `VStack(alignment: .leading, spacing: 0)` *inside* the panel.

**2. `frame(maxHeight:)` does not equalise inside a vertical scroll view.** A `ScrollView` gives
an unbounded proposal, so children keep natural heights and a row stays ragged. `Grid` + `GridRow`
supplies a real proposal, so tiles equalise. If you need equal heights, you need a container that
proposes — not a modifier that wishes.

**3. Reserving lines truncates real content.** `lineLimit(2, reservesSpace: true)` equalised a
row by clipping "Feels like" on some units. Do not buy layout stability with content.

**4. Touch targets are layout.** Android's `IconButton` is 48 dp; a 22 pt SwiftUI glyph with
default padding is not. Set explicit `minHeight: 44` (or 48) on every interactive row, and check
with the UI test that the element is hittable, not merely present.

**5. Overlays compete for hit-testing.** The bar-as-overlay version lost taps to the page content
underneath. The structural fix is parity: the bar is a sibling in the layout, not an overlay.

**6. Safe-area insets move.** Scrims bound to `safeAreaInsets` looked wrong until bound to the
*overlay* rather than the content. Anything that must hug the chrome belongs in an overlay.

**7. Centring is relative to what you centre in.** The page dots were centred inside the leftover
gap between four bar items — 24 pt left of screen centre. Overlaying them on the full bar width,
then testing `midX == window.midX` within 1 pt, made it unarguable.

## Wording is part of the screen

Every string comes from the original, including awkward ones ("Interpolated model temperature").
Two exceptions, both documented in `02_case_study/PARITY_LEDGER.md`:

- The footer credits the port author **and** the original author.
- The diagnostics surface (no Android counterpart) moved from the bar into Settings, where it does
  not crowd a real feature.

## Verify with screenshots, not adjectives

Each screen gets a named capture from the visual audit (`06_evidence/screenshots/`). Layout claims
then have a file behind them, and the next session can compare instead of re-litigating.

If you can, hand the captures to a vision pass with one specific question per image ("is the Save
button aligned right?"). It catches the class of defect where you have stopped seeing your own
layout.

## Exit gate

- Every screen appears in the visual audit under a stable name.
- Every interactive element has ≥44 pt of touch area and is reachable in a UI test.
- Every string matches the original, or is in the parity ledger as a deviation.