# Defect log — 22 defects, with root cause and proof

Every entry: what the user would have seen, the actual cause, the fix, and what guards it now.
IDs match `TIMELINE.md`.

Legend for **class**: `state` = state written during evaluation; `perf` = performance/resource;
`api` = framework or platform API misread; `parity` = differs from the Android original;
`build` = build/packaging; `data` = data-layer correctness.

| ID | Class | Defect | Root cause | Fix | Guard |
|---|---|---|---|---|---|
| D1 | state | Forecast screen burned 100% of a core while idle | `ForecastPageModel.init` called `onWeather(...)`; each parent body pass constructed a page model that wrote back into `WeatherViewModel`, invalidating the parent (≈22 Hz) | Forward once from `.task` instead of `init` | idle CPU measured at 5.7%; `ps aux` after 30 s |
| D2 | api | Map showed "API KEY REQUIRED" tiles | CARTO `dark_all` now serves a placeholder for keyless requests (HTTP 200, so no error path) | Esri World Dark Gray Canvas + attribution | `audit-08/09` screenshots show real map |
| D3 | api | Units switch did nothing | `Toggle` setter never fired under this SDK/`@Observable` combination | `Button` + capsule switch (also a proper 44 pt target) | units UI test flips and re-reads forecast |
| D4 | perf | Hourly list stuttered on long ranges | `Array.uniqued` rebuilt the array per element (O(n²)) | `Set`-backed dedupe | logic test on dedupe |
| D5 | perf | Re-render cost scaled with row count | `DateFormatter` allocated per format call | cached formatters, keyed by format | code review; no test |
| D6 | state | Metric grid oscillated between widths | width measurement wrote back into layout | quantised measurement | `Grid`-based layout later (D13) |
| D7 | build | Build failed under Swift 6 | `DiagLog`'s `mach_task_self_` and `WeatherMapView`'s `static var inFlight` are Darwin-only, never compiled by the Linux CI | `SWIFT_VERSION 5.0`, `SWIFT_STRICT_CONCURRENCY minimal`; `platforms:` added to the test package | clean-clone build |
| D8 | api | Every panel rendered as several stacked cards | `@ViewBuilder` returns a tuple; card modifiers applied at the call site painted each child. Compose's `Glass` is a `Column` | `VStack(alignment: .leading, spacing: 0)` inside the panel | all 13 call sites in the audit captures |
| D9 | parity | Bottom-bar buttons sometimes ignored taps | bar was an overlay; page content under it won hit-testing. Android's bar is a layout **sibling** of the pager | bar became a sibling `VStack` element | bar/nav UI tests; `testAddCityButtonOpensSearch` |
| D10 | parity | Bar looked unlike the original (spacing, targets, stray debug icon) | ad-hoc reconstruction | rebuilt to `MainActivity.kt:147-152`; labels restored; 12 pt padding | `audit-03/04` |
| D11 | parity | Status/nav areas showed raw content behind the bar | scrims bound to content instead of chrome | overlay scrim `0x99112340` bound to `safeAreaInsets` | `audit-04` |
| D12 | parity | Saved cities looked like a system list | `List` chrome | glass cards, 12 pt spacing | `audit-07` |
| D13 | api | Metric tiles ragged per row (~14 pt) | `.frame(maxHeight:)` cannot equalise inside a `ScrollView` (no bounded proposal) | `Grid`+`GridRow` with explicit height proposal | `audit-03` (≈1 pt) |
| D14 | parity | Range bars had square ends at the maximum value | rectangle drawing | round caps inset by radius | `audit-03` |
| D15 | parity | Back arrows / links were below 44 pt | glyph-size defaults | explicit `minHeight: 44`, larger glyph, negative leading | UI test hittability |
| D16 | api | "Use my location" could hang forever on a second tap | `ensureAuthorized` stored a second caller's continuation *outside* the lock and never requested authorization, so one delegate callback resumed only the first | waiter array resumed by the single callback; request only when the queue was empty | `testUseMyLocationTerminates` |
| D17 | api | Location fetch never timed out (18 s spec) | `withTaskGroup` waits for **all** children, and the `CLLocation` child sat in an unchecked continuation with no cancellation handling; timed-out continuations leaked | `withTaskCancellationHandler` + resolve stale slot first | `testUseMyLocationTerminates` (6.9 s) |
| D18 | data | City identity silently degraded to `"lat,lon"` | GeoNames `id` is a JSON **number**; `as? String` always failed. Kotlin's `optString` stringifies | numeric ids stringified via the JSON number helper | codec test with recorded payload |
| D19 | perf | Tile cache re-sorted its whole index per stored tile | `store` recomputed total bytes by sorting | running byte total; evict only over budget | eviction test against a byte budget |
| D20 | parity | Radar looked already played on open | `loadRadar` ported `followLatest`: playhead parked on newest frame, `playing == false` | first load opens oldest frame and plays once (`autoPlayOnce`), stops at the end | `testRadarPlaysOnceFromTheStartWhenMapOpens`; session log |
| D21 | parity | Temperature badges cut in half / hidden behind panels | marker loop drew a badge at every other sample wherever it landed | ≤5 badges, greedy spacing, exclusion of measured chrome rects + city marker | `audit-10` |
| D22 | build | App shipped with a blank icon | `ASSETCATALOG_COMPILER_APPICON_NAME` was set to `""`, so `actool` produced no `Assets.car`. Nothing failed: an empty name is not a wrong one | `AppIcon` + icon rendered from the APK vector | `Assets.car` in bundle; home-screen capture |

## The patterns

**1. `api` defects are the expensive ones (8 of 22).** Every one was code that reads correctly:
a `Toggle` that looks wired, a `withTaskGroup` that looks like a timeout, a `@ViewBuilder` that
looks like a container, an empty string that looks like a value. None of them throw. All of them
were found by a *check* (a test, a measurement, a screenshot), never by reading.

**2. `state` defects are found by metrics, not tests (D1, D6, D8).** An invalidation loop passes
every functional test. Idle CPU is the only witness.

**3. `parity` defects are found by screenshots.** D8, D10, D12, D13, D14, D20, D21 were all
visible in a capture and invisible in a diff.

**4. `build` defects are found by inspecting the artifact (D22).** A green build says nothing about
what is inside the bundle.

## What this implies for the next port

- Write the guard **before** the feature for the `api` class (they are predictable).
- Budget for the `state` class: a `.task`-based data flow and an idle-CPU check after every screen.
- Never close a screen without a capture; never close a release without inspecting the artifact.
- Treat "nothing failed" as a hypothesis. D22 and D2 both shipped silently behind HTTP 200 and
  an empty build setting.