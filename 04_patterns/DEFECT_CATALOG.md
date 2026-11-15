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

## Cheap sweep before you call a port done

```bash
grep -rn "DateFormatter()" Sources | grep -v cache      # 14
grep -rn "init(" Sources | xargs grep -l "onChange\|onWeather"   # 1
grep -rn "while true\|withTaskGroup" Sources            # 4
grep -rn "ZStack" Sources | wc -l                        # 3 (each is a hit-testing suspect)
grep -rn "as? String" Sources                            # 8
ps aux | grep "[W]eatheriOS.app/WeatheriOS" | awk '{print $3}'   # 1
```