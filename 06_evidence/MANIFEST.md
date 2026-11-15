# Evidence manifest — what is in `06_evidence/`, and where it came from

Everything here is copied verbatim from the port repository
(`PriyanshuNaredi/weather-ios-port`, HEAD `5acc2eb` at copy time). Nothing was edited; each file
was produced by the port's own scripts or by me while doing the work.

## Screenshots (`screenshots/`)

Produced by `./07_tools/visual-audit.sh` — a UI test class excluded from normal runs that navigates
every surface and writes named captures. Taken on iPhone 16 / iOS 18.0 simulator.

| File | Surface | What it proves |
|---|---|---|
| `audit-01-empty.png` | First launch, no cities | Empty state + search affordance |
| `audit-02-search-results.png` | City search | Live Open-Meteo geocoding results, country/admin labels |
| `audit-03-forecast.png` | Forecast (top) | Hero temperature, metric grid with equal row heights, day range bars with round caps |
| `audit-04-forecast-scrolled.png` | Forecast (scrolled) | Hourly strip, 10-day list, bottom bar as a layout sibling (not an overlay) |
| `audit-05-settings-top.png` | Settings top | Units switch (Button + capsule), links with 44 pt targets |
| `audit-06-settings-bottom.png` | Settings bottom | Attribution block, both authors in the footer, diagnostics entry |
| `audit-07-cities.png` | Saved cities | Glass cards instead of `List` chrome |
| `audit-08-map-playing.png` | Map, 1.2 s after open | Radar **playing**: pause button, playhead near the left edge, frame ≈ 03:00 |
| `audit-09-map-settled.png` | Map, 13 s after open | Radar **finished**: play button, playhead at the right edge, frame ≈ 05:00 |
| `audit-10-map-temperature.png` | Temperature layer | Full-bleed colour field, five badges, none clipped or under a panel |
| `icon-on-home.png` | Simulator home screen | The app icon renders (rendered from the APK's own vector, not redrawn) |

## Documents (`06_evidence/`)

| File | Source | Why it is here |
|---|---|---|
| `CHANGELOG.md` | Port repo root | Per-change record with the reasoning at the time, not reconstructed later |
| `CODE_AUDIT.md` | Port repo root | Repo-wide audit: 6 fixed findings + finding 7 (the icon never compiled) + the "not checked" list |
| `MACOS_VERIFICATION.md` | `05_ios_port/` | The evidence table: every build/test/defect claim with the command or test that proves it |

## Recon baseline (`recon-baseline/`)

Output of `05_tools/apk-recon.sh` run against `Weather_v1.1.1.apk` (the release artifact, sha256
verified against the recorded baseline). Kept because it is the only proof that the recon script
reports the truth: the answers here were already established by hand in early 2026, so the script's
agreement is a real check rather than a self-consistent-looking output.

It rediscovered: Compose, no app-owned fragments, no DI, `HorizontalPager` ×1, `LazyColumn` ×1,
`verticalScroll` ×2, `AndroidView` + `MapView` ×1, `OkHttp` ×2, `AtomicFile` ×1,
`SharedPreferences` ×1, both entry points (`MainActivity`, `MapsKt`), package
`dev.kiankonrad.weather` v1.1.1 (code 6), 43 app classes, and a self-signed
`CN=Weather Personal` certificate. The decompiled tree (274 MB) and decoded resources (435 MB) are
not vendored.

## Second port: Breezy Weather 6.2.2 (`breezy-recon/`)

Recon output for a very different app — 1,204 app classes, 26 activities, 100 locales, 53 network
sources, plus live wallpaper and RemoteViews widgets. Kept because it is the worked example behind
`sizing` in `01_method/01_recon.md` and behind defect #17 (counting library classes as the app):

- the checksum matches the official release asset, so the analysed binary is the shipped one
- 1,097 of 1,204 classes sit in one subpackage (`sources/`), which is what turned "port the app"
  into "cut 91 % of it and port the UI"
- nine permissions have no iOS counterpart, stated as decisions rather than discovered later

`screenshots/gust-live-openmeteo.png` is the stage-5 gate from that port: live data fetched by the
ported client from Open-Meteo (Berlin: 1.6 °C, 10.0 km/h, 88 %, 1017.5 hPa), decoded by the ported
response types and rendered through the ported units — committed so the claim is checkable without
running anything.

`screenshots/gust-cards-half-rule.png` shows the half/full card rule working: six half-size cards in
three two-column rows, with rows of unequal height because one card has a second line. That ragged
height is what the Android grid does too; a SwiftUI `LazyVGrid` would stretch them level and lose it.

`screenshots/gust-shell-stage4.png` is the stage-4 gate from that port: the app target running on a
simulator with no signing identity, showing values computed by the ported units package
(humidex 31.0 °C at 25 °C / 18 °C dew point; wind chill correctly absent above 10 °C).

## Deliberately not vendored

- **The APK** (~7 MB) and the decompiled sources tree (~60 MB): the analysed artifact is described
  by checksum in `03_rea/evidence/out-signature.json` and its analysis; redistributing someone
  else's application binary is not needed to read this playbook.
- **DerivedData / build outputs**: reproducible with `05_tools/`.
- **The unsigned IPA**: reproducible with `05_tools/ipa-build.sh`; it is 1.2 MB of build output, not
  evidence of method.
- **`07_logs/` session logs**: the one excerpt that matters (radar frames 2/13 → 13/13) is quoted
  in `02_case_study/METRICS.md` with the command to re-derive it.

## Provenance rule

If a claim in this repo has no file behind it here, it is in `02_case_study/METRICS.md` as
*not measured*, or it does not appear at all.