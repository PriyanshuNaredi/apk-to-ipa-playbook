# Checklists — the gates as tickable lists

Copy these into the next port's `PROJECT_STATUS.md` and tick as you go. Each item is a command or
an observation, never a feeling.

## Stage 1 — Recon

- [ ] APK checksum recorded, and the tag/version being ported is pinned
- [ ] Signature + package facts captured (which build am I analysing?)
- [ ] Screen graph written down, each screen's trigger cited (file:line or dump)
- [ ] Persistence inventory: key/file, format, atomicity, eviction
- [ ] Network inventory: endpoint, params, refresh policy, staleness window
- [ ] Constants: timings, opacities, colour stops, cache budgets, zoom limits, page sizes
- [ ] Copy inventory: every user-visible string, in order
- [ ] Dependency list, with a decision per dependency: equivalent, own implementation, or drop

## Stage 2 — Source recovery

- [ ] Every screen has source **or** (decompile + method dump)
- [ ] Structural claims cross-checked against bytecode, not just source
- [ ] Resources decoded (strings, colours, drawables, icon vector)
- [ ] Analysis tools installed project-local; nothing written to global configs
- [ ] Evidence files committed and indexed

## Stage 3 — Parity spec

- [ ] Table has three columns: Android behaviour, iOS implementation, proof
- [ ] Every row has a non-empty proof column (test name or screenshot name)
- [ ] Deviations listed separately with reasons
- [ ] Numeric rows double-checked against the constants table

## Stage 4 — Scaffolding

- [ ] Project generated from a committed spec; generated files gitignored
- [ ] App + UI test targets exist; `-resetState` launch argument works
- [ ] Build script: generate → build → install → launch
- [ ] Test script asserts **N > 0** tests executed
- [ ] Visual audit script fails if the expected capture count is not met
- [ ] Clean clone builds and launches
- [ ] Simulator pinned by UDID in every script
- [ ] CI skeleton builds (release path included)

## Stage 5 — Data layer

- [ ] Recorded-response tests for every endpoint
- [ ] Codec handles the wire format's real types (numeric ids!)
- [ ] Persistence is atomic; relaunch test keeps data
- [ ] Cache eviction tested against a byte budget
- [ ] Cancellation tested (a timeout test, not an assertion in a comment)
- [ ] Projection (units/formatting) tested without any view

## Stage 6 — UI port

- [ ] Shell first: screen switch, back order, chrome
- [ ] Each screen has a named visual-audit capture
- [ ] Interactive elements ≥ 44 pt and hittable in a UI test
- [ ] Chrome is a layout sibling, not an overlay, wherever the original was
- [ ] Strings match the original (or are in the ledger)
- [ ] Idle CPU measured after each screen lands

## Stage 7 — Custom rendering

- [ ] Projection/camera math has unit tests
- [ ] Tile fetch/decode off the main actor; cache budget enforced
- [ ] Pan/pinch tested (and pinch+pan simultaneous)
- [ ] Layer opacity/timings are literals copied from the original
- [ ] Labels/badges avoid measured chrome and the primary marker
- [ ] Work cancels on disappear (verified in the log)
- [ ] Idle CPU and memory budget within target

## Stage 8 — Verification

- [ ] Logic suite green, under a second
- [ ] UI suite green, waits on state (no `sleep`)
- [ ] Visual audit exports the expected number of captures
- [ ] Idle CPU measured and recorded
- [ ] Clean-clone run with a separate derived-data path
- [ ] Every defect in the log has a guarding test, or is listed as untestable with a reason

## Stage 9 — Release

- [ ] Device `Release` build with signing disabled
- [ ] Payload packaged, Xcode leftovers stripped
- [ ] Signature checks pass (no `_CodeSignature`, no profile, no `LC_CODE_SIGNATURE`)
- [ ] `unzip -t` passes; `.sha256` published
- [ ] Bundle contains `Assets.car`, the icon rendition, and the legal notices
- [ ] README + release notes: unsigned, what that means, SideStore/LiveContainer links, account limits
- [ ] CI reproduces the artifact from a tag
- [ ] "Simulator-verified, device-unverified" stated explicitly

## Stage 10 — Retrospective

- [ ] Defect catalog updated with anything new
- [ ] Parity ledger lists every intentional difference
- [ ] Metrics file records what was measured **and what was not**
- [ ] Next port's first commit can start from these checklists unedited