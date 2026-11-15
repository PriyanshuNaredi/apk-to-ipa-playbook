# Upstream atlas — what Breezy Weather 6.2.2 actually contains

Measured from [`breezy-weather/breezy-weather`](https://github.com/breezy-weather/breezy-weather)
at tag `v6.2.2`, the same tree the port — [Gust](https://github.com/PriyanshuNaredi/gust) —
was built against. Every number here was produced by a command, not from memory; the commands
are in the last section so the numbers can be re-derived on another tag.

This document exists because the first pass over the repository was driven by the *screens*
(what a user sees) and not by the *system* (what the app is). Screens accounted for the UI;
they said nothing about source selection, cache lifetimes, locale defaults, data completion
or alerts — all of which the port either omitted or discovered late.

---

## 1. Shape

| Fact | Value |
|---|---|
| Kotlin files | 1,358 |
| Kotlin lines | ~136,700 (app 122,023 · weather-unit 5,549 · ui-weather-view 2,958 · domain 2,550 · maps-utils 1,830 · data 1,796) |
| Gradle modules | 6 (`:app`, `:data`, `:domain`, `:maps-utils`, `:ui-weather-view`, `:weather-unit`) |
| Resource XML files | 487 |
| Dependency catalog entries | 145 (`gradle/libs.versions.toml`) |
| Locales | 63 language directories (incl. regional variants `en-rGB`, `pt-rBR`, `zh-rTW`, `nb-rNO`); 77 `values-*` directories once night-mode and API-level overlays are counted |
| Translatable strings | 1,162 in `strings.xml`, plus one `<plurals>` file |
| Source integrations | 9 worldwide + 59 national weather services; 3 location, 1 place search, 3 reverse geocoding |
| Database | SQLDelight, 25 migrations |
| Unit tests in repo | 11 files (Android instrumentation tests: 0) |
| Android components | 25 activities, 4 services, 15 receivers, 3 content providers |
| Permissions | 14 |

The module split is the single most useful thing to read first: `weather-unit` is pure
arithmetic (no `Context` except in formatting), `domain` is the model and contains no UI,
`:app` is everything else. A port that starts at `:app` will try to port Hilt, Room-shaped
storage and Material theming at the same time.

## 2. What is in `:app` that is not a screen

| Package | Contents | iOS counterpart |
|---|---|---|
| `sources/` | 74 service classes + serializers + converters | one `WeatherProvider` protocol per service |
| `background/` | updater, forecast + tomorrow notifications, boot receiver | `BGAppRefreshTask`, `UNUserNotificationCenter` |
| `remoteviews/` | 15 widget providers, notification widgets | WidgetKit extensions |
| `domain/settings/` | config tree, defaults, display options | `UserDefaults` + one Codable preferences struct |
| `ui/theme/` | Material 3 dynamic colour, weather theme colours, icon providers | asset catalogue + a colour table |
| `work/` | stray design assets (not a module) | — |

## 3. Features the port targeted, and coverage

| Area | Upstream | This port | Note |
|---|---|---|---|
| Main card stack | 15 block types + alerts | 14 of 15 | alerts absent, no provider in scope sends them |
| Half/full layout law | `ViewType.isHalfSizeableBlock` | ported 1:1 | verified by UI tests |
| Header | relative time, condition, value+unit, feels-like, day/night range, weather-coloured background | ported | colour table literal-for-literal |
| Detail pages | one page per element, date selector, deviation, normals, degree days | chart + date selector + day/night panel | climatology not ported |
| Sources | 74 integrations, per-feature selection, API keys | 1 (Open-Meteo) | see `../01_method/12_source_architecture.md` |
| Cache | per-feature TTL, 5 km coordinate invalidation | none | see `../01_method/13_refresh_and_cache.md` |
| Background refresh | WorkManager, 0:30–24:00 intervals, first-location policy | foreground timer only | documented as a deviation |
| Units | CLDR + `LocalePreferences`, per-country fallbacks | five pickers, Celsius default | see `../01_method/14_units_and_locale.md` |
| Localization | 77 locales, plurals, RTL | English only | see `../01_method/15_localization.md` |
| Alerts | severity, colour, dedupe, notifications | none | see `../01_method/17_alerts_and_notifications.md` |
| Data completion | backfill, extrapolation, computed sun/moon | partial (sun/moon) | see `../01_method/16_data_completion.md` |
| Widgets / wallpaper / tile | 15 receivers, live wallpaper service, quick-settings tile | none | out of scope, mapped in `../01_method/11_surface_map.md` |

## 4. Documents inside the repository that are worth reading before writing code

| File | Why it matters |
|---|---|
| `breezy-weather/docs/UPDATES.md` | the seven-step refresh pipeline, the cache TTL table per feature, and the exact rules for background notification behaviour |
| `breezy-weather/docs/SOURCES.md` | per-provider API notes, limits, attribution requirements |
| `breezy-weather/docs/COVERAGE.md` | 285-row table of which source covers which country |
| `breezy-weather/docs/DAY_DETAILS.md` | degree-day definitions |
| `breezy-weather/docs/TECHNICAL.md` | API keys, release management, reproducibility, how to add a source, crash-log decoding |
| `breezy-weather/docs/HOMEPAGE.md` | the product spec: what each block shows, thresholds and colour bands |
| `breezy-weather/work/DEFAULT_UNITS_PER_COUNTRY.md` | a per-country unit table, deliberately unfinished — evidence that CLDR alone is not enough |

## 5. A discrepancy worth carrying into the next port

`breezy-weather/docs/HOMEPAGE.md` says days are split at 06:00–17:59 (day) and 18:00–29:59 (night), and
that China uses 10:00–19:59. `PrecipitationViewHolder.onBindView` uses
`currentHour < 5 → previous night`, `< 17 → day`, else night. The documentation and the
code disagree by an hour, and the code is what ships.

**Rule:** when a manual and the source disagree, the source wins, and the disagreement is
worth a line in the parity ledger so the next reader does not "fix" the port back to the
documentation.

---

## 6. Commands used

```bash
for m in app data domain maps-utils ui-weather-view weather-unit; do
  echo "$m $(find $m -name '*.kt' | wc -l) $(find $m -name '*.kt' -exec cat {} + | wc -l)"
done
ls app/src/main/res | grep -c '^values-'          # locales
grep -c '<string ' app/src/main/res/values/strings.xml
grep -o 'android:name="android.permission[^"]*"' app/src/main/AndroidManifest.xml | sort -u
python3 -c "import re;x=open('app/src/main/AndroidManifest.xml').read();\
print({t:len(re.findall('<%s[^>]*android:name'%t,x)) for t in ['activity','service','receiver','provider']})"
ls data/src/main/sqldelight/breezyweather/migrations | wc -l
find . -path '*/test/*' -name '*.kt' | wc -l
```

---

## 7. The look, counted by command

The second port's first main screen had every card, every value and every tab, and looked nothing
like the original. The reason was not the data layer: it was six resource facts nobody had read. They
are cheap to gather and they decide the whole appearance, so they are measured here the same way as
the module sizes above.

```bash
cd app/src/main/res
ls drawable/weather_*.png | wc -l                                   # 85
ls drawable/weather_*.png | grep -c '_day\.png'                     # 2
ls drawable/weather_*.png | grep -c '_night\.png'                   # 2   (so 2 conditions, not 85, split)
grep -c '<item' xml/icon_provider_drawable_filter.xml               # 153
ls drawable/weather_*.png | sed 's#.*weather_##;s#_day\.png##;s#_night\.png##;s#\.png##' | sort -u | wc -l   # 83 bases
grep -H 'app:shapeAppearance' layout/container_main_*.xml | wc -l   # 12 of 15 containers
grep -h 'app:shapeAppearance' layout/container_main_*.xml | grep -c 'Corner.Full'         # 4
grep -h 'app:shapeAppearance' layout/container_main_*.xml | grep -c 'Corner.ExtraLarge'   # 8
grep -L 'app:shapeAppearance' layout/container_main_*.xml           # clock, header, uv: none
grep -l 'layout_constraintDimensionRatio="1:1"' layout/container_main_*.xml | wc -l  # 10
grep 'trend_item_width\|daily_trend_item_height\|main_title_text_size\|title_text_size' values/dimens.xml
grep -A3 'MainBlock.NumberDigit' values/styles.xml                  # 45sp, letterSpacing 0
```

| Fact | Value | Why it decides the screen |
|---|---|---|
| Card shapes | 2 in use: `Corner.Full` ×4, `Corner.ExtraLarge` ×8; 3 containers declare none | A port with one radius is wrong twice: too round in some places, not round enough in others |
| Square cells | 10 containers constrain a `1:1` block | The circular cards are circles *because* the cell is square; a neighbour rect then has to match that height |
| Block value | 45 sp, `letterSpacing` 0 | The header number is 140 sp and the titles 16 sp. Copying the scale is what makes the screen read as the same product |
| Trend geometry | `trend_item_width` 67 dp, `daily_trend_item_height` 298 dp | One fixed-width column per day, scrolled sideways under a shared chart — a vertical list is a different screen |
| Weather artwork | 85 PNGs, 83 conditions, 153 filter entries, 2 day/night splits | Icons are content: SF Symbols would collapse 83 conditions into a handful of glyphs |
| Navigation | `res/menu/activity_main.xml`: `action_edit`, `action_open_in_other_app`; no bottom navigation anywhere | The iOS look-alike move (a tab bar) is a feature the original does not have |

The two lessons for the method are in `../01_method/06_ui_port.md` ("The look is in the layouts, not
in the theme") and defects §37–§42. Everything above is XML: this section needed no decompiler.
