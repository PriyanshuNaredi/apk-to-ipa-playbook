# APK → IPA Playbook

How to take an Android app you have the source (or only the APK) for, and rebuild it as a
native iOS app that a user cannot tell apart — plus the full record of doing it once,
defects and all.

This repo is the **method** and the **evidence** from porting
[Weather for Android](https://github.com/Kian-hdr/Weather) (Kotlin, Jetpack Compose,
MapLibre GL, MIT, v1.1.1) to a SwiftUI iOS app in two days: 2,144 lines of Kotlin became
6,079 lines of Swift across 30 files, with 87 logic tests and 11 UI tests standing watch.

It exists because the second port should not repeat the first one's cost. Read the playbook
top to bottom before touching an APK; read the case study when the playbook says "this
happens" and you want to know how it actually looked.

---

## Two layers

| Layer | Directory | What it gives you |
|---|---|---|
| **Playbook** (reusable) | `01_method/`, `04_patterns/` | 10 stages plus 7 non-visual subsystem docs, entry/exit gates, Compose→SwiftUI mapping tables, 42 catalogued defects, checklists |
| **Case study** (this app + the second, larger upstream) | `02_case_study/`, `03_rea/`, `06_evidence/` | commit-by-commit timeline, defects with root cause and proof, parity ledger, a measured atlas of Breezy Weather 6.2.2, REA findings we acted on, screenshots and logs |

## The 10 stages

Each stage has a **gate**: a check you can run. Skipping a gate is what turns a port into a
rewrite.

| # | Stage | Gate (must pass before moving on) |
|---|---|---|
| 1 | Recon | You can list every screen, every persisted key and every network call from evidence, not memory |
| 2 | Source recovery | For every screen you have *either* readable source *or* a decompiled file + method dump |
| 3 | Parity spec | A written table: Android behaviour → iOS implementation → how it will be tested |
| 4 | Scaffolding | `install → launch → empty state` works on a clean clone, with tests wired |
| 5 | Data layer | Offline replay of recorded responses; no UI yet |
| 6 | UI port | Every screen renders with the faith of a screenshot diff, not vibes |
| 7 | Custom rendering | The map/canvas equivalent is interactive at 60 fps with bounded memory |
| 8 | Verification | Logic suite + UI suite + visual audit + idle-CPU budget all green from clean |
| 9 | Release | Unsigned IPA builds reproducibly in CI and is verified unsigned |
| 10 | Retrospective | The defect catalog is updated with what actually bit you |

## Results at a glance (this case)

| Metric | Value |
|---|---|
| Source translated | 2,144 lines Kotlin → 6,079 lines Swift (30 files, ~2.8× — Compose layout is denser than SwiftUI, plus hand-rolled map) |
| Logic tests | 87 (59 XCTest + 28 swift-testing), 0.8 s |
| Simulator UI tests | 11, ~5 min for the full walk |
| Visual audit | 10 named screenshots, exported to `06_evidence/screenshots/` |
| Idle CPU on the forecast screen | 100% → 5.7% (the port's worst defect) |
| Radar window | 13 frames, ~10 s playback, verified from the app's own session log |
| Release artifact | 1.2 MB unsigned IPA, `arm64`, no `LC_CODE_SIGNATURE` |
| Defects found and fixed | 22 (see `02_case_study/DEFECTS.md`) — 12 would have shipped silently |
| Deliberate deviations from the APK | 9, each documented (see `02_case_study/PARITY_LEDGER.md`) |

## How to use this repo on the next port

1. `01_method/00_STAGE_MAP.md` — the whole method on one page.
2. `04_patterns/COMPOSE_TO_SWIFTUI.md` — paste-grade equivalents; check before inventing.
3. `04_patterns/DEFECT_CATALOG.md` — the defects that recur across ports, and the *test* that
   catches each. Write those tests before the screens.
4. `04_patterns/CHECKLISTS.md` — the gates as tickable lists.
   `04_patterns/PORTING_CHECKLIST_V2.md` — the same, extended to the non-visual subsystems
   (providers, caches, locale defaults, notifications, alerts); use this one for a port of an
   app that is more than a few screens.
   `04_patterns/PROJECT_SHAPE.md` — package-vs-app split, and the XcodeGen traps.
   `00_overview/LICENCES.md` — what the upstream licence makes you ship and how to name it.
5. `05_tools/` — copy-paste scripts: build, test, visual audit, unsigned IPA, icon rendering.

### Starting from an APK with no source

```bash
./05_tools/setup-apk-tools.sh          # Temurin JDK + jadx + apktool, no sudo, ~2 min
./05_tools/apk-recon.sh app.apk ./app-recon
less ./app-recon/RECON.md              # then the gates it lists
```

Ten evidence files in one run: checksum pin, signing certificate, manifest, permissions mapped to
their iOS counterparts, components, user-visible copy, colours/dimens/icon vectors, app-vs-library
class counts, and architecture markers (Compose or Views, scroll containers per screen, pager, map,
network, DI, obfuscation). Validated against the Weather APK, whose answers were already known —
output committed at `06_evidence/recon-baseline/`.

## Repo map

```
00_overview/     why port at all, what it cost, glossary, licence obligations
01_method/       the stages, one file each (01–10) plus the non-visual subsystems (11–17)
02_case_study/   timeline, defects, parity ledger, metrics, upstream atlas
03_rea/          what REA is, which findings we used, evidence index + vendored evidence
04_patterns/     Compose→SwiftUI tables, project shape, defect catalog, checklists
05_tools/        scripts (recon, build, tests, visual audit, IPA, icon)
06_evidence/     screenshots, the port's CHANGELOG / audit / verification docs,
                 recon baselines (Weather + Breezy)
```

### The non-visual half (`01_method/11`–`17`)

Added after auditing a second, much larger upstream (Breezy Weather 6.2.2: 1,358 Kotlin files,
74 source integrations, 63 locales) and finding what a screenshot-driven port never touches:

| Doc | Question it answers |
|---|---|
| `11_surface_map.md` | What does the manifest declare that no screen shows, and what is the iOS equivalent? |
| `12_source_architecture.md` | How do you keep a provider seam when you ship one provider? |
| `13_refresh_and_cache.md` | What is stale, for how long, and what does iOS actually guarantee in the background? |
| `14_units_and_locale.md` | Which unit does a user in `en_GB` see before opening settings? |
| `15_localization.md` | 1,162 strings in 63 languages: extraction, plurals, RTL, truncation. |
| `16_data_completion.md` | What do you derive (dew point, feels-like, weather code) and what is "today"? |
| `17_alerts_and_notifications.md` | Which alerts notify, whom, when, and how not to spam. |

The measured inventory behind them is `02_case_study/UPSTREAM_ATLAS.md`; the consolidated
checklist is `04_patterns/PORTING_CHECKLIST_V2.md`.

## Provenance

Every claim here is traceable to the port repository's commits, its `CHANGELOG.md`,
`CODE_AUDIT.md` and `MACOS_VERIFICATION.md` (all copied into `06_evidence/`), or to a file
under `03_rea/evidence/`. Where something was **not** verified — physical-device install,
on-device performance, denied-permission paths — it is labelled as such rather than implied.

Port: **Priyanshu Naredi**. Original Android app: **Kian Konrad**
([Kian-hdr/Weather](https://github.com/Kian-hdr/Weather), MIT) — the artwork, wording, colour
stops and cache budgets this port copies are his. Analysis of MIT-licensed source only: no
binaries are redistributed here.

## Licence

MIT — see `LICENSE`. Applies to the text and the scripts. The original app's assets remain
under its own MIT licence and its author's copyright.
