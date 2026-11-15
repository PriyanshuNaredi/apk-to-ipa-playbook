# Project shape: put the portable logic in a package

Learned on the second port (Breezy Weather, 1,204 classes). The first port was one app target with a
separate logic-test bundle; that works at 43 classes and stops working at 1,200.

## The shape

```
05_ios/
  BreezyUnits/            ← Swift package: models, units, computing, networking clients
    Package.swift
    Sources/BreezyUnits/
    Tests/BreezyUnitsTests/
  Gust/                   ← app target: views, view models, app lifecycle
    project.yml           (XcodeGen)
    Sources/
    UITests/
  tools/                  ← build/test scripts
```

**Why the split, in order of how much it matters:**

1. **Sub-second feedback.** `swift test` on a package finishes in ~10 ms for 20 tests. The same
   tests inside an app target drag a simulator, a boot wait and a signing check. The inner loop
   you use 200 times a day must be the fast one.
2. **The logic becomes testable without a UI.** Ported formatting, units, projections, cache
   policies and decoding all live where they can be asserted directly.
3. **It ports upstream's module boundaries.** Breezy has `weather-unit`, `domain`, `data`, `work`
   as separate Gradle modules. Mirroring them in Swift makes the parity spec's rows map onto
   directories, and makes "which module does this belong to?" answer itself.
4. **It survives a UI rewrite.** The Weather port's fastest work happened after the data layer was
   green; the slowest was anything that needed a running app to test.

**When not to bother:** under ~500 lines of total logic, one target is simpler. The split costs a
`Package.swift`, a path in `project.yml`, and the discipline not to import SwiftUI from the package
(keep the package `import Foundation` only — that is also what lets it build on macOS for fast
tests).

## XcodeGen wiring for a local package

```yaml
packages:
  BreezyUnits:
    path: ../BreezyUnits

targets:
  Gust:
    type: application
    dependencies:
      - package: BreezyUnits
        product: BreezyUnits
```

Name the product explicitly. With a single-product package it is optional, but the moment the
package grows a second product (say a test-support library), an implicit link silently resolves to
the wrong one.

## The trap that cost a build: `CFBundleVersion`

`simctl install` refuses the app with:

```
Simulator device failed to install the application.
The application's Info.plist does not contain a valid CFBundleVersion.
(domain=NSPOSIXErrorDomain, code=22)
```

`xcodebuild` had said **BUILD SUCCEEDED**. The cause: `GENERATE_INFOPLIST_FILE: YES` together with
an explicit `info: path:` — XcodeGen writes the plist from `info.properties`, and the generated
one wins none of the version keys. Fix: drop `GENERATE_INFOPLIST_FILE` and state the version
explicitly:

```yaml
    info:
      path: Support/Info.plist
      properties:
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
```

And assert it in the build script, so a green build cannot mean an uninstallable app:

```bash
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist" 2>/dev/null || echo MISSING)
[ "$BUILD_VERSION" != "MISSING" ] || { echo "FAIL: CFBundleVersion missing" >&2; exit 1; }
```

## Gate for stage 4 on a big app

- [ ] Package builds and its tests are green (`swift test`)
- [ ] App target links the package and **renders one value that comes from it** — a placeholder
      screen is fine, a placeholder *value* is not
- [ ] App installs and launches on the pinned simulator with no signing identity
- [ ] Relaunch works (catches first-launch-only state bugs early)
- [ ] `CFBundleVersion` asserted by the build script
- [ ] Test script fails when a layer executes zero tests
- [ ] One screenshot committed showing the ported value on screen

The last item matters more than it looks: it is the difference between "the package links" and
"the package links *and* the arithmetic is right", which is what `Gust`'s shell screen showed —
humidex 31.0 °C for 25 °C / 18 °C dew point, wind chill correctly absent above 10 °C.
