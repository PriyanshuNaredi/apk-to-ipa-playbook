# Stage 10 — Retrospective

What actually mattered, in the order it mattered. Written from the defect list, not from
memory of the work feeling good.

## The three things that saved the most time

**1. Reading the original before designing anything.** The parity spec (stage 3) took ~20% of the
schedule and prevented the most expensive class of defect: a component that *almost* matches.
Concretely: discovering that the bottom bar is a layout sibling of the pager, not an overlay,
turned a live tap-routing bug into a five-line structural change.

**2. An idle-CPU budget as a first-class metric.** The 22 Hz invalidation loop was invisible to
every test and to every screenshot. A single `ps aux` line found it and a single number proved the
fix. Put this in the scaffolding, not the backlog.

**3. The visual audit + evidence file.** Ten named screenshots turned "looks fine" into a diffable
artifact. The two worst *cosmetic* defects — every panel child painted as its own card, and page
dots 24 pt off centre — were both obvious in a capture and invisible in code review.

## The four things that cost the most time

**1. A framework mental model applied one level too shallow.** `@ViewBuilder` returns a tuple; a
`Column` is a container. Believing the abstraction leaked cost a full parity pass over 13 call
sites.

**2. Timeout and cancellation semantics.** `withTaskGroup` waits for *every* child, so a
"timeout" built that way never fires; `LaunchedEffect` → `.task(id:)` restarts and cancels, and
unchecked continuations do not care. Both were code that read correctly and hung in practice.

**3. Silent empty test runs.** A forgotten `xcodegen generate` meant new test files were excluded
and the suite reported success with zero tests. Any harness that can pass by doing nothing must
assert otherwise.

**4. Release verification that was wrong in a subtle way.** `... | grep -q` + `pipefail` produced
false failures on a *correct* artifact — and had it produced false *passes*, the playbook would
have shipped a release note lying about signing.

## What to do differently on the next port

1. **Write the defect tests first**, from `04_patterns/DEFECT_CATALOG.md`. Nine of this port's 15
   defects are in that catalog already; the tests exist for them just as soon as the code does.
2. **Instrument before porting the map**: log frame transitions and tile cache hits from day one.
   The map's defects were all temporal.
3. **Screenshot every screen on the day it is written**, not a parity pass later; retro-fitting
   parity across 13 call sites is what the "one card per panel" bug required.
4. **Assert test counts in CI** and regenerate before every test run, unconditionally.
5. **Keep the evidence file alive** (`06_evidence/`). It is the only reason this retrospective is
   specific instead of plausible.

## Delegation and tooling note

This port was executed with an agent harness (pi) driving Xcode, the simulator, and the analysis
tools. What that changed:

- **Better**: mechanical breadth (reading 2,144 lines of Kotlin, sweeping 30 Swift files for an
  idiom, re-running suites), and relentless verification loops.
- **Worse**: it will confidently port a *wrong mental model* of a framework API, and only a
  measurement catches that.
- **Rule that emerged**: the agent must never be the only witness. Every claim in the port has a
  file behind it — a log line, a screenshot, a test name, a commit body.

## Exit gate

- `04_patterns/DEFECT_CATALOG.md` has at least one new or corrected entry from this port.
- The next port's first commit can start from `04_patterns/CHECKLISTS.md` without editing it.