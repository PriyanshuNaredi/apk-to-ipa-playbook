# 11 — Android surface map: everything the APK can do that is not a screen

A port driven by screenshots misses every component the manifest declares and nothing draws.
In Breezy Weather 6.2.2 that is: **25 activities, 4 services, 15 broadcast receivers, 3 content
providers and 14 permissions**. The user never sees them, the app is useless without most of
them, and none of them appear in a screenshot diff.

This stage is a paper exercise, done during recon, whose output is a table like the one
below. Fill it in before scaffolding, because the "does this platform have it at all?"
column decides scope.

---

## 1. Inventory the manifest, mechanically

```bash
python3 - <<'PY'
import re
x = open('app/src/main/AndroidManifest.xml').read()
for tag in ('activity', 'service', 'receiver', 'provider'):
    names = re.findall(r'<%s[^>]*android:name="([^"]+)"' % tag, x)
    print(tag, len(names), [n.rsplit('.', 1)[-1] for n in names])
PY
grep -o 'permission\.[A-Z_]*' app/src/main/AndroidManifest.xml | sort -u
```

Then classify every entry into exactly one of four buckets:

| Bucket | Meaning | Action |
|---|---|---|
| **A — same thing exists** | notifications, background refresh, location, files | implement with the platform API, in the parity spec |
| **B — different shape** | widgets, status-bar tile, shortcuts, live wallpaper | implement the nearest iOS equivalent or drop it explicitly |
| **C — platform glue** | `BootReceiver`, `AppLocalesMetadataHolderService`, `InitializationProvider` | nothing to port; delete the requirement |
| **D — impossible** | wallpaper service, system-wide overlay, `EXPAND_STATUS_BAR` | write it into the deviations table with a reason |

Anything in C or D that you carry into the backlog is a phantom task that will never close.

## 2. Component → iOS mapping

| Android | Breezy's version | iOS | Fidelity |
|---|---|---|---|
| `Activity` | 25 including `MainActivity`, `DetailsActivity`, `SettingsActivity`, `SearchActivity`, `AlertActivity` | `View` + `NavigationStack` route enum | full |
| `Activity` with `singleTop` + deep link | `AlertActivity` from a notification | `NavigationStack(path:)` driven by a pending route, `UNNotificationResponse` handler | full, if you keep the route in one `AppState` |
| `Service` (foreground, data sync) | refresh that survives the app being killed | `BGAppRefreshTask` (best effort, OS-scheduled) | **partial** — no guaranteed cadence |
| `Service` (wallpaper) | `MaterialLiveWallpaperService` | none | impossible |
| `Service` (`TileService`) | quick-settings tile | App Intent / Control Centre control (iOS 18) | partial |
| `BroadcastReceiver` on boot | `BootReceiver` reschedules work | automatic; `BGTaskScheduler` registrations are replayed | nothing to do |
| `BroadcastReceiver` (15 total) | 15 widget providers + notification actions | WidgetKit timelines, `UNNotificationAction` | shape differs |
| `ContentProvider` | `WeatherContentProvider` for external data sharing | App Group + `FileManager` (no cross-app read on iOS) | none; delete the feature |
| `ContentProvider` (`FileProvider`) | sharing exported files | `ShareLink`, `UIActivityViewController` | full |
| `SharedPreferences` | settings tree | `UserDefaults` | full |
| SQLite via SQLDelight | 25 migrations | file-per-model or SwiftData; see §5 | full |
| `WorkManager` periodic | 0:30 → 24:00 intervals | `BGAppRefreshTask` + `earliestBeginDate` | **partial** |
| `AlarmManager` exact alarm | today/tomorrow forecast notification at 07:00 / 21:00 | `UNCalendarNotificationTrigger` | full — and better |
| Shortcuts (long-press icon) | `shortcuts.xml` | `UIApplicationShortcutItems` in Info.plist | full |
| Widgets (RemoteViews) | 15 providers | WidgetKit: 1–3 families, timeline entries | partial, redesign |
| Live wallpaper | yes | none | impossible |
| Status-bar expand | `EXPAND_STATUS_BAR` | none | impossible |

## 3. Permissions, and what to ask for instead

| Android permission | Why Breezy has it | iOS |
|---|---|---|
| `ACCESS_FINE_LOCATION` / `COARSE` | current location | `WhenInUse` (never `Always` unless background refresh of the current location is a requirement; then `Always` + a written justification in the UI) |
| `ACCESS_BACKGROUND_LOCATION` | widget/notification refresh of the current location | `Always` authorisation + `allowsBackgroundLocationUpdates`; only if you truly refresh location in the background |
| `POST_NOTIFICATIONS` | alerts, forecast notifications | `UNUserNotificationCenter.requestAuthorization` |
| `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE*`, `SET_ALARM`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Android scheduling | no counterpart, drop |
| `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE` | network + "online only" logic | none needed; use `NWPathMonitor` |
| `READ_EXTERNAL_STORAGE` | importing/exporting settings files | document picker, no permission |
| `READ_APP_SPECIFIC_LOCALES`, `EXPAND_STATUS_BAR`, `BIND_WALLPAPER`, `BIND_QUICK_SETTINGS_TILE` | platform features | no counterpart |

Two rules that save an App Store rejection:

1. **Ask for a permission at the moment it is used, and never at launch.** A weather app that
   opens a location prompt before drawing anything reads as spyware.
2. **Every permission needs a purpose string that names the feature**, and the purpose string
   is content, not boilerplate: "Gust shows the forecast for where you are" beats "we need
   your location".

## 4. The mapping table is a scope document

Write the table in the recon stage and put a row count in the parity spec: *"manifest: 47
components → 12 implemented, 18 mapped to platform equivalents, 17 dropped (14 impossible,
3 glue)."* That single line is the honest measure of how much of the Android app the iOS app
is. Without it, "full parity" means "the screens match", which is a much smaller claim.

Example from this case:

```
manifest parity: 47 components
  A same thing (12):  main, details, settings, search, alert route, share, notifications x2,
                      background refresh, preferences, location, unit formatting
  B different shape (5): widgets x2, shortcut items, tile→control, preview→settings rows
  C glue (3):         boot receiver, locales metadata, initialization provider
  D impossible (27):  live wallpaper, wallpaper config, 15 widget receivers, tile service,
                      data-sharing content provider, expand-status-bar, ...
```

## 5. Persistence: SQLDelight/SQLite → what, exactly?

Breezy uses SQLDelight with 25 migrations: keep it as evidence that a mature weather app
*does* change its schema, and that a port with a hand-rolled JSON file must version it.

| Approach | When | Cost |
|---|---|---|
| One Codable struct per store, written atomically to `Application Support` | < ~10k records, no queries | cheapest, what this port did |
| SQLite via `SQLite3` + hand-written migrations | joins/queries, large history | you own the migration ladder |
| SwiftData | iOS 17+, you want `@Model` and queries | migrations are opaque; schema changes need care |
| `GRDB` | you want SQL with sane Swift types | extra dependency, worth it above ~100k rows |

Whatever you choose: **put the schema version in the file and refuse to load an unknown
version**, rather than decoding best-effort and silently showing an empty app.

## 6. Gate

You may leave this stage when every one of these is answered in writing:

- [ ] Every manifest component has a bucket (A/B/C/D).
- [ ] Every permission has an iOS authorisation and a purpose string, or is marked dropped.
- [ ] Every A/B row has a parity-spec entry with a test.
- [ ] The persistence strategy is named, and its schema versioning rule is written down.
- [ ] The deviation table lists every D row with a reason a user could understand.