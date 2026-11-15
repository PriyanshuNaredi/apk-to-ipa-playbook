# Results — what the port produced, in numbers you can check

All values below come from the final state of the port repository (`06_evidence/` holds the
source documents). Where a number was not measured, it says so.

## Size and shape

| | Android original | iOS port |
|---|---|---|
| Language | Kotlin + Jetpack Compose | Swift 5 mode + SwiftUI |
| Source lines | 2,144 (`.kt`) | 6,079 (`.swift`, 30 files) |
| Screens | 5 (`WeatherApp` `when` branches) + metric detail | 6 SwiftUI screens, same graph |
| UI framework | Compose Material3 | SwiftUI, no third-party UI deps |
| Map | MapLibre GL 13.6.1 (native renderer) | Hand-rolled SwiftUI Mercator tile renderer (1,139 lines) |
| Dependencies | OkHttp, MapLibre, Compose, AndroidX | Foundation, SwiftUI, CoreLocation — zero third-party Swift packages |

The 2.8× line increase is not bloat: Compose expresses layout far more compactly, and the iOS
side substitutes a custom map renderer (≈1,100 lines) for a 200-line MapLibre setup.

## Tests

| Suite | Count | Runtime |
|---|---|---|
| Host logic (XCTest) | 59 | 0.8 s |
| Host logic (swift-testing) | 28 | 0.1 s |
| Simulator UI (XCUITest) | 11 | ~5 min |
| Visual audit (excluded from normal runs) | 1 class, 10 screenshots | ~3 min |

Each test that matters corresponds to a defect in `../02_case_study/DEFECTS.md`; the mapping is in
that file's "caught by" column.

## Performance

| Metric | Before | After |
|---|---|---|
| Idle CPU, forecast screen | ~100% of one core | 5.7% |
| Cause | `ForecastPageModel.init` calling back into the view model on every parent body pass (≈22 Hz invalidation loop) | forwarded once from `.task` |
| Map pan/pinch | responsive; the watchdog scenario is the reason the map test exists | unchanged |
| Tile cache | in-memory only (96 tiles, ~25 MB) | 48 MiB disk LRU, matching the Android budget |

## Behaviour verified against evidence, not belief

| Claim | How it was proven |
|---|---|
| Radar plays the 13-frame window once, ~03:00 → 05:00 | The app's own session log: `frames 2/13 … 13/13` then silence; screenshot shows pause during, play after |
| Temperature badges never clip or hide | 10-screenshot audit; badge placement excludes measured panel frames |
| Units switch works | UI test flips it and re-reads the forecast |
| Legal texts ship | UI test opens Settings → licences and finds all five bundled files |
| Clean clone builds | Repo cloned to `/tmp/verify-clone`, built with a separate derived-data path, launched, idle CPU measured |

## Release

| Item | Value |
|---|---|
| Artifact | `Weather-1.1.1-6-unsigned.ipa` |
| Size | 1.2 MB |
| Architecture | `arm64` (device `Release`) |
| Signature | none — verified: no `_CodeSignature`, no profile, no `LC_CODE_SIGNATURE` |
| Install path | SideStore / LiveContainer on-device signing (user's own Apple ID) |
| CI | `.github/workflows/unsigned-ipa.yml`, `macos-15`, on `v*` tags |


## Second pass: the audit of a larger upstream

A second port used a much bigger upstream — Breezy Weather 6.2.2, 1,358 Kotlin files across
6 Gradle modules, 74 weather-source integrations, 63 locales — and the first thing it produced
was a list of everything the *first* pass never looked at. Measured inventory:
`../02_case_study/UPSTREAM_ATLAS.md`.

| What was missing from the method | Where it now lives | Evidence it mattered |
|---|---|---|
| Manifest surfaces (25 activities, 4 services, 15 receivers, 14 permissions → iOS) | `../01_method/11_surface_map.md` | Widgets, tile and wallpaper were being backlogged as "later"; they are impossible or different-shaped, not pending |
| Provider seam and per-feature coverage | `../01_method/12_source_architecture.md` | A single hardcoded provider made the pollen bounding-box gate look arbitrary and turned one failed request into a blank card |
| Per-feature cache validity, 5 km invalidation, background policy | `../01_method/13_refresh_and_cache.md` | One timestamp for six features; no TTL; "updated 2 min ago" next to hour-old air quality |
| Locale-derived unit defaults (per-country tables for wind/pressure) | `../01_method/14_units_and_locale.md` | The port defaulted to metric for `en_US`; invisible in a European simulator |
| 1,162 strings, 63 locales, plurals, RTL | `../01_method/15_localization.md` | English-only port, and the plural concatenation in the notification text |
| Data completion: backfill, derived values, `todayIndex` rule | `../01_method/16_data_completion.md` | "Today" read as `daily[0]` shows yesterday between midnight and the first refresh |
| Alert model, severity colours, notification rules | `../01_method/17_alerts_and_notifications.md` | Alerts were dropped with no written rule for the provider that would restore them |

Six new defect entries were added as a result (§31–36), and the consolidated sweep is
`../04_patterns/PORTING_CHECKLIST_V2.md` — 80-odd ticks, half of which are not visible on any
screen.

What this pass did **not** add: a reconstruction of the 74 provider integrations (the port ships
one), the 15 widget providers (WidgetKit needs a redesign, not a transcription), or the live
wallpaper (no iOS counterpart). Those are documented as deviations rather than backlog.

## Explicitly not measured

- **Physical device**: no Apple ID/team in the build environment, so the app has never run on
  real iPhone hardware. Everything above is simulator + host logic.
- **Denied-permission location path**: the `LocationFinder` fixes are proven by code reading and
  a timeout test, not by a device run with Location refused.
- **Map drawing math**: the renderer was audited for fetch/cache/render paths, not
  line-by-line for projection correctness; visual parity is the evidence.
- **Watchdog behaviour on device**: the radios' freeze scenario is reproduced synthetically in
  the simulator, which is not the same thing.