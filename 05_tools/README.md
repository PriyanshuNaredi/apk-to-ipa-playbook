# Tools — the scripts this port actually used

Copied from the port repository, plus two added while preparing for the next port
(an APK with no source available). They are small, dependency-light, and each one exists
because a manual step was forgotten at least once. Adapt the paths, keep the assertions.

## `setup-apk-tools.sh` + `apk-recon.sh` — the no-source path

When there is no repository to read, stage 1–2 collapse into one command:

```bash
./setup-apk-tools.sh                                  # once per machine, ~2 min, no sudo
./apk-recon.sh ~/app.apk ./app-recon                  # per APK, ~90 s for a 97 MB app
less app-recon/RECON.md
```

`setup-apk-tools.sh` installs Temurin JDK 21 + jadx + apktool into `~/.local/apk-tools`
with wrappers, and verifies them. **Not** `brew install jadx`: on x86_64 macOS 15 the
`openjdk` formula has no bottle, so brew compiles OpenJDK 27 plus ~48 dependencies
(cmake, glib, cairo, harfbuzz, icu, …) from source — 30–60 minutes, and it trips over older
Command Line Tools. The prebuilt route is minutes and deletes cleanly.

`apk-recon.sh` writes ten files you can commit as evidence:

| File | Content | Why it matters |
|---|---|---|
| `00-checksum.txt` | sha256, size, package, version, tool versions | Pins *which* build was analysed |
| `01-signature.txt` | v1/v2/v3 schemes + the signing certificate | A debug-key signature means the APK was repacked, not the publisher's build |
| `02-manifest.txt` | decoded manifest | Ground truth for entry points |
| `03-permissions.txt` | permissions → likely iOS counterpart, `UNKNOWN` where there is none | A permission with no iOS equivalent is a **scope change**, not a port task |
| `04-components.txt` | activities/services/receivers/providers + count | One activity ⇒ no navigation graph to port |
| `05-strings.txt` | user-visible copy per locale, library keys filtered | The copy *is* parity; copy it, never paraphrase |
| `06-resources.txt` | colours, dimens, vector drawables | Icon `pathData` for `make-app-icon.swift` |
| `07-package.json` | app classes vs bundled library classes | The real size of the porting surface |
| `08-markers.txt` | Compose/Views, scroll containers, pager, map, network, DI, obfuscation | The architecture decisions, before reading any code |
| `RECON.md` | the summary, with gates | What a human reads first |

### Four bugs in the first version, all found by testing against a known APK

It was validated on `Weather_v1.1.1.apk` — an app whose architecture is already documented in
`../02_case_study/PARITY_LEDGER.md` — with the sha256 compared to the recorded baseline. That is
the only way to trust a recon tool: run it on something you already know the answer to.

1. `producer | grep -q` under `set -o pipefail` — exit on SIGPIPE read as failure. The exact trap
   this playbook documents; I reintroduced it. Now: capture output, compare strings.
2. `n=$(grep -rl … | wc -l)` is fatal under `set -e` + `pipefail` when grep finds nothing
   (`NavHost` absent is *normal* for a pure-Compose app). Needs `|| true`.
3. A quoted glob (`find "…/drawable*"`) is a literal path, not a pattern → `find` exits 1 →
   script dies. Use `-path "*drawable*"`.
4. **Counting library classes as the app.** The first run reported 19,271 classes and 3.85 M
   lines, and claimed “Fragments found” and “DI found” — all from bundled dependencies. The app
   is 43 classes. Everything is now scoped to the manifest's own package; library hits are
   reported separately and labelled as not ported.

What it rediscovered from the APK alone, with no source: Compose, no fragments, no DI,
`HorizontalPager` ×1, `LazyColumn` ×1, `verticalScroll` ×2, `AndroidView`+`MapView` ×1,
`OkHttp` ×2, `AtomicFile` ×1, and both entry points. All of it matches the hand-written analysis
in `03_rea/`. The baseline output is committed at `06_evidence/recon-baseline/`.

Caveat the script prints itself: decompiled Java line counts overstate Kotlin (imports, lambda
expansion). Compare **file counts**, not lines.

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

## `ipa-build.sh` (see `../01_method/09_release.md`)

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
| `setup-apk-tools.sh` | nothing (versions are pinned at the top) | deletes with `rm -rf ~/.local/apk-tools` |
| `apk-recon.sh` | marker list in the loop, library prefix filter | app-package scoping, the checksum pin, `RECON.md` gates |
| `macos-build.sh` | project name, scheme, simulator UDID, bundle id | regenerate-before-build, launch check |
| `macos-tests.sh` | test targets, filter names | the two layers, the non-zero-count assertion |
| `visual-audit.sh` | capture names and expected count | the loud failure, the naming contract |
| `ipa-build.sh` | app name, version keys | every unsigned assertion |
| `make-app-icon.swift` | the `pathData` strings and viewport size | the parser, the two-pass fit, the opaque plate |