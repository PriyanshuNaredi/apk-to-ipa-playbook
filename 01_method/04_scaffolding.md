# Stage 4 — Scaffolding

Goal: a project that builds, launches, and *runs tests* from a clean clone, before any feature
code. This stage is boring on purpose — every minute here is repaid when you add the 30th file.

## Decisions to make explicitly

| Decision | This port | Why |
|---|---|---|
| Project definition | XcodeGen `project.yml` committed, `.xcodeproj` gitignored | No merge conflicts, no Xcode state in git, reviewable diff |
| Language mode | Swift 5 (`SWIFT_VERSION 5.0`, `SWIFT_STRICT_CONCURRENCY minimal`) | Swift 6 mode rejected Darwin-only paths; see the note below |
| Test targets | logic package (host) + XCUITest (simulator) | Fast loop for logic, honest loop for pixels |
| Launch args | `-resetState` wipes defaults + caches | Deterministic UI tests |
| Dependencies | none | The port deliberately owns its map renderer |
| CI | build + unsigned IPA on `macos-15` | Release goes through the same door as development |

### Swift language mode is not a style choice

Porting from Kotlin sources that were compiled for a *Linux* CI meant two Darwin-only paths had
never been type-checked under Swift 6's strict concurrency (`mach_task_self_` in the diagnostics
logger; a `static var inFlight` in the map view). Swift 6 mode failed the build; Swift 5 mode
matched what had actually been verified. Record the mode you build in — a silent mode change
later turns into a wall of unrelated errors.

## Minimum viable scaffolding

1. `project.yml` with app target + UI test target, `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`
   taken from the Android `versionName`/`versionCode`.
2. `Support/Info.plist` generated from the spec, with the usage strings the app needs
   (`NSLocationWhenInUseUsageDescription`).
3. Scripts: `macos-build.sh` (generate → build → install → launch), `macos-tests.sh`
   (`all | logic | ui`), `visual-audit.sh` (screenshots).
4. A logic test target that can run in under a second, and one test that proves it is wired.
5. `.gitignore` for generated artifacts: `.xcodeproj`, `Support/Info.plist`, `*.ipa`,
   `DerivedData`, screenshot output.

## The two traps that cost the most time

**1. Generated project = invisible new files.** Add a source or test file and forget
`xcodegen generate`, and the build silently excludes it — worst of all, a *test* file, so the
suite runs with `0 tests` and reports success. Rule: any command that adds files ends with
regenerate, and the test script asserts a non-zero test count.

**2. `booted` is ambiguous.** With a second simulator booted (a long-running test device), a
`-destination 'platform=iOS Simulator,name=iPhone 16'` can attach to the wrong one, or fail
outright. Pin the UDID in the scripts and pass it to every command.

## Simulator state is part of the scaffolding

UI tests need deterministic state: defaults, caches, permissions, and location.

- `-resetState` launch argument clears the app's own stores.
- `xcrun simctl privacy <udid> grant location-always <bundle-id>` for location tests.
- `xcrun simctl location <udid> set <lat>,<lon>` to freeze a location (the timeout test in this
  port needs a real fix to arrive, so a fixed coordinate is required).
- Granting privacy requires the app to be installed *first* — order the script accordingly.

## Exit gate

From a clean clone, with a fresh derived-data path:

```
./scripts/build.sh      # BUILD SUCCEEDED, app launches
./scripts/tests.sh all  # N > 0 tests, all green
```

If the test script can pass with zero tests executed, the gate is not real. Add the assertion
now, while it is one line, not later when it hides a regression.