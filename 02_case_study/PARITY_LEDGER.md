# Parity ledger — every deliberate deviation from the APK

A port should not differ from its original by accident. These nine differences are on purpose,
each with a reason and — where it makes sense — a test.

| # | Area | Android | iOS port | Why | Guard |
|---|---|---|---|---|---|
| 1 | Basemap | OpenFreeMap dark vector style (`tiles.openfreemap.org`) | Esri World Dark Gray Canvas raster | Keyless and reliable; CARTO (tried first) returned an "API KEY REQUIRED" placeholder with HTTP 200 | `audit-08/09` show a real map |
| 2 | Map engine | MapLibre GL 13.6.1 native renderer | Hand-rolled SwiftUI/CoreGraphics Mercator renderer (1,139 lines) | Zero third-party dependencies, and radar/temperature compositing under our control. Cost: we own projection, caching and gestures | map UI tests + `audit-08..10` |
| 3 | Tile cache | MapLibre's OkHttp disk cache, 48 MiB | Own 48 MiB disk LRU + memory index | Same budget, replicated explicitly because there is no library doing it | eviction test against byte budget |
| 4 | Add city | None. Reaching search requires the Cities tab in the bottom bar | `+` control on the forecast header | Discoverability: the only route to adding a city was buried behind an icon-only tab | `testAddCityButtonOpensSearch` |
| 5 | Bottom bar labels | Icon-only (`IconButton`s) | Icons **and** `Map` / `Settings` / `Cities` labels | Icon-only parity hid the app's only entry point for adding a city | `audit-03`; nav UI tests |
| 6 | Radar playback | Opens parked on the newest frame, not playing | Opens on the oldest frame, plays the window once, stops at "now" | Faithful but confusing: the slider sat at the right edge and the button said "play", reading as *already played*. Manual play still loops | `testRadarPlaysOnceFromTheStartWhenMapOpens`; session-log frame trace |
| 7 | Temperature labels | A badge at every other grid sample, wherever it lands | ≤5 badges, greedily spaced, clear of edges, measured panels and the city marker | Badges were clipped by the screen edges and buried under translucent panels. **Data unchanged**: colours stay full-bleed over the whole viewport, the panel still reports the true area range | `audit-10` |
| 8 | Page indicator position | Dots centred in the leftover gap between bar items (≈24 pt left of screen centre) | Dots overlaid and centred on the full bar width | The original's position is a layout accident, not a design | `testPageIndicatorIsCentred` (1.0 pt) |
| 9 | Diagnostics | None | Diagnostics list at the end of Settings | The port added a diagnostics surface for watchdog work; it crowded the Cities tab, where Android has a real feature | `audit-06` |

Plus one non-visual difference: the Settings footer names **both** authors
("iOS port created by Priyanshu Naredi / Based on Weather for Android by Kian Konrad (MIT)").
The original names only Kian Konrad; the port's author is not a deviation from behaviour, but it
is a deviation from the string, and it is recorded here for the same reason.

## Deviations considered and rejected

Worth recording, because "we thought about it" is the useful part of a ledger.

| Considered | Verdict | Reason |
|---|---|---|
| Cap the temperature sampling box to ±4° | **Rejected** | Shrank the range to a plausible 8–25 °C but turned the shading into a rectangle over a quarter of the screen — read as a half-drawn overlay. Fix presentation with labels, not by narrowing data |
| Compose-style `PullToRefreshBox` equivalent | Deferred | No native SwiftUI pull-to-refresh in the target version; a custom gesture is a new defect surface for a minor gap |
| `rememberSaveable` parity for the current screen | Deferred | Would need `@SceneStorage`; low value for a single-screen-at-a-time app, but it is a real parity gap (documented, not hidden) |
| MapLibre iOS package | Rejected | Adds a dependency whose parity with the Android renderer is unprovable here, and removes control of radar frame compositing |
| Icon redrawn to "look iOS-native" | Rejected | iOS icon is rendered from the APK's own vector (`05_tools/make-app-icon.swift`); fidelity beats taste when the app is a port |

## Rule

If a difference is not in this file, it is a bug. That is the whole value of the ledger: it turns
"intentional?" into a lookup instead of an argument.