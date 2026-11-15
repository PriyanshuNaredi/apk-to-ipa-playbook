# Stage 8 — Verification

This stage is where a port stops lying to itself. It has four instruments; all four are needed
because each one is blind to something the others see.

| Instrument | Sees | Blind to |
|---|---|---|
| Logic suite (host) | Data layer, codecs, projections, cache policy | Anything involving a view |
| UI suite (simulator) | Navigation, gestures, state transitions, hit targets | Layout quality, visual parity |
| Visual audit (scripted captures) | Layout, density, colour, clipping | Behaviour over time |
| Metrics (CPU, memory, timings) | Invisible loops, leaks, drift | Correctness |

## The suites

**Logic suite** — runs in under a second on the host, so it is the loop you actually use. Keep it
free of UIKit/SwiftUI so it stays fast. Recorded network payloads only.

**UI suite** — XCUITest, driven by accessibility labels, not coordinates. Three habits make it
survive contact with a live app:

1. `-resetState` launch argument, so state never leaks between tests.
2. Wait on *state* (`app.buttons["Pause radar"].waitForExistence(timeout:)`), never `sleep`.
3. One behaviour per test, named after the behaviour (`testPageIndicatorIsCentred`).

**Visual audit** — a separate UI test class that walks every surface and writes named PNGs
(`audit-01-empty` … `audit-10-map-temperature`). It is excluded from normal runs
(`-skip-testing:`) so it does not slow the inner loop, and the script fails loudly if fewer than
the expected number of captures appear — an audit that silently exports nothing is worse than none.

**Metrics** — after launch, measure. Numbers that mattered here: idle CPU 100% → 5.7%; tile cache
96 tiles → 48 MiB disk; radar 13 frames ≈ 10 s.

## Reading evidence instead of guessing

When behaviour is time-dependent (animation, refresh, timeout), the app's own diagnostics log is
the honest witness. This port shipped a `DiagLog` that writes `session-<epoch>.log` into
Application Support, then used it to prove the radar plays `frames 2/13 … 13/13` and stops:

```
xcrun simctl get_app_container <udid> dev.kiankonrad.weather data
# → Library/Application Support/weather-diag/session-*.log
```

That turned "the radar probably works" into a line of text with timestamps.

## Test the defects, not the happy path

A port's tests should read like the defect list. In this port:

| Defect | Test that now guards it |
|---|---|
| Radar looked already-played | `testRadarPlaysOnceFromTheStartWhenMapOpens` |
| Location button could hang forever | `testUseMyLocationTerminates` (6.9 s, with a fixed simulator coordinate) |
| Bar taps swallowed by map preview | `testMapPanAndZoomStaysResponsive`, `testAddCityButtonOpensSearch` |
| Dots 24 pt off centre | `testPageIndicatorIsCentred` |
| Units switch inert | settings/units UI test |
| Legal texts missing from bundle | licence-list UI test |

## The clean-clone run

Verification is not finished when it passes in your working copy. Clone the repo to a fresh
directory, build with a *different* derived-data path, launch, and measure:

```
git clone <repo> /tmp/verify-clone && cd /tmp/verify-clone
DERIVED=/tmp/dd-verify ./07_tools/macos-build.sh
ps aux | grep "[W]eatheriOS.app/WeatheriOS" | awk '{print $3}'
```

This catches the whole class of "works because of local state": build settings only present in
your Xcode UI, a generated file you forgot to commit, a cache in DerivedData.

## Exit gate

- Both suites green from a clean clone, with a non-zero test count asserted.
- Visual audit exports the expected number of named captures.
- Idle CPU measured and under budget.
- Every defect in the case study has a guarding test, or is listed as untestable with the reason.