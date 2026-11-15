# Stage 3 — Parity spec

The parity spec is a table you write **before** UI code and keep until the end. It is the
difference between a port and an impression of one.

## Shape

| # | Android behaviour | iOS implementation | Proves it |
|---|---|---|---|
| 1 | `screen` is `rememberSaveable` → survives process death | `@SceneStorage("screen")` | UI test relaunch restores screen |
| 2 | Pager keyed by city id; `currentIndex` derived from pager | `ForEach(cities, id: \.id)` + `scrollPosition(id:)` | test: remove city 0, index follows |
| 3 | Radar frame delay 700 ms, 1300 ms on last | same literals in the animation task | session log frame timestamps |
| … | … | … | … |

Three columns are mandatory. A row with an empty "Proves it" column is a wish.

## How fine to go

Fine enough that a stranger could implement each row without opening the APK. Too fine is a
transcription of the source, which is stage 2's job. The useful unit is **one user-visible
behaviour**: a layout relationship, a timing, a persistence rule, a piece of copy.

In this port 40-odd rows were enough for 5 screens; the survivors are in
`02_case_study/PARITY_LEDGER.md` (that file lists only the ones that ended up *different*, which
is the interesting half).

## The four classes of row

1. **Structural** — "the bottom bar is a sibling of the pager, never an overlay". These cause the
   ugliest defects: the iOS version of this row was an overlay, and the map preview swallowed
   bar taps.
2. **Identity** — "pager pages are keyed by city id". Wrong identity = wrong state recycled into
   the wrong page, which looks like a data bug and is not.
3. **Numeric** — 700/1300 ms, 48 MiB, 0.42 opacity, zoom 2–12, 7×7 grid, 15-minute refresh.
   Numbers are cheap to copy and expensive to guess.
4. **Copy** — exact wording, including the app's own oddities. If the original says
   "Interpolated model temperature", the port says that too.

## Deviations: allowed, never silent

Some rows you *will* break — a platform API is missing, the original behaviour is a bug, or the
port can do better. That is fine, under two conditions:

1. The deviation is written down with the reason (`02_case_study/PARITY_LEDGER.md`).
2. The gate for that row changes from "matches Android" to "matches the documented intent", and
   the test asserts the *new* behaviour.

Example from this port: Android opens the radar parked on the newest frame with nothing playing.
Technically faithful, practically confusing — it reads as "already played". The port opens on the
oldest frame and plays once. Ledger entry, test, screenshot: all three exist.

The worst outcome is neither faithful nor documented: it looks like a defect and will be
"fixed" back to the original later by someone who never sees the reasoning.

## Anti-patterns

- Writing the spec after the screens, from the code you just wrote. That is a changelog, not a spec.
- "Looks the same" as the gate. Looks is stage 6's screenshot test, not a claim about behaviour.
- Rows for internal structure ("uses a ViewModel"). Ports are judged on behaviour; internal
  parity is over-constraining.
- A spec with no owners. Every row needs a test file it lands in, or it evaporates.

## Exit gate

Every row has a test or a named screenshot. Anything else moves to a "known gaps" list that
`02_case_study/PARITY_LEDGER.md` and the README both link to.