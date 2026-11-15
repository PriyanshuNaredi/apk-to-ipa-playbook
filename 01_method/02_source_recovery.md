# Stage 2 — Source recovery

Three situations, three strategies. Decide which one you are in *before* stage 3.

## Situation A — you have the source

Best case, and the one this port was in: the Android app was published under MIT.

- Clone the exact tag you intend to port (`v1.1.1` here, not `main`).
- Read the `.kt` files, but **verify structural claims against the bytecode**. Source and APK can
  disagree: build flavours, dead code, or a release build with a different resource set.
- Keep the source as the *readable* reference and the decompile as the *authoritative* one.

Cost of getting this wrong: a port that matches the repo but not the shipped app.

## Situation B — APK only

Recover in two layers, because they answer different questions:

| Layer | Tool | Gives you |
|---|---|---|
| Bytecode | jadx (or `rea-agents`, which wraps it) | Classes, methods, control flow, constants, string literals, per-method dumps as JSON |
| Resources/manifest | apktool | `AndroidManifest.xml`, `res/` with original IDs, layouts, drawables (vector XML!), strings |

Do both. jadx shows you *what the code does*; apktool shows you *what the user sees* — and the
icons, colours and copy live in apktool territory.

For a large APK, drive the decompiler through a queryable layer rather than grepping HTML dumps
by hand. `rea-agents` does this: it exposes package inventory, class and method dumps, and
signature/manifest facts as JSON, which is far easier to cite than a 60 MB sources tree.

## Situation C — obfuscated, no source

Proceed only with a written risk note. You will:

- Rename everything to *your* vocabulary and keep a mapping table, or you will lose track of
  which `a.a.b` is the repository;
- Reconstruct model shapes from JSON access patterns rather than from fields;
- Have no ground truth for error handling. Budget extra time for the "what does it do when X
  fails" tests, because you are guessing.

If the app also stores opaque blobs or talks to a server you do not control, stop and reconsider
(`00_overview/WHY_PORT.md`).

## Verify the artifact before trusting it

1. **Checksum** the APK you analyse and record it (`49a502b2…99c1` here). Analysis of an
   unrecorded binary cannot be reproduced.
2. **Signature check** — tells you if this is the official build and whether it is debuggable.
3. **Package/version** — the port targets a version, not a moving `main`.
4. **Dependency list** — decides what you must reimplement (here: MapLibre, OkHttp). Anything in
   this list either gets an iOS equivalent or becomes your own code. Write the decision down per
   dependency; in this port MapLibre became 1,139 lines of custom renderer.

## What was used here

- Readable source: `00_original/source/Weather/…/*.kt` at tag `v1.1.1`.
- Bytecode evidence: `rea-agents@6.9.0` under `07_tools/rea-analysis/`, 38 evidence files
  (vendored in `03_rea/evidence/`), including per-method dumps for
  `WeatherApp`, `ForecastPage`, `CityScreen`, `MetricScreen`, `SettingsScreen`, `MapsKt`, and
  the repository methods `cached/get/read/write/radar/temperatures/saveCities`.
- Resource evidence: apktool dump for the manifest and the launcher icon vector, which later
  became the iOS app icon (rendered, not redrawn).

See `03_rea/FINDINGS_USED.md` for the specific findings that changed the port, and
`03_rea/EVIDENCE_INDEX.md` for the full file inventory.

## The gate

For every screen: **either** readable source **or** (decompiled file **and** method dump).
Anything else is stage-1 guesswork leaking into stage 3.