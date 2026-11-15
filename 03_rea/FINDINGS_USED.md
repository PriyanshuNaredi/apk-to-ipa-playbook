# REA findings that changed the port

Not "what REA said" — only the findings that produced a code change or a test. Each row:
finding → what it changed → where it lives now.

## 1. Tiles are cached on disk (48 MiB), not just in memory

**Finding** (memory analysis, bytecode-verified): MapLibre's HTTP layer caches tiles to
`cacheDir/map-http` with a 48 MiB budget; the app itself holds no tile bitmaps, so tiles survive
restart and re-entry.

**Changed**: the first iOS port had an in-memory 96-tile LRU only, so leaving the map and coming
back refetched everything. The port grew a real disk cache (`Models/DiskTileCache.swift`) with the
same 48 MiB budget (`TileCachePolicy.maxDiskBytes = 48 * 1024 * 1024`) and an eviction test.

**Where**: `05_tools/` copies of the port scripts; eviction test in the port's logic suite.

## 2. Pager identity is the city id; the current index is derived

**Finding**: `HorizontalPager(..., key = { cities[it].id })` and
`LaunchedEffect(pager.currentPage) { currentIndex = pager.currentPage }` — page identity is the
city, and there is exactly one source of truth for "which page is showing".

**Changed**: the iOS pager keyed pages by array index and kept its own index beside the scroll
position. Adding or removing a city could recycle the wrong page's state, or desync the dots and
the header. Now `ForEach(cities, id: \.id)` with `scrollPosition(id:)`, mirroring the Android
structure.

**Where**: `../02_case_study/DEFECTS.md` (identity class), `../04_patterns/COMPOSE_TO_SWIFTUI.md`
(pager row).

## 3. The bottom bar is a layout sibling, never an overlay

**Finding**: `Row` placed after `HorizontalPager(Modifier.weight(1f))` *inside* the weather
branch — the bar cannot be occluded, and only exists on the weather screen, because `when`
replaces the whole branch.

**Changed**: the port had the bar as an overlay in a `ZStack`, competing with page content for
touches (a map preview could swallow bar taps). Rebuilt as a sibling `VStack` element, exactly as
Compose nests it. This is the single most valuable finding in the whole analysis.

**Where**: `../02_case_study/PARITY_LEDGER.md` (not a deviation — a restoration),
`../04_patterns/DEFECT_CATALOG.md` entry #3.

## 4. Which scroll containers exist, per screen

**Finding** (marker counts): `LazyColumn` ×1 in `CityScreen`; `verticalScroll` ×1 in
`SettingsScreen` and `MetricScreen`; **no `Lazy*` at all on the forecast page** — the forecast is
one `Column(verticalScroll)` with a horizontal `Row` strip inside it, and the pager owns horizontal
drags.

**Changed**: stopped nesting a third scroller around the forecast column. Gesture routing on iOS
had one layer more than Android and produced dead zones; the port now matches the container count.

**Where**: `../01_method/06_ui_port.md` trap #5; map/forecast gesture tests.

## 5. Refresh policy is cache-first with a 900 s window, then a 15-minute loop

**Finding**: serve cache when younger than 900 s; otherwise fetch; refresh every 15 minutes under
`repeatOnLifecycle(RESUMED)`; a resume tick covers staleness after backgrounding.

**Changed**: ported as a `.task`-based loop with explicit cancellation (the first version leaked
and was replaced — see D17 in the defect log for the same class of bug).

**Where**: data-layer logic tests; `../01_method/05_data_layer.md`.

## 6. Back handling order: detail → screen → system

**Finding**: `BackHandler(screen != "weather" || detail != null)` pops the metric detail first,
then returns to the weather screen.

**Changed**: `back()` mirrors this order and is covered by a logic test, rather than each screen
deciding independently.

## 7. Persistence is atomic and pruned to the saved set

**Finding**: `AtomicFile` `forecast-<key>.json` with fail-write rollback; `saveCities` prunes any
forecast entry not in the saved-city set.

**Changed**: `.atomic` `Data.write` plus the same prune-on-save; a failed write cannot leave a
cache the app then trusts.

## 8. The launcher icon is a vector, and its pathData is the ground truth

**Finding** (resources): `res/drawable/ic_weather_foreground.xml` — an adaptive icon whose
background is transparent, with a cloud/sun glyph as `pathData`.

**Changed**: the iOS icon is rendered from that exact vector by `05_tools/make-app-icon.swift`
(M/L/C/A/Z parser + arc conversion, two-pass centring), on an opaque navy plate because iOS forbids
alpha. No hand-drawn lookalike.

## What REA did *not* provide

- Runtime behaviour. Every timing claim in the port was later re-verified from the app's own
  session log or a test.
- Visual truth. Colour stops and layout relations came from readable source + screenshots.
- Anything about iOS. Every iOS-side defect in this repo was found by building, measuring or
  capturing — never by analysis of the APK.