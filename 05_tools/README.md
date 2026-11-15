# Tools — the scripts this port actually used

Copied from the port repository. They are small, dependency-light, and each one exists because a
manual step was forgotten at least once. Adapt the paths, keep the assertions.

## `macos-build.sh`

`xcodegen generate` → `xcodebuild` (simulator) → install → launch.

Why it exists: forgetting `xcodegen generate` after adding a file means the build silently excludes
it — and if the file was a test, the suite runs zero tests and reports success. The script
regenerates unconditionally.

Env: `DEVELOPER_DIR` (required — `xcode-select` may point at Command Line Tools), `DERIVED`
(default `/tmp/dd-weather`).

## `macos-tests.sh [all|logic|ui]`

Two layers, deliberately split:

- `logic` — host Swift Testing + XCTest, ~1 s. This is the inner loop.
- `ui` — XCUITest on a pinned simulator UDID, ~5 min. Run before claiming a milestone.
- `all` — both, plus the assertion that the executed count is non-zero.

The visual-audit class is excluded with `-skip-testing:` from normal runs, because it exports
screenshots for humans and takes minutes.

## `visual-audit.sh`

Drives `VisualAuditTests` and copies the resulting attachments into a named directory. **Fails
loudly** if fewer than the expected number of captures appear — an earlier version silently
exported nothing and still exited 0.

The capture names are the contract: `audit-01-empty` … `audit-10-map-temperature`. Those names are
referenced by the playbook and the case study, which is why they are stable.

## `ipa-build.sh` (see `01_method/09_release.md`)

Device `Release` build with signing disabled, packaged as `Payload/<Name>.app` inside a `.ipa`, plus
a `.sha256`. Then it **proves** the unsigned state: no `_CodeSignature`, no
`embedded.mobileprovision`, no `LC_CODE_SIGNATURE`, `codesign` says "not signed", `unzip -t` passes.

Note for future editors: do not reintroduce `producer | grep -q` in these checks — `grep -q` exits
early, the producer takes SIGPIPE, and `set -o pipefail` turns a successful match into a failed
pipeline. Capture output into a variable and compare strings.

## `make-app-icon.swift`

Renders a 1024×1024 iOS icon from the **original Android vector**
(`res/drawable/ic_weather_foreground.xml`), so the port ships the same glyph instead of a lookalike.

How it works, and why it is shaped this way:

1. Parse Android `pathData`: M/L/C/A/Z, absolute and relative. The `A` (arc) command is converted
   with the SVG endpoint→centre parameterisation — an icon with a crescent cannot be approximated
   by lines.
2. Draw with CoreGraphics at 1024² on an **opaque** plate (the adaptive icon's background is
   transparent; iOS forbids alpha).
3. **Two-pass placement.** A probe render measures the ink's actual pixel bounds, then a second pass
   scales and centres it. A geometric fit is wrong because stroked elements extend past path bounds
   on two sides only — the first attempt was 28 px off centre.

If you port an app with a vector icon, this is 250 lines that save you from hand-drawing, and the
result is exact rather than reminiscent.

## Adapting these to another port

| Script | Change | Keep |
|---|---|---|
| `macos-build.sh` | project name, scheme, simulator UDID, bundle id | regenerate-before-build, launch check |
| `macos-tests.sh` | test targets, filter names | the two layers, the non-zero-count assertion |
| `visual-audit.sh` | capture names and expected count | the loud failure, the naming contract |
| `ipa-build.sh` | app name, version keys | every unsigned assertion |
| `make-app-icon.swift` | the `pathData` strings and viewport size | the parser, the two-pass fit, the opaque plate |