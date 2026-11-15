# Stage 6 — UI port

Screens, in navigation order, against the parity spec. The mechanics are mostly
`../04_patterns/COMPOSE_TO_SWIFTUI.md`; this file is about *process* and the layout traps that a
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

## The look is in the layouts, not in the theme

A port can have every card, every value and every tab and still be unrecognisable, because the
things that make a screen *look like itself* are spread across resource files that nobody reads
first. Read them before writing a single view, and write down the answers:

| Question | Where the answer is | What it decided in this playbook's second port |
|---|---|---|
| What shapes exist? | `app:shapeAppearance` on each `res/layout/container_*.xml` | 12 of 15 containers declare one: 8 `Corner.ExtraLarge`, 4 `Corner.Full`; header, clock and UV declare none. Two shapes, not one, and not a theme default |
| Are half-size cells square? | `app:layout_constraintDimensionRatio="1:1"` | 10 containers pin a square block inside the card. Frame paired half cards to a square or they stand at different heights |
| How big is the number? | `res/values/styles.xml`, a per-block `TextAppearance` | 45 sp for the block value, 140 sp for the header, 16 sp title, 14 sp content, 12 sp subtitle. Copy the scale; do not reuse `.title2` |
| Is the unit part of the value? | the holder code (`formatUnitsHalfSize`) | No: value and unit are separate views with different sizes. A single formatted string cannot be restyled to match |
| What does a trend block look like? | `res/values/dimens.xml` | `trend_item_width` 67 dp, `daily_trend_item_height` 298 dp — one fixed-width column per day, scrolling sideways, not a row list |
| Where does the artwork come from? | the icon provider (`res/xml/icon_provider_*.xml`) | A resource-name lookup with 153 filter entries over 85 PNGs and 83 distinct conditions; only 2 conditions have separate day/night files |
| What navigation exists? | `res/menu/*.xml` and the activity layout | An up button, an edit action and an overflow menu. No bottom navigation, so a port must not add one |

Two consequences worth repeating, because they cost the most time:

- **A shape attribute is per-container.** Extracting "the corner radius" from a theme is the wrong
  file; the containers disagree on purpose (defect §37).
- **Icons are content, not decoration.** Substituting the platform's symbol set collapses 83
  conditions into a handful of glyphs and changes what the screen communicates (defect §38). Copy
  the drawables and port the *lookup*, then test that every name the lookup can produce resolves to
  a file.

Nothing in this section requires reading Kotlin: all seven answers are XML, and all seven can be
gathered by `grep` in a few minutes.

## Wording is part of the screen

Every string comes from the original, including awkward ones ("Interpolated model temperature").
Two exceptions, both documented in `../02_case_study/PARITY_LEDGER.md`:

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