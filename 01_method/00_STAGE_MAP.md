# Stage map — the whole method on one page

A port is ten stages. Each has a **gate**: a check that proves the stage is done. Gates exist
because a port's failure mode is not "it does not compile" — it is "it compiles, looks right, and
behaves differently in six places nobody tested".

```
1 Recon ──▶ 2 Source recovery ──▶ 3 Parity spec ──▶ 4 Scaffolding
                                                          │
  8 Verification ◀── 7 Custom rendering ◀── 6 UI port ◀── 5 Data layer
        │
        ▼
  9 Release ──▶ 10 Retrospective (feeds 04_patterns/DEFECT_CATALOG.md)
```

## Stage 1 — Recon
Establish what the app *is*, from evidence: screens, navigation, persistence keys, network
endpoints, timings, cache budgets, permissions.
**Gate:** a written inventory where every line cites a file and line number (Kotlin) or a
decompiled method (APK-only). Anything uncited is a guess and must be marked as one.
→ `01_recon.md`

## Stage 2 — Source recovery
Get readable-or-decompiled code for every screen. Same repo, APK-only, or a mix.
**Gate:** no screen exists only as "I remember how it looked".
→ `02_source_recovery.md`

## Stage 3 — Parity spec
One table: Android behaviour → iOS implementation → the test that will prove it. Written before
UI code.
**Gate:** every row has a non-empty test column. Rows with no possible test are marked
"visual, audited by screenshot".
→ `03_parity_spec.md`

## Stage 4 — Scaffolding
Project generation, targets, test hosts, launch arguments, CI skeleton.
**Gate:** clean clone → build → launch → empty state, and `test` runs (and runs **something**).
→ `04_scaffolding.md`

## Stage 5 — Data layer
Clients, codecs, persistence, caches, projections — with no UI.
**Gate:** recorded responses replay offline through the whole data layer, and cache eviction is
tested against a byte budget.
→ `05_data_layer.md`

## Stage 6 — UI port
Screens, in navigation order, against the parity spec.
**Gate:** every screen appears in the visual audit with a stable name.
→ `06_ui_port.md`

## Stage 7 — Custom rendering
Whatever the framework does not give you: map, canvas, charts, animation loops.
**Gate:** interactive at 60 fps, memory bounded by policy, and a lifecycle that survives
backgrounding.
→ `07_custom_rendering.md`

## Stage 8 — Verification
Logic suite, UI suite, visual audit, idle-CPU budget; all from a clean clone.
**Gate:** numbers recorded in the repo, not in a chat.
→ `08_verification.md`

## Stage 9 — Release
Unsigned IPA built reproducibly, verified unsigned, documented for SideStore/LiveContainer.
**Gate:** the artifact exists, its verification passes, and a stranger can install it from the
README alone.
→ `09_release.md`

## Stage 10 — Retrospective
Which defects bit, which gates caught them, what the next port should test first.
**Gate:** the defect catalog in `04_patterns/` gained or corrected at least one entry.
→ `10_retrospective.md`

## Rules that cut across all stages

1. **Cite or mark it.** Every behavioural claim is either sourced or flagged unverified.
2. **Measure, do not describe.** "Idle CPU 5.7%" beats "performance looks fine".
3. **Prefer a test to a comment.** A comment asserts; a test enforces.
4. **One deviation at a time, written down.** Deviations are legitimate; undocumented ones rot
   into "bugs".
5. **Prove the unsigned state.** Never claim an artifact is unsigned — check it in the build.