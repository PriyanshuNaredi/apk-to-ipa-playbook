# Stage 1 — Recon

Goal: know what the app is before writing a line of Swift. Everything here is *evidence
collection*, not design.

## What to extract, and from where

| Question | Where the answer lives |
|---|---|
| Which screens, and what switches between them? | Manifest (activities) + the top-level composable/`when` |
| What is persisted, under which keys? | `SharedPreferences`/DataStore names; `AtomicFile`/file names |
| Which network endpoints, with what parameters? | HTTP client setup, URL builders, model classes |
| What timings and budgets exist? | Literal constants: refresh intervals, frame delays, cache byte limits |
| What does the app do when offline / denied / empty? | The error/empty branches of each screen |
| What is the app's own copy text? | String resources + literals in the source |

For each answer, record **file:line** (when source is available) or **decompiled method** (when
it is not). In this case study the inventory lives in `03_rea/evidence/ORIGINAL_APK_DEEP_ANALYSIS.md`
and every line of it cites `MainActivity.kt:NNN` or an `out-m-*.json` dump.

## The inventory that matters

Keep it short enough to read in one sitting. These six tables were enough for a 5-screen app:

1. **Screen graph** — from the manifest down: entry activity, then every branch.
2. **State** — per-screen state, what survives process death, what is derived.
3. **Network** — endpoint, method, parameters, response shape, refresh policy.
4. **Persistence** — key/file, format, atomicity, eviction, pruning.
5. **Constants** — timings, opacities, colour stops, cache budgets, zoom limits.
6. **Copy** — headline/body strings, in order, because parity includes wording.

## Recon on this port: what it produced

- **One activity, no navigation library.** `MainActivity` is the only exported activity; the
  whole app is a `when (screen)` inside one composable, and `screen` is `rememberSaveable`.
- **The bottom bar is a layout sibling** of the pager inside the weather branch — structurally
  impossible to occlude. This single fact drove the iOS bottom-bar rebuild later.
- **Pager identity is the city id**, and `currentIndex` is derived from the pager, not stored
  beside it. The first iOS implementation used array indices and two sources of truth — a defect
  that only showed when cities were added or removed.
- **Radar**: RainViewer tiles, `maxZoom 7`, 700 ms per frame, 1300 ms on the last, refresh every
  300 s while the layer is active.
- **Temperature**: 7×7 grid over the viewport, `FillLayer` opacity 0.42, six-stop colour scale.
- **Cache**: forecast JSON via `AtomicFile` with fail-write rollback; tiles in a 48 MiB OkHttp
  disk cache; forecast cache pruned to exactly the saved-city set on every `saveCities`.

## The gate

You can answer, without opening the APK again:

- every screen, and what makes it appear;
- every persisted key and its lifecycle;
- every endpoint and its refresh policy;
- every literal that a user could notice (timings, limits, colours, wording).

If a row of the inventory cannot be cited, it is a **guess**: write it down as a guess and
schedule a test for it. In this port the guess was "the map probably re-renders tiles on
return"; it was wrong, and the mistake cost a day (see `02_case_study/DEFECTS.md`, D9).

## Automation

When there is no repository to read, `05_tools/apk-recon.sh` produces this whole stage in one run:
checksum pin, signing certificate, decoded manifest, permissions mapped to their iOS counterparts,
components, user-visible copy, colours/dimens/icon vectors, app-vs-library class counts, and the
architecture markers (Compose or Views, scroll containers per screen, pager, map, network, DI,
obfuscation). Commit its output as the new port's `recon/` evidence directory; the script was
validated against an APK whose answers were already known — see `06_evidence/recon-baseline/`.

Two of its outputs decide scope before any design work:

- **Permissions with `UNKNOWN` counterpart** (foreground services, boot receivers, wake locks,
  cross-app queries). Each is a feature that cannot exist on iOS as written. Decide with the owner,
  do not discover it at stage 6.
- **App classes vs bundled library classes.** The first version of the script counted both and
  reported 19,271 classes; the app was 43. Size the work from the app's own package only.

## Anti-patterns

- Designing the iOS architecture during recon. You will port your design, not the app.
- Trusting memory of "how the Android app felt". Feelings are not parity.
- Skipping the constants table because "they are just numbers". Half the defects in this repo
  are numbers: 700/1300 ms, 48 MiB, 0.42 opacity, 5.0 zoom.
- Recon without artefacts. If recon leaves no file behind, the next person (or your next session)
  starts over.