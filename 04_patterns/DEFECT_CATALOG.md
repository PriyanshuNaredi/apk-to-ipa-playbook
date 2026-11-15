# Defect catalog — the failures that recur across ports

Each entry: the symptom you will see, the cause, the fix, and **the test to write first**. These
are ordered by how much time they cost in this port, not by how interesting they are.

---

## 1. State written during evaluation → invalidation loop

**Symptom:** app is warm, battery drains, idle CPU at 100%, scrolling feels heavy but nothing is
visibly wrong. Every functional test passes.

**Cause:** a model writes back into its parent while being constructed or evaluated
(`init` calling `onChange`/`onWeather`, `body` mutating state, `onChange` of a derived value
writing its source).

**Fix:** forward results from `.task`/`.onChange`, never from `init`. Make the child own its data
and the parent observe it, not the reverse.

**Write this test:** none — this class is invisible to tests. **Instrument it instead:** assert
idle CPU < 6% in the quality checklist, measured 30 s after launch.

---

## 2. `@ViewBuilder` treated as a container

**Symptom:** a panel/card renders as N stacked cards, one per child. Everything is "almost right".

**Cause:** `@ViewBuilder var content: some View` returns a *tuple*; modifiers applied at the call
site apply to each element. Compose's `Column` is a container and does not do this.

**Fix:** wrap the builder inside the card: `VStack(alignment: .leading, spacing: 0) { content }`.

**Write this test:** a visual audit capture of any panel with ≥2 children.

---

## 3. Overlay instead of sibling (hit-testing)

**Symptom:** buttons sometimes do nothing — specifically when content behind them is interactive
(map, scroll view). Retrying works.

**Cause:** the original's chrome is a *layout sibling* of the content; the port implemented it as an
overlay in a `ZStack`. Two interactive layers compete.

**Fix:** restore the structural relationship (sibling in a `VStack`/`HStack`), not a z-index hack.

**Write this test:** a UI test that taps the control after interacting with the content behind it.

---

## 4. `withTaskGroup` used as a timeout

**Symptom:** a spinner never resolves; the button stays disabled forever. Code looks correct.

**Cause:** `withTaskGroup` awaits **all** children, so racing an operation against
`Task.sleep` never returns until the slow child finishes. Combined with an unchecked
`CheckedContinuation`, cancellation does not propagate either.

**Fix:** `withTaskCancellationHandler`, resolve the continuation from `onCancel`, resolve any stale
slot before storing a new one.

**Write this test:** "operation terminates within N seconds" (use a fixed simulator location so
success is deterministic).

---

## 5. Continuation stored outside the lock, single-shot API

**Symptom:** the second attempt at an action hangs permanently; the first always works.

**Cause:** a one-shot callback (permission dialog, delegate) resumed a continuation that a second
caller had overwritten or stored after unlocking — so nobody resumed it.

**Fix:** a queue of waiters, all resumed from the single callback; issue the request only when the
queue was empty.

**Write this test:** call the action twice concurrently; assert both resolve.

---

## 6. HTTP 200 with an error body

**Symptom:** a map shows "API KEY REQUIRED" (or a grey placeholder) instead of tiles; no error is
thrown, no error state appears.

**Cause:** tile providers answer keyless requests with a *valid image* explaining the problem.

**Fix:** verify tile content, not just status, during bring-up; switch to a keyless provider and
record the attribution obligation.

**Write this test:** fetch one tile and assert it is not the placeholder (size/colour check), or a
visual capture that a human/vision check confirms shows a map.

---

## 7. Empty build setting that looks like a value

**Symptom:** the app ships with a blank icon. Nothing warns.

**Cause:** `ASSETCATALOG_COMPILER_APPICON_NAME = ""` — an empty name is not an invalid one, so
`actool` simply produces no `Assets.car`.

**Fix:** set the real name; inspect the built bundle (`Assets.car` present, `AppIcon` rendition
inside) as part of release verification.

**Write this test:** release script asserts `Assets.car` exists and contains an `AppIcon` rendition.

---

## 8. Numeric JSON ids read as strings

**Symptom:** identity/caching degrades silently; "the app forgets things" much later.

**Cause:** `row["id"] as? String` on a JSON number → always `nil` → fallback key (`"lat,lon"`).
Kotlin's `optString` stringifies numbers, so parity differs.

**Fix:** stringify numbers explicitly in the decoder; unit-test with a recorded payload that
contains numeric ids.

---

## 9. Cache maintenance that scales with store count

**Symptom:** cache writes get slower as the cache grows; a scroll stutters.

**Cause:** recomputing total size by sorting the whole index on every `store`, or evicting by
re-sorting.

**Fix:** maintain a running total; evict only when over budget.

**Write this test:** store N tiles against a byte budget, assert the surviving set and that
`store` does no full-index sort (or just assert O(1)-ish timing on a large index).

---

## 10. Badges/labels placed by data coordinates

**Symptom:** labels sliced by screen edges, hidden under translucent panels, overlapping each other
or a marker.

**Cause:** the original drew a label at every Nth sample wherever it landed; the port copied that.

**Fix:** three rules — (a) reject labels whose rect leaves the safe area, (b) reject labels
intersecting *measured* chrome frames (`PreferenceKey` + `GeometryReader`, never hard-coded insets),
(c) greedy minimum spacing so they never crowd. Exclude the primary marker too.

**Write this test:** visual capture with a vision-model question ("is any badge clipped or under a
panel?").

---

## 11. Faithful port of a confusing behaviour

**Symptom:** a feature "works" but reads as broken: a slider parked at maximum, an animation that
looks finished before it starts.

**Cause:** the original's initial state is a product accident (e.g. "follow the latest frame" for a
playback timeline).

**Fix:** choose the comprehensible behaviour, then record it in the parity ledger with a test that
asserts the *new* behaviour. Never leave it undocumented.

**Write this test:** assert the visible state at open (button label, slider position) and after the
sequence completes.

---

## 12. Silent zero-test runs

**Symptom:** CI green, no tests executed.

**Cause:** generated project not regenerated after adding a test file; the new file is not in the
target. Also: a filter that matches nothing.

**Fix:** regenerate unconditionally before test runs; assert the executed count is > 0 in the test
script itself.

---

## 13. `pipefail` + `grep -q` false failures (and false passes)

**Symptom:** a verification step fails on a correct artifact — or, worse, passes on a broken one.

**Cause:** `producer | grep -q` exits at the first match; the producer takes SIGPIPE; under
`set -o pipefail` the pipeline reports failure even though the match succeeded.

**Fix:** capture output into a variable, then compare strings (`[[ "$out" == *pattern* ]]`).

**Write this test:** run the verification against both a correctly-unsigned and a
deliberately-signed fixture; both outcomes must be correct.

---

## 14. Formatter/date allocation inside render paths

**Symptom:** scrolling a long list is heavy; profile shows `DateFormatter` init.

**Cause:** formatting per row with a fresh formatter.

**Fix:** cache formatters by format string; or precompute strings in the projection layer.

**Write this test:** not worth a test — grep for `DateFormatter()` and keep it out of views.

---

## 15. Single-source-of-truth violations in paging

**Symptom:** dots and header disagree with the visible page; state lands on the wrong page after
add/remove.

**Cause:** the port kept its own index beside the framework's scroll position, and keyed pages by
array index instead of entity id.

**Fix:** key by id; derive the index from the pager (or bind the pager to a single selected id).

**Write this test:** add a city, remove the first, assert the visible page and the indicator agree.

---

## 16. `BUILD SUCCEEDED`, app will not install (missing `CFBundleVersion`)

**Symptom:** `xcodebuild` reports success; `simctl install` fails with
`The application's Info.plist does not contain a valid CFBundleVersion` (NSPOSIXErrorDomain, code 22).

**Cause:** `GENERATE_INFOPLIST_FILE: YES` plus an explicit `info: path:` in the XcodeGen spec — the
plist is written from `info.properties`, so no version keys are present.

**Fix:** drop `GENERATE_INFOPLIST_FILE`; state `CFBundleShortVersionString` and `CFBundleVersion`.
Assert them in the build script so a green build cannot mean an uninstallable app.

**Write this test:** the build script fails if `PlistBuddy :CFBundleVersion` is missing.

---

## 17. Sizing the port from the wrong class count

**Symptom:** nobody agrees on the estimate; one person says "2,000 lines", another says "weeks".

**Cause:** a decompiled tree contains the app **and** every bundled library. Counting them together
reported 19,271 classes / 3.85 M lines for an app whose own code is 43 classes — and made framework
heuristics fire on code the author never wrote ("Fragments found", "DI found" on a pure-Compose app
with no DI).

**Fix:** scope every count to the manifest's own package, and print the subpackage breakdown — the
shape decides the schedule. On a 1,204-class app, 1,097 of those classes were 53 weather-provider
integrations, i.e. 91 % of the code was *one feature that is also the one you must cut*.

**Write this test:** recon output must state app classes, bundled classes, and the top subpackages
separately (`05_tools/apk-recon.sh` does).

---

## 18. A script that reports success after a failure

**Symptom:** the build script prints `OK: built` and installs a **stale** app. No error anywhere.

**Cause:** `xcodebuild ... | grep -E "error:|BUILD SUCCEEDED"` — the pipeline's exit status is
grep's, so a failed build is invisible. Under `set -o pipefail` it would fail *the other way*
(a successful build with a SIGPIPE'd grep looks failed). Both directions are wrong.

**Fix:** capture the log, branch on the command's own status, then inspect the log:

```bash
BUILD_LOG=$(mktemp)
if ! xcodebuild ... build > "$BUILD_LOG" 2>&1; then
  grep -E "error:" "$BUILD_LOG" | head -20; echo "FAIL: build failed" >&2; exit 1
fi
grep -c "BUILD SUCCEEDED" "$BUILD_LOG" >/dev/null || { echo "FAIL: no success marker" >&2; exit 1; }
```

The general rule, now learned twice on two different ports: **never let a text filter decide
whether a command succeeded.** Capture, check status, then filter for human reading.

**Write this test:** break the build on purpose once (add `let x: Int = "s"`), run the script, and
confirm it fails.

---

## 19. A "helpful" data transform that shifts a time series

**Symptom:** everything looks right, but the rain nowcast is early. In this case
the payload had 1,632 fifteen-minute steps and the port rendered 1,613.

**Cause:** `values.compactMap { $0 }` to drop nulls. The array is a **time series**:
dropping a gap moves every later value to an earlier timestamp. Upstream keeps one
entry per step with a nullable value, exactly so gaps stay gaps.

**Rule:** for a time series, never filter, compact, dedupe or sort. Keep alignment
with the time axis and make the value optional. (Sorting by value is the same bug
in a different costume.)

**Write this test:** assert the *count equals the timestamp count* and that the
fixture contains at least one null — otherwise the test cannot catch the bug.

---

## 20. SwiftUI: a container identifier eats its children's identifiers

**Symptom:** a UI test waits 30 s for `header.temperature` and fails, while the
same build works by hand. Dumping `app.debugDescription` shows the temperature
element carrying the *container's* identifier.

**Cause:** `.accessibilityIdentifier("card.header")` on a `VStack` propagates down
the subtree and overwrites descendants that set their own.

**Fix:** declare the container first —
`.accessibilityElement(children: .contain).accessibilityIdentifier("card.header")`.

**Technique worth keeping:** when a UI query fails, print `app.debugDescription`
from a throwaway test before changing any assertions. It found this in one run,
where guessing had already cost two. Keep it in a file named to sort last
(`ZZDebugTree.swift`) and delete it afterwards.

---

## 21. A "reasonable" aggregation that silently differs from upstream

**Symptom:** the air-quality number is wrong on some days, right on others, and
nobody can say why. Comparisons against the Android app disagree intermittently.

**Cause:** the headline index is the max over **four** pollutants (O3, NO2, PM10,
PM25), not all six. CO and SO2 are displayed but never drive the number. A port that
"obviously" maxes every pollutant is right most of the time and wrong on any day
when CO or SO2 is the extreme value.

**Rule:** when upstream has a derived scalar (an index, a severity, a level), port
the *exact set of inputs* it uses and write a test where an excluded input is
deliberately extreme. Here: `AirQuality(pm25: 5, co: 10_000)` must still index 20.

**Related smell:** interpolation that *clamps* above its last breakpoint. Upstream
continues linearly (300 µg/m³ PM2.5 → 500, not 250). A clamp looks safer and hiddenly
diverges on polluted days — the days a weather app is most likely to be looked at.

---

## 22. Dictionary order in a test makes it flaky, not the code

**Symptom:** the same test passed three runs in a row, then failed in the combined
suite. No code change in between.

**Cause:** `mapped.values.first` — dictionary iteration order is unspecified. In one
process the "first" value had data; in another it was an all-nil hour.

**Rule:** never take `.first` / `.last` on a Dictionary or Set in a test. Name the
element you mean (`mapped[mapped.keys.min()!]`). A test that can pass by luck will,
and then it will fail in CI on someone else's branch.

---

## 23. A card that is internally consistent and still lies

**Symptom:** the nowcast card's title said "Rain starting" over a strip of empty bars. Every
number in it was correct.

**Cause:** two independently correct decisions that do not compose. The title is derived from the
**whole** series (first and last step), while the chart drew a **fixed 2-hour window**. Rain seven
hours away satisfies the title and leaves the window empty.

**Fix:** when rain falls outside the drawn window, start the window just before the first wet step
and label it ("from 09:15"). The card then states the same thing in both places.

**Generalisation:** for any card with a headline plus a picture, assert that the headline's claim is
*visible in the picture*. A UI test cannot see this, so make it a unit test on the windowing
function: `window(maxSteps:)` must contain at least one non-zero value whenever the state is not
`.none`.

**Related:** the same card had auto-scaled its bars to the window's peak, which makes a drizzle fill
the card. Upstream uses an absolute scale topping out at 15 mm/h. Auto-scaling a chart to its own
data hides the one comparison the user cares about.

---

## 24. Accessibility identifiers, again — this time from `NavigationLink`

**Symptom:** wrapping cards in `NavigationLink` made every card identifier inside them vanish. Two
tests that had passed for hours started failing with "card missing".

**Cause:** same rule as defect 20, one level up. A link is a button, and a button is one
accessibility element; identifiers inside it are no longer individually addressable.

**Fix:** `.accessibilityElement(children: .contain)` on the link as well.

**Also seen:** a container identifier on a list of rows merged them into a single identifier string
(`daily.row.0-daily.row.0-daily.row.1-…`). If child identifiers are the useful handles, do not put an
identifier on the parent at all.

**Rule of thumb:** identifiers belong on leaf-ish views. Every container you name either eats or
merges its descendants.

---

## 25. Code that is correct and a screen that is still wrong

**Symptom:** the hourly detail chart drew correctly, and the min/max labels sat underneath the line.

**Cause:** nothing in the code. Two text labels were placed at fixed coordinates that the data
happened to occupy.

**Fix:** reserve a gutter for the labels and draw the series inside the remainder.

**Practice:** look at the rendered screen with a vision model after building any canvas or custom
layout. Unit tests cannot see overlap, and "it compiles and the numbers are right" is not the same
claim as "you can read it". This is the same lesson as defect 20's advice to dump the accessibility
tree: assert what a human would see, using the tool that can see.

---

## 26. Empty is three different facts

**Symptom:** the pollen card showed "0" for a city in the United States. The number was not wrong so
much as meaningless: there is no pollen product there.

**Cause:** a coverage-gated API. Upstream gates the request on a bounding box; porting the request
without the gate requests variables the service cannot answer, gets empty arrays, and renders them as
"zero".

**Rule:** for every piece of data, distinguish **absent** (no value), **zero** (a measured zero) and
**not covered** (this product does not exist here). They need different words on screen, because a
user acts on them differently. Model it as `hasData` vs `value`, not as a single number.

**Checklist item:** whenever a source documents a coverage area, a resolution, or a "not available
for this region" note, that note belongs in the port as a gate and as UI copy.

---

## 27. A flag the tests pass and the app ignores

**Symptom:** a unit assertion passed in one run and failed in the next. Nothing about the code had
changed.

**Cause:** the UI tests launched with `-resetState`, and nothing implemented it. Each run inherited
whatever the previous manual session had saved, so the "default" unit was whatever was last chosen.

**Fix:** implement the flag where state is loaded (`AppState.init`), and clear every persisted key,
not just the one you remember.

**Rule:** a test-only launch argument is production code. Assert it does something (a test that sets
a non-default value, relaunches without the flag, and sees the default again).

---

## 28. The header colour that was decided before there was a header

**Symptom:** the navigation title was black on a night-coloured background, so it was invisible.

**Cause:** `.toolbarColorScheme()` was evaluated while the weather was still `nil` and never
re-evaluated, while the header text underneath recomputed from the loaded data. Two colour decisions
with different lifetimes.

**Fix:** derive both from one value and apply it explicitly (`.foregroundStyle`, `.tint`), rather than
relying on a modifier that snapshots its input.

**Checklist item:** if a screen has two places that must agree, make them read the same expression.
"Probably the same" is how a black-on-black title ships.

---

## 29. Night with a sun in it

**Symptom:** the "Nighttime" half of the details panel showed a sun icon and "Clear".

**Cause:** one symbol table for day and night. The label was computed from the hour, the picture from
the weather code.

**Rule:** any label that names a period must colour, icon and format itself from that same period.
This is the screenshot equivalent of defect 23 (a card whose title and picture disagree), and it is
caught by looking, not by tests.

---

## 30. Judging a test run by its text

**Symptom:** `macos-tests.sh` reported failure on green runs, roughly every time.

**Cause:** it decided success by grepping the log for `error:`. XCTest logs
`Failed to scroll to visible … error: Error kAXErrorCannotComplete` when a tap falls back to another
path — a line that appears in successful runs.

**Fix:** judge by the exit code *and* the tool's own verdict (`TEST SUCCEEDED`), and use the text only
to explain a failure that already happened.

**Rule:** this is defect 18 again (a text filter deciding success), two layers up. When you write a
script that watches another tool, ask which line means "the tool said yes", and use that one.

---

## 31. One provider, hardcoded — and no seam where the second one goes

**Symptom:** the port works, and three unrelated things are subtly wrong: a coverage gate looks
arbitrary ("why does pollen vanish in New York?"), one failed request blanks a whole card, and there
is no way to try a second API without editing the client.

**Cause:** the first provider was wired directly (`OpenMeteoClient` called from the store) instead of
behind a `WeatherProvider` protocol with `supportedFeatures`, `isSupported(at:)` and `priority`.
Every per-feature rule then has to be invented ad hoc at the call site.

**Fix:** a protocol with one implementation. ~80 lines. See `../01_method/12_source_architecture.md`.

**Write these tests first:** resolver picks the highest-priority provider; resolver returns `nil`
when nothing covers the feature — the second test is the one whose absence turns "not covered"
into "0".

**Rule:** a hardcoded provider is a scope decision; a hardcoded *call site* is a future refactor.

---

## 32. One timestamp for six features

**Symptom:** "updated 2 min ago" while air quality is an hour old; or pollen refetched every time you
open a card; or the whole screen reloads because the nowcast expired.

**Cause:** the store remembers one `lastUpdated` for the whole weather object. Upstream has six
(forecast, current, air quality, pollen, minutely, alerts) and a validity table that even depends on
whether the payload has content.

**Fix:** per-feature `Fetched<Value>` wrappers plus a `CachePolicy` value; stale-per-feature, 5 km
coordinate invalidation.

**Write this test:** two minutes later, same place → no network call; six minutes later → one call;
moved 6 km one minute later → one call.

---

## 33. Defaults hardcoded to the developer's locale

**Symptom:** `en_US` users see `22°C` and `21 km/h` until they open settings. Nobody on the team
notices: the simulator is metric.

**Cause:** `var temperatureUnit = .celsius` instead of a default derived from `Locale`.

**Fix:** derive all five families from `Locale.current` (`temperatureUnit`, `measurementSystem`,
`region`), including the hand-written country lists upstream keeps for wind speed and pressure.

**Write this test:** the eight-locale loop in `../01_method/14_units_and_locale.md` §4. It fails on the
first run and takes two minutes to fix.

---

## 34. Plurals made with string concatenation

**Symptom:** "1 updates failed", or correct English and broken Polish.

**Cause:** `"\(n) update\(n == 1 ? "" : "s") failed"`.

**Fix:** plural variants in the String Catalog; English needs two forms, Polish four, Arabic six.

**Write this test:** none — **grep** for `? "" : "s"` and `\(count) \(` in view code.

---

## 35. `daily[0]` is "today"

**Symptom:** between local midnight and the first refresh, the header shows yesterday's high; the
"today" detail page opens on yesterday; the date selector highlights the wrong row.

**Cause:** daily entries are dated at local midnight, and the first row may be yesterday. Upstream's
rule is *the first entry newer than 24 h ago*.

**Fix:** a computed `todayIndex` in the model with the 24 h rule, used by every view.

**Write this test:** entries `[2024-05-01T00:00Z, 2024-05-02T00:00Z]`, now `2024-05-02T00:10Z`,
expect `todayIndex == 1`.

---

## 36. Porting the document instead of the code

**Symptom:** the port disagrees with the app on one boundary — e.g. the day/night split is 06:00 in
the port and 05:00 in the shipped app.

**Cause:** the upstream manual (`breezy-weather/docs/HOMEPAGE.md`) and the upstream code
(`PrecipitationViewHolder.onBindView`) disagree by an hour, and the manual was read first.

**Fix:** the code wins, every time. Record the disagreement in the parity ledger so the next reader
can see it was a decision, not an oversight.

**Rule:** documentation describes intent at some past commit; the APK describes behaviour.

---

## 37. Card shapes invented instead of read

**Symptom:** the port has a consistent, pleasant corner radius on every card and looks nothing like
the original, which has **exactly two** shapes — a circle and one rounded size.

**Cause:** the shape is not in the theme, it is an attribute on each container. In the upstream
measured for this playbook, 15 `res/layout/container_main_*.xml` files carry 12 `app:shapeAppearance`
declarations: 8 `Corner.ExtraLarge`, 4 `Corner.Full`, and 3 declare none at all. A theme-level
`MaterialTheme.shapes` reading is the wrong file.

**Fix:** extract the shape attribute per container into a table *before* writing any card view, and
make the card view take the shape as a parameter. Anything without an attribute keeps its own
treatment — the header, clock and UV blocks in the same app are neither.

```bash
# the whole table, in one command
grep -H "shapeAppearance" res/layout/container_main_*.xml | sed 's#.*container_main_##'
grep -L "shapeAppearance" res/layout/container_main_*.xml
```

**Related:** a circle only looks like a circle because its inner block is constrained square
(`app:layout_constraintDimensionRatio="1:1"` on 10 of those containers). Port the square cell as a
square cell, or a rounded rectangle next to a circle in the same row will not stand level.

**Write this test:** a Swift unit test that maps every card kind to a shape and asserts the count
per shape equals the number found in the layouts.

---

## 38. Platform icon set substituted for the original's artwork

**Symptom:** every card has the right content and a wrong picture. Conditions that exist
(`partly_cloudy`, `haze`, `sleet`) have no SF Symbol, so they collapse into three or four glyphs and
the screen loses its information density.

**Cause:** the icons were treated as decoration. Upstream computes a resource name —
`Constants.getResourcesName(code) + "_" + (daylight ? "day" : "night")` — and resolves it through a
filter XML that maps missing variants onto shared artwork. 153 `<item>` entries, 85 PNGs, 83 distinct
conditions, and only **2** of those conditions (`clear`, `partly_cloudy`) actually have separate day
and night files.

**Fix:** copy the drawables and port the *lookup* as code. Then make a test resolve every name the
lookup can produce against the bundled files, so a condition with no artwork fails the suite instead
of drawing a fallback symbol in the shipped app:

```swift
for code in WeatherCode.allCases {
    for day in [true, false] {
        let name = WeatherIcons.name(for: code, day: day)
        XCTAssertNotNil(Bundle.main.path(forResource: name, ofType: "png"), name)
    }
}
```

**Licence note:** redistribute the artwork only alongside the upstream licence and a statement of
what was changed — see `01_method/09_release.md`.

**Write this test:** the resolver test above; it is the cheapest possible guard and it caught the
day/night split rule in this playbook's second port.

---

## 39. Trend block built as rows

**Symptom:** the daily card is a vertical list of days. The original is a sideways strip: five or six
columns of weekday, date, icon, high, low, all scrolling together over one chart.

**Cause:** the container name (`RecyclerView` with a `LinearLayoutManager`) does not say which axis,
and the columns look like rows in a screenshot until you count them.

**Fix:** read the dimens. `trend_item_width` 67dp, `daily_trend_item_height` 298dp: one column per
day, fixed width, under a single shared chart. On iOS that is `ScrollView(.horizontal)` around an
`HStack` of 67 pt columns with the chart beneath — not `ForEach` over rows.

**Write this test:** a UI test that asserts two or more day headers exist *and* that the container
scrolls horizontally (swipe, then assert the first day's x origin moved).

---

## 40. Platform chrome the original never had

**Symptom:** the port is recognisably an iOS app in a weather costume: bottom tab bar, sheet
navigation, back arrow where the original has a hamburger.

**Cause:** "how do people navigate on this platform" was answered before "how does *this app*
navigate". The original's main activity has an up button, an edit action and an overflow menu — no
bottom navigation of any kind.

**Fix:** inventory upstream's navigation from `res/menu/` and the activity layout *before* choosing
an iOS container, and write the inventory into the parity spec. Removing a tab bar afterwards is
cheap; removing the habit is not.

**Write this test:** `XCTAssertEqual(app.tabBars.count, 0)` when upstream has none. A negative
assertion is odd-looking and it is the only thing that stops the chrome coming back.

---

## 41. A bar colour that arrives after the bar is built

**Symptom:** the app bar renders white/blank while every other surface is correct, and toolbar items
are invisible because their tint was chosen for the weather colour.

**Cause:** SwiftUI evaluates `toolbarBackground` when the navigation container is built. A colour
derived from data loaded later — the current condition, in this case — is captured as nil and never
re-applied, even when it is stored in `@State` and updated from `onChange`. (`toolbarBackgroundVisibility`
only exists from iOS 18, and the deployment target was 17.)

**Fix:** choose a bar treatment that does not depend on network data — a material blur over the same
backdrop reads correctly at every scroll offset — and record the deviation instead of fighting the
framework. If the bar must follow the weather, resolve the colour *before* first paint (cache the
last condition), or require iOS 18 and set visibility explicitly.

**Write this test:** a screenshot with one specific question ("is the bar the weather colour?"). No
unit test can see this.

---

## 42. UI tests that cannot see the thing they assert

**Symptom:** tests fail on identifiers that exist in the code, or pass while the screen is wrong.

Four separate causes, all seen in one port:

1. **A `NavigationLink` collapses its subtree.** Inner identifiers disappear once the card is a link;
   assert on the link, or move the identifier to a leaf outside the link.
2. **`.accessibilityIdentifier` on a plain container is invisible.** A container is not an element
   until `.accessibilityElement(children: .contain)` precedes the identifier.
3. **`app.navigationBars.buttons.firstMatch` is unscoped.** With a sheet open it matched the
   presenter's bar underneath, and the tap failed with `kAXErrorCannotComplete` on a scroll action.
   Scope every query to a named bar.
4. **A `Menu` in a toolbar is unreliable to tap.** Replace it with a `Button` opening a
   `confirmationDialog`; the identifier then behaves like any other button.

**Write this test:** dump `app.debugDescription` to a file from a throwaway test the first time a
query disagrees with the source. It answers "does the element exist" in one run instead of five.

---

## 43. The background approximated instead of ported

**Symptom:** every weather condition looks the same. The screen is recognisably the app —
cards, numbers, wording — with a generic wash behind it. Rain, snow and a clear noon are
indistinguishable at a glance.

**Cause:** the backdrop was treated as decoration. In the measured upstream it is two
things: a **gradient asset per condition** (`res/drawable{,-night}/weather_background_*.xml`,
12 files plus 11 night-theme overrides, three stops each, angle 270) and a **geometric
scene** drawn over it by an animation implementor (rotating squares for the sun, breathing
circles for cloud, 75 rounded streaks for rain, 50 circles for snow, 160 thin gusts for
wind, 50–70 stars and 10 meteors at night, a violet flash for thunder). None of that is a
blurred circle, and none of it is in the theme.

**Fix:** port both halves as *data*, not as drawing code:

1. Enumerate the background drawables by (kind, daylight) and the `-night` qualifier; pin
   every stop colour in a test.
2. Read each implementor for counts, colours, sizes and speeds — they are constants at the
   top of each class (`RAIN_COUNT = 75`, `SNOW_COUNT = 50`, `HAIL_COUNT = 51`,
   `WIND_COUNT = 160`, `SUN_POSITION = 0.5`, alphas `0.16/0.08/0.04`).
3. Make particle positions a function of time (`position = f(seconds)`) instead of a stepped
   simulation. Nothing drifts, nothing leaks, and pausing is free.
4. Measure the frame rate. 30 fps cost ~10% CPU in the simulator and bought nothing visible;
   20 fps measured ~5.5% and looks the same. Ship the setting that pauses it.

**Write this test:** one per number. Gradient stops hex for hex, particle counts, the sun's
three alphas, and a determinism test that the same seed produces the same scene.

---

## 44. A test count that ignored half the tests

**Symptom:** the CI gate "a run that executes nothing fails" passes, and the reported test
count stops moving when new tests are added.

**Cause:** the script scraped one framework's summary line. XCTest prints
`Executed N tests`; Swift Testing prints `Test run with N tests passed`. Summing only the
first silently excluded every `@Test` suite — 7 of 106 tests here, including the new ones.

**Fix:** parse both, add them, and print the split (`106 (99 XCTest + 7 swift-testing)`) so
the next reader can see which layer is which. Fail if the sum is 0.

**Write this test:** inject a deliberate failure in each framework once, and confirm the
gate catches both.

---

## 45. The tag build that published nothing

**Symptom:** every push to `main` is green; the first tagged build fails at the last step
with `403 Resource not accessible by integration`. There is no release, so the install
instructions point at a download that does not exist.

**Cause:** `GITHUB_TOKEN` is **read-only by default** on repositories created recently.
Building and uploading the workflow artifact is a read; creating a release and attaching
an asset is a write.

**Fix:** declare it, and refresh the tag afterwards, because a tag build runs the workflow
*at that tag*, so fixing the file on `main` does not fix the run you already queued:

```yaml
permissions:
  contents: write
```

Then move the tag onto the fixed commit (`git tag -f vX.Y.Z && git push -f origin vX.Y.Z`)
and confirm the asset exists — `GET /repos/{owner}/{repo}/releases` and check `assets[].size`,
not just the green tick.

---

## 46. A law that answered about a different two hours

**Symptom:** a summary sentence and a chart that contradict each other. Ours read
"Precipitation soon — expected to start at 2:15 AM" above a chart whose axis ran
17:30–19:30 and whose bars were all zero. Both halves were "ported correctly".

**Cause:** the law and the chart were ported from the same upstream file, but the *series*
was not. Upstream's providers hand it a list that begins **now** and covers about two
hours; the replacement API hands over a list that begins at **local midnight** and runs for
days. "Is the first step wet?" therefore asked a question about 00:00, and "the first wet
step" found rain nine hours away. Nothing in either port was wrong in isolation.

**Fix:** clip the series to the rendered span before applying any law to it, in one place:

```swift
func relative(to now: Date, span: TimeInterval) -> Series {
    let inWindow = steps.filter {
        $0.date.addingTimeInterval(stepInterval) > now && $0.date < now.addingTimeInterval(span)
    }
    return Series(steps: inWindow.isEmpty ? [steps.last].compactMap { $0 } : inWindow)
}
```

Two properties worth keeping: the sentence and the chart can no longer describe different
windows, and a card with nothing to say still has an axis and says "none" rather than
disappearing.

**The general rule:** when the replacement data differs from the original's in *origin,
length or resolution*, every law that reads the series needs a clip or a resample, and the
clip belongs in the data layer where a test can reach it. This one cost a full visual
review cycle because the empty chart looked like a drawing bug.

**Also in the same card:** a threshold label drawn above its line is clipped when the line
is the topmost one; flip the anchor within ~14 pt of the top of the plot.

**Write this test:** a series that is dry inside the window and wet outside it must read
"no precipitation", not "starting soon".

---

## 47. One card, two clocks, and the port only read one of them

**Symptom:** a block reads "—" or a number for the wrong period, but only for a couple of
hours a day — so it passes every daytime screenshot comparison.

**Cause:** the upstream card split the same data twice with different hours and never said
so. `PrecipitationViewHolder` chose *which half of the day to describe* at **05:00 and
17:00**; `CommonConverter.getHourlyListByHalfDay` chose *which hours are summed into that
half* at **06:00 and 18:00** (it shifts every hour by six hours and calls anything before
noon "day"). The port read the first pair of hours, applied it to both jobs, and resolved
the night window forwards. At 03:00 it therefore summed 17:00→05:00 of the day that was
just beginning, found no hours, and showed a dash — describing a night still to come
instead of the one just gone.

**Fix:** port every split you find, even when two of them disagree:

```swift
// which half is shown
func period(hour: Int) -> Period { (5...16).contains(hour) ? .day : .night }
// which hours are summed, and a night belongs to the evening it starts in
func window(_ period: Period, at now: Date) -> (Date, Date) {
    switch period {
    case .day:   return (six(now), eighteen(now))
    case .night:
        let start = hour(now) < 6 ? previousEvening(now) : thisEvening(now)
        return (start, start + 12.hours)
    }
}
```

**How to find it:** grep the upstream for **every** constant that looks like a boundary or a
threshold and note which file each lives in. Two files with different numbers for the same
concept is the signal. Also check whether the comparison is `==` or `>=`: upstream compared
a part to its total with `==`, so a half whose rain and snow add up to *less* than its total
stays generic, which `>=` silently changes.

**Write this test:** a case at 03:00, a case at 05:30, a case at 17:30, and both window
boundaries — the two disagreeing hours are exactly the ones a casual test misses.

---

## Cheap sweep before you call a port done

```bash
grep -rn "DateFormatter()" Sources | grep -v cache      # 14
grep -rn "init(" Sources | xargs grep -l "onChange\|onWeather"   # 1
grep -rn "while true\|withTaskGroup" Sources            # 4
grep -rn "ZStack" Sources | wc -l                        # 3 (each is a hit-testing suspect)
grep -rn "as? String" Sources                            # 8
grep -rn '= \.celsius\|= \.kilometrePerHour\|= \.hectopascal' Sources   # 33 (want 0 in defaults)
grep -rn '? "" : "s"' Sources                           # 34
grep -rn 'daily\[0\]\|hourly\[0\]' Sources              # 35
grep -rn 'struct .*: WeatherProvider' Sources           # 31 (want >= 1)
ps aux | grep "[W]eatheriOS.app/WeatheriOS" | awk '{print $3}'   # 1
```