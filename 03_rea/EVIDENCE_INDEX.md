# Evidence index — all 50 REA artifacts, and what each proves

Every file in `evidence/` is a verbatim copy from the port repository's
`07_tools/rea-analysis/` directory, produced by `rea-agents@6.9.0` against
`Weather_v1.1.1.apk` (SHA-256 `49a502b2…99c1`). Nothing here was edited.

## Written analyses (the arguments these artifacts support)

| File | Lines | What it establishes |
|---|---|---|
| `REA_SETUP_REPORT.md` | 71 | How REA was installed project-locally without touching global agent config; the Node engines gate; the pre-install tarball inspection |
| `ORIGINAL_APK_DEEP_ANALYSIS.md` | 116 | Areas A–E: single-activity UI architecture, the weather screen, data layer, memory model, parity risks — each claim sourcing a file:line or a dump |
| `MEMORY_AND_UI_FINDINGS.md` | 52 | Android's memory model vs the iOS port (the 48 MiB disk cache gap), and the eight UI guarantees Android provides structurally |
| `ANDROID_IOS_PARITY.md` | 92 | 12-row Android↔iOS comparison, plus post-mortems on forecast scrolling and bottom-bar hit-testing |

## Binary-level facts

| File | Proves |
|---|---|
| `out-signature.json` / `out-signature.err` | Which certificate signed the analysed APK: no rebuild was substituted for the official artifact |
| `out-package.json` | Package inventory and dependency shape (19,287 classes) — the size/scale assessment |
| `out-resources.json` | Compiled resource table: strings, colours, dimension values, drawable references |
| `out-apktool-client.json` | apktool's decode report: resource IDs preserved, which files the manifest and layouts came from |
| `out-classes.json`, `app-classes.txt` | Flat class list — the map used to decide which classes were worth dumping |

## Class dumps (members, constants, annotations)

| File | Class it documents | Used for |
|---|---|---|
| `out-class-MainActivityKt.json` | `MainActivityKt` (192 KB) | The screen `when`, the bar composition, pager wiring |
| `out-class-MapsKt.json` | `MapsKt` | Map setup: zoom limits, style URL, layer callbacks |
| `out-class-OpenWeatherRepository.json` | `OpenWeatherRepository` | Cache keys, budgets, network call shapes |
| `out-class-MapRepository.json` | `MapRepository` | Tile/radar URL construction |
| `out-class-WeatherRepository.json` | `WeatherRepository` | Interface both repositories implement |
| `out-class-DataKt.json` | `DataKt` | Grid coordinate maths (`gridCoordinates`), longitude normalisation |
| `out-class-ForecastProjectionKt.json` | `ForecastProjectionKt` | Derived values the forecast screen shows |
| `out-class-ModelsKt.json` | `ModelsKt` | Model shapes and unit conversions |

## Method dumps (bytecode-level behaviour)

Twelve methods, chosen because each answered a question the readable source left ambiguous:

| File | Question it answered |
|---|---|
| `out-m-WeatherApp.json` | How the screen state machine and `rememberSaveable` work |
| `out-m-WeatherApp$add.json` | What "add city" does: dedupe by id, save, scroll the pager |
| `out-m-WeatherApp$locate.json` | The location flow's success/failure handling |
| `out-m-ForecastPage.json` | Per-city state keys, refresh policy, scroll containers |
| `out-m-CityScreen.json` | Search list behaviour and page size |
| `out-m-MetricScreen.json` | Metric detail composition |
| `out-m-SettingsScreen.json` | Units handling and attribution block |
| `out-m-findLocation.json` | Location request policy and timeout handling |
| `out-m-OWR-cached.json` | Cache-first read path and staleness window |
| `out-m-OWR-get.json` | Network fetch and error mapping |
| `out-m-OWR-read.json` / `out-m-OWR-write.json` | Atomic file persistence semantics |
| `out-m-OWR-radar.json` | RainViewer timeline request shape |
| `out-m-OWR-temperatures.json` | 7×7 grid request, `cell_selection`, 30-minute validity |
| `out-m-OWR-saveCities.json` | Prune-to-saved-set behaviour on save |
| `out-m-Maps-prepareMap.json` | Camera move, zoom preferences, gesture config |
| `out-m-Maps-clearWeatherLayers.json` | Layer clearing so radar does not accumulate |

## Decompiled sources (jadx text, for reading)

`decompiled-WeatherApp.java`, `decompiled-ForecastPage.java`, `decompiled-CityScreen.java`,
`decompiled-MetricScreen.java`, `decompiled-SettingsScreen.java`, `decompiled-OWR-{cached,get,radar,read,saveCities,temperatures,write}.java`.

Used to *read* a method when the JSON dump was too abstract, and cross-checked against the shipped
Kotlin source. Where the two disagreed, the bytecode won.

## Scripts

| File | Purpose |
|---|---|
| `extract-markers.cjs` | Counts structural markers (e.g. `LazyColumn`, `verticalScroll`) per class — the source of the "one scroller per screen" finding |
| `extract-repo-markers.cjs` | The same, scoped to the repository classes |
| `apktool-launcher.cmd` | Windows launcher used for the resource decode |

## How to re-derive any of it

```bash
# in a scratch copy of the port repo, with REA installed project-locally
node 07_tools/rea-analysis/rea/node_modules/.bin/rea --help
# signature / manifest / package facts
rea signature 00_original/apk/official/Weather_v1.1.1.apk
rea package   00_original/apk/official/Weather_v1.1.1.apk --format json
# one method, as JSON
rea method    00_original/apk/official/Weather_v1.1.1.apk dev.kiankonrad.weather.MainActivityKt saveCities
```

Exact command names vary by REA version; the setup report records v6.9.0's surface.