# Timeline — what happened, commit by commit

The port ran in two sittings (Linux CI bring-up, then macOS/Xcode bring-up) plus three
parity/behaviour passes. Each entry: what broke, what fixed it, what proves it now.
Commits referenced from the port repository (`PriyanshuNaredi/weather-ios-port`).
Port 2's commits are in [`PriyanshuNaredi/gust`](https://github.com/PriyanshuNaredi/gust).

## Sitting 1 — scaffolding on Linux (pre-macOS)

`SwiftPM` package + `xtool` cross-compile, never executed on a device. Value: it forced the data
layer and every screen into existence as *code*, and it produced the first `WeatheriOS.ipa`
(packaged, unsigned, unlaunchable). Lesson recorded in `../01_method/04_scaffolding.md`: a build
system nobody runs is not verified.

## Sitting 2 — macOS/Xcode bring-up (`7104089`)

First real build: Xcode 16.0, iOS 18 SDK, simulator.

| # | Defect | Fix |
|---|---|---|
| D1 | `ForecastPageModel.init` called back into the view model on every parent body pass → ≈22 Hz invalidation loop, **100% CPU idle** | forward once from `.task`; idle 5.7% |
| D2 | CARTO `dark_all` returned an "API KEY REQUIRED" placeholder tile | Esri World Dark Gray Canvas + attribution |
| D3 | Settings units `Toggle` never fired its setter | `Button` + capsule switch, 44 pt |
| D4 | `Array.uniqued` O(n²) | `Set`-based |
| D5 | `DateFormatter` allocation churn per render | cached formatters |
| D6 | Metric grid width measurement fed back into layout | quantised measurement |
| D7 | Swift 6 strict concurrency rejected Darwin-only paths | Swift 5 mode + `platforms:` in the test package |

Also: `project.yml` as source of truth, `macos-{build,tests}.sh`, first UI target with 7 cases,
`-resetState` launch argument.

## Sitting 3 — cosmetic parity pass (`a8099eb`, `96e6bf3`)

| # | Defect | Fix |
|---|---|---|
| D8 | Every child of a panel painted as its own card (13 call sites) | `VStack` inside `GlassPanel`, matching Compose's `Column` |
| D9 | Bottom bar overlaid the pager and lost taps to page content | bar became a layout **sibling**, as in `MainActivity.kt:144-156` |
| D10 | Bottom bar composition wrong (spacing, targets, debug icon) | rebuilt to the Compose structure, labels restored, 12 pt padding |
| D11 | Scrims bound to content rather than chrome | overlay bound to `safeAreaInsets` |
| D12 | Saved cities used `List` chrome | glass cards in a `LazyVStack` |
| D13 | Metric tiles ragged per row | `Grid`/`GridRow` with a real height proposal |
| D14 | Day-range bars square-ended at maximum | round caps inset by radius |
| D15 | Header/link touch targets below 44 pt | explicit `minHeight: 44`, larger glyphs |

## Sitting 4 — dots, labels, add-city, audit (`ad72be2`, `2844f18`)

- Page indicator was centred in the leftover bar gap: **24 pt left of screen centre**. Now an
  overlay centred on the full bar width, asserted by `testPageIndicatorIsCentred` (1.0 pt).
- Bar labels restored after icon-only parity — discoverability beat pixel fidelity.
- `+` Add-city control added to the forecast header (iOS-only; the APK has none).
- Repo-wide audit (ponytail method) → `CODE_AUDIT.md`, six findings fixed, including the two
  `LocationFinder` hangs (D16/D17), the GeoNames numeric-id bug (D18) and the tile-cache
  re-sort (D19). Dead debug views gated behind `#if DEBUG`; legacy basemap helper deleted.

## Sitting 5 — behaviour correctness (`24b533a`, `f3d35dc`, `ad4f352`)

- **Radar (D20):** ported Kotlin's `followLatest`, which parked the playhead on the newest frame
  with nothing playing — the loop read as "already played". Now opens on the oldest frame and
  plays once, stopping at "now". Proven from the app's own session log (`frames 2/13 … 13/13`).
- **Temperature badges (D21):** every other grid sample got a badge wherever it landed, so badges
  were sliced by the screen edges and buried under panels. Now ≤5 badges, greedily spaced,
  excluded from measured chrome frames and the city marker.
- **Temperature field:** a capped sample box was tried (to tame a −20…28 °C range on a Japan map)
  and **reverted** — it made the shading a rectangle over a quarter of the screen. Colours stay
  full-bleed; only labels were thinned.

## Sitting 6 — identity and release (`adedbd4`, `4701859`, `5acc2eb`)

- **Icon (D22):** the target set `ASSETCATALOG_COMPILER_APPICON_NAME` to an empty string, so
  `actool` never produced `Assets.car` and the app shipped a blank tile. Icon now rendered from the
  APK's own vector by `05_tools/make-app-icon.swift`, verified on the simulator home screen.
- Creator credit: port author named, original author retained, `CREDITS.md` added.
- Unsigned IPA release path + CI (`.github/workflows/unsigned-ipa.yml`), install docs for
  SideStore / LiveContainer.

## What the timeline says about the method

Defects cluster in the same two places every time: **state that writes during evaluation**
(D1, D19) and **framework assumptions one level too shallow** (D8, D9, D21). Both are cheap to
test for and expensive to notice, which is why stage 8's instruments exist.
