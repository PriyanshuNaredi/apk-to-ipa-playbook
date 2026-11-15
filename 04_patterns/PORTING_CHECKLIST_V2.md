# Porting checklist, second edition

The first checklist asked "did you rebuild the screens?". This one asks "did you rebuild the
**app**?" — the parts that never appear in a screenshot and that a screen-driven port silently
drops. It is ordered by stage; each line points at the document that explains it.

Use it as a read-through before scaffolding (to size the work) and as a sweep before release
(to find what was skipped). A tick you cannot demonstrate with a command, a test name or a
screenshot is not a tick.

---

## Recon and scope

- [ ] Screen inventory, every screen cited from source or decompiled method — `01_recon.md`
- [ ] **Manifest inventory**: every activity / service / receiver / provider in a bucket
      (same thing / different shape / glue / impossible) — `11_surface_map.md`
- [ ] **Permission inventory** with an iOS authorisation and a purpose string each — `11_surface_map.md`
- [ ] Persisted keys enumerated, including the ones only a settings screen writes
- [ ] Network endpoints enumerated, with quota/licence notes — `05_data_layer.md`
- [ ] **Source inventory**: which provider feeds which feature, and what happens where there is
      no coverage — `12_source_architecture.md`
- [ ] **Locale inventory**: how many languages, which RTL, which plurals — `15_localization.md`
- [ ] Upstream's own docs read (`breezy-weather/docs/UPDATES.md`-style refresh and cache rules if they exist)
- [ ] Every dropped feature written into the deviations table with a user-comprehensible reason

## Parity spec

- [ ] One row per behaviour: Android → iOS → the test that proves it
- [ ] Numbers with boundaries in the spec (thresholds, split hours, band edges), not adjectives
- [ ] **Docs-vs-code disagreements** recorded, code chosen — `../02_case_study/UPSTREAM_ATLAS.md` §5
- [ ] Every "impossible" row names the platform limitation, not "hard"

## Scaffolding

- [ ] Clean clone → generate → build → launch → empty state
- [ ] Test targets exist and **assert N > 0** so an empty suite cannot pass — `08_verification.md`
- [ ] Launch arguments for deterministic tests (`-resetState`, seed data) are implemented in
      production code, not only documented — defect §27
- [ ] Deployment target chosen for the APIs actually used (`@Observable` → iOS 17)

## Data layer

- [ ] Recorded real responses committed as fixtures; replay works offline
- [ ] Reference-unit storage (integers) and one formatting edge — `14_units_and_locale.md`
- [ ] **Per-feature validity** + 5 km coordinate invalidation — `13_refresh_and_cache.md`
- [ ] **Failure is per feature**: stale values survive a partial refresh — `12_source_architecture.md` §4
- [ ] **Absent ≠ zero ≠ not-covered** is representable in the model — defect §26
- [ ] Persistence has a schema version and refuses unknown versions — `11_surface_map.md` §5
- [ ] Profile-derived values (dew point, feels-like, weather code) computed once, in the model,
      with boundary tests — `16_data_completion.md`
- [ ] `todayIndex` uses the 24-hour rule, not index 0 — `16_data_completion.md` §2
- [ ] Sun/moon return `nil` where they do not rise, and a known new moon is pinned in a test
- [ ] Provider seam exists even with one provider — `12_source_architecture.md` §3

## UI port

- [ ] Every screen in the visual audit with a stable name
- [ ] Layout law ported as **code** (half/full blocks, column counts), not as per-screen layout
- [ ] Colours copied as literals from the source, with a test pinning them
- [ ] Dark mode, and the weather-driven background, verified on a real screenshot — defect §28
- [ ] Charts reserve a gutter for their extreme labels — defect §25
- [ ] Night labels drive night icons — defect §29
- [ ] Identifiers on leaves, `.accessibilityElement(children: .contain)` on containers and links
      — defects §23, §24
- [ ] Spoken labels are localized; identifiers are stable English — `15_localization.md` §6
- [ ] Every count string pluralized in resources — defect §34
- [ ] Pseudo-locale run for truncation, RTL run for hand-drawn views — `15_localization.md` §4
- [ ] Settings shows only what the platform honours; no dead pickers — defect §27
- [ ] Card shapes read from `app:shapeAppearance` per container, with a test pinning the count per
      shape — defect §37, `06_ui_port.md` "The look is in the layouts"
- [ ] Half-size cells framed square when the layout constrains them `1:1` — defect §37
- [ ] Weather artwork taken from the drawables and resolved by the ported lookup; a test asserts
      every producible name has a file — defect §38
- [ ] Trend blocks are sideways columns at the dimens' fixed width, not rows — defect §39
- [ ] Navigation inventory taken from `res/menu/` and the activity layout; no tab bar unless upstream
      has one, and a test asserts its absence — defect §40
- [ ] No bar treatment that depends on network data — defect §41
- [ ] Background is the upstream's asset gradient per (kind, daylight, theme) **and** its
      animated scene, with every stop colour and particle count pinned by a test —
      defect §43
- [ ] Frame rate measured, not assumed; a setting exists to pause the animation — defect §43
- [ ] The test gate counts every framework in the output and prints the split — defect §44
- [ ] Square blocks use the upstream's 20 %/80 % guidelines, not a padding, and full-width
      cards have their own container — defect §49
- [ ] Every card's *appearance* field and *numbers* field written down, and the copy for
      the state where they disagree — defect §48
- [ ] Every period/period-boundary constant in the upstream is listed with the file it
      lives in; a card that splits the same data twice keeps both splits — defect §47
- [ ] Every law applied to a fetched series is clipped or resampled to the rendered span
      first, in the data layer, with a test — defect §46
- [ ] `permissions: contents: write` declared before the first tag, and the release asset's
      size checked by API rather than assumed — defect §45
- [ ] Every UI identifier on a leaf or on a link/container declared with `children: .contain`; every
      `navigationBars` query scoped by title — defect §42

## Background, cache, notifications

- [ ] Views never fetch; the store does, with an injectable clock — `13_refresh_and_cache.md` §5
- [ ] Background refresh is `BGAppRefreshTask` **or** absent from settings; nothing promises a
      cadence iOS does not guarantee — `13_refresh_and_cache.md` §4
- [ ] Daily forecast notifications use `UNCalendarNotificationTrigger`, not a background loop
- [ ] Notifications: authorisation asked at first use, deep link handled, `userInfo` route wired
- [ ] **Alert rules** (if alerts exist): MINOR suppressed, UNKNOWN notified, dedupe by id,
      first location only, background only — `17_alerts_and_notifications.md`
- [ ] Notification permission denied → the app is still fully usable, and says so once

## Units and locale

- [ ] Defaults derived from `Locale`, tested across at least eight locales — `14_units_and_locale.md`
- [ ] `measurementSystem == .uk` not collapsed into `.us`
- [ ] 12/24-hour default from `Locale.hourCycle`, override available
- [ ] All times formatted in the **location's** zone, with a fixed cross-zone test
- [ ] "Restore defaults" exists

## Verification

- [ ] Logic suite green from clean, and it tests behaviour not getters
- [ ] UI suite green, judged by exit code + `TEST SUCCEEDED`, never by grepping `error:` — defect §30
- [ ] Idle CPU measured, not assumed
- [ ] Screenshots exported and reviewed by eye — at least one per screen, in both themes
- [ ] Accessibility audit: every interactive element has a label and a stable id
- [ ] Offline launch, first-run launch, and launch with an unknown persisted schema version

## Release

- [ ] Unsigned IPA built by one script, self-verified (`CFBundleIdentifier`, licences, `Assets.car`,
      `DTPlatformName == iphoneos`) — `09_release.md`
- [ ] Licences of the upstream project and every data provider bundled and reachable in-app
- [ ] Credited upstream, and the upstream's additional terms respected (name, notices)
- [ ] CI runs the tests then the packaging step, on a tag
- [ ] README states the deviations a user can see

## Retrospective

- [ ] Every defect that cost more than an hour has a `DEFECT_CATALOG.md` entry with a **test to
      write first**
- [ ] Every entry that already existed and recurred is merged into the old one, not renumbered
- [ ] The checklist above gained every line this port wish it had had