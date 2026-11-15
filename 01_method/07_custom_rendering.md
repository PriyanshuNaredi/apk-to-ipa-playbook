# Stage 7 — Custom rendering

Every port has one screen the framework does not give you: a map, a canvas, a chart, an animation
loop. It is the only stage with genuine unknowns, so it gets its own budget and its own rules.

## Decide the substitution before writing code

| Android approach | iOS options | What this port chose |
|---|---|---|
| MapLibre GL (GPU vector renderer) | MapLibre iOS (SPM), MapKit, custom raster | **Custom raster in SwiftUI `Canvas`/`Image` + CoreGraphics** — no third-party dependency, full control of the radar/temperature compositing |
| Canvas/Compose drawing | `Canvas`, CoreGraphics, Metal | SwiftUI `Canvas` |
| Video/animation | `AVPlayer`, frame loop on a timer | Frame loop driven by `.task(id:)` with explicit delays |
| Vector icon | PDF/SVG asset, or draw it | CoreGraphics path from the Android vector (icons, marks) |

The criterion is not "what is easiest" but "what can I verify". MapLibre-on-iOS would have been
less code and less control over the composited radar frames, and it would have added a dependency
whose parity with Android's renderer is unprovable from this side.

## Build it in this order

1. **Projection and camera math**, with unit tests: lon/lat ↔ tile x/y ↔ screen points, zoom
   limits (2–12 here), and the visible-bounds function the data layer needs.
2. **Tiles**: fetch, decode off the main actor, cache (memory + disk budget), draw.
3. **Interaction**: pan and pinch, with deltas measured against the previous frame — a
   `DragGesture.translation` is cumulative, so `panBy(translation - lastTranslation)`.
4. **Overlays**: radar frames, interpolated fill, markers — each as its own view so layer opacity
   is a number you can point at.
5. **Lifecycle**: cancel work when the screen leaves, resume cleanly when it returns.

## Things that only show up at runtime

**Frame identity.** Radar frames are cached per frame path; if the cache key does not include the
frame, a stale animation flashes. Key it exactly like the original.

**Playback semantics are a product decision.** Android parks the playhead on the newest frame; the
port starts at the oldest and plays once. Both are defensible; only one is comprehensible to a user
opening the screen. Decide, document, test (`testRadarPlaysOnceFromTheStartWhenMapOpens`).

**Label placement needs measured chrome.** Badges drawn at grid points get sliced by screen edges
and buried under translucent panels. Fixed insets do not survive text-size and locale changes:
measure the chrome (`PreferenceKey` + `GeometryReader`), exclude those rects, and greedily space
badges so they never crowd (`04_patterns/DEFECT_CATALOG.md` D13).

**Full-bleed beats a clipped box.** A capped sampling box made the colour field a rectangle over a
quarter of the screen, which reads as a half-drawn overlay. Sample the whole viewport; thin the
*labels*, not the data.

**Interpolation is a data decision.** 7×7 samples over a viewport that spans 27° of latitude is
faithful to the original and produces a −20 °C to +28 °C range on a Japan-centred map. That is
correct data with a confusing presentation; fix presentation with labels and copy, never by
quietly narrowing the data.

## Performance budgets, set up front

| Budget | Target here | How it is checked |
|---|---|---|
| Idle CPU (screen open, nothing happening) | < 6% of a core | `ps aux | grep WeatheriOS` after 30 s idle |
| Pan/pinch responsiveness | no dropped gestures | UI test pans and pinches, asserts state changed |
| Memory | bounded by cache policy | cache budget constants + eviction test |
| Animation smoothness | 700/1300 ms rhythm | session log timestamps per frame |

The idle-CPU budget is the highest-value number in the whole method: it caught a 22 Hz
invalidation loop that would have shipped as "the phone gets warm".

## Exit gate

- Projection math has tests.
- Interaction works in a UI test that would fail if gestures were swallowed.
- The screen cancels its work on disappear (verified in the diagnostics log, not by reading code).
- Idle CPU is under budget, measured.