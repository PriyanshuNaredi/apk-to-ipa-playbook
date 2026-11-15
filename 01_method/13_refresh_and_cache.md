# 13 — Refresh, caching and the background policy

The first version of any port refreshes when a view appears. That is fine on the simulator
and wrong everywhere else: it burns quota, it makes "updated 4 minutes ago" untrue, it shows
a different number every time you swipe between tabs, and it cannot answer "show me the data
I had twenty minutes ago when I was offline".

Breezy has a written pipeline (`breezy-weather/docs/UPDATES.md`), a per-feature cache table, and a
background policy that is deliberately asymmetric between the first location and the rest.
All three are portable.

---

## 1. The refresh pipeline, as seven named steps

From `breezy-weather/docs/UPDATES.md`, verbatim in order — each step is a place a port usually stops early:

1. **Resolve the location first.** For the current location, re-read coordinates from the
   location source. On failure: use the last known coordinates; if there are none,
   this location's refresh ends. Manual refresh always reports the error; background refresh
   reports it only when there is no last-known position.
2. **Re-resolve the address** when coordinates changed, when the reverse-geocoder changed, or
   when the place was added from raw coordinates. With no configured reverse geocoder, fall
   back to an offline country lookup.
3. **Disambiguate the country** (ISO 3166-1 alpha-2) through the offline lookup, so every
   provider sees the same country code.
4. **Compute the missing time zone locally** from the country, instead of asking a service.
5. **Group features per source** into a single request, then request only features whose data
   is no longer valid (step 3 of the cache table below). If a feature fails, restore the
   previous data for **that feature**.
6. **Merge all sources' data** into one weather object.
7. **Complete it**: backfill the past to yesterday 00:00, extrapolate derived values, compute
   sun/moon. See `16_data_completion.md`.

Steps 1–4 are location hygiene and are commonly skipped because the geocoder "already returns
a time zone". It does — until the place was added by coordinates, or the geocoder's country
code is `UK` instead of `GB` and the provider's coverage check silently fails.

## 2. The cache table

Validity, in minutes, per feature and per source class. "Restricted" = OpenWeather, AEMET,
CWA without a user API key.

| Feature | Normal source | Restricted source |
|---|---|---|
| Main weather | 5 | 15 |
| Current weather | 1 | 15 |
| Air quality | 5 | 60 |
| Allergen / pollen | 5 | 60 |
| Minutely (precipitation nowcast) | 1 if there is a nowcast, else 5 | 5 / 15 |
| Alerts | 1 if there are alerts, else 5 | 5 / 60 |
| Normals / climatology | only if this month's data is missing | same |

Plus one global rule: **cache is ignored when the coordinates moved more than 5 km** from the
last successful fetch.

Two properties of this table are worth copying exactly:

- **Validity depends on content**, not only on age: minutely and alerts go stale in one minute
  when they carry data and five when they do not.
- **Validity is per feature.** A single `lastRefreshed` timestamp for the whole weather object
  forces you to choose between refreshing air quality too often and too rarely.

## 3. Porting the table

```swift
public struct CachePolicy: Sendable {
    public let freshMinutes: @Sendable (_ hasContent: Bool) -> Int
    public static let mainWeather = CachePolicy { _ in 5 }
    public static let current     = CachePolicy { _ in 1 }
    public static let airQuality  = CachePolicy { _ in 5 }
    public static let pollen      = CachePolicy { _ in 5 }
    public static let minutely    = CachePolicy { has in has ? 1 : 5 }
    public static let alerts      = CachePolicy { has in has ? 1 : 5 }
    public static let geocoding   = CachePolicy { _ in 60 * 24 * 30 }   // places do not move
}

public struct Fetched<Value> { public let value: Value; public let at: Date }

public func isStale<Value>(_ fetched: Fetched<Value>?, policy: CachePolicy,
                           now: Date = .now, movedMetres: Double = 0) -> Bool {
    guard let fetched else { return true }
    guard movedMetres <= 5_000 else { return true }
    let minutes = now.timeIntervalSince(fetched.at) / 60
    return minutes >= Double(policy.freshMinutes(true))
}
```

Keep the `Fetched` wrapper in the store, not in the view: the view should never decide
whether to call the network. **Views render; stores fetch.**

## 4. Background refresh: what iOS will and will not give you

Android gets `WorkManager` with a user-selected interval from this exact ladder:

```
never, 0:30, 1:00, 1:30 (default), 2:00, 3:00, 6:00, 12:00, 24:00
```

iOS gives you `BGAppRefreshTask`, run at the system's discretion, typically no more than a few
times a day and not at all if the app is force-quit or the user disables Background App
Refresh. So:

| Requirement | Android | iOS | What to do |
|---|---|---|---|
| "Refresh every 90 min" | honoured approximately | cannot be promised | honour `earliestBeginDate`, and **say so** in settings: "iOS decides when to run background updates" |
| Refresh first location | always | likely | schedule one task, refresh the first location only |
| Refresh secondary locations | ≤ once a day, max 3/4/5 | no | refresh on open, and only when stale by the table |
| Notify on new severe alerts | yes | yes, if the task runs | accept "may be late"; never promise immediacy |
| Refresh while the app is open | timer | `Timer`/`Task.sleep` in `.active` phase | foreground loop, cancelled in background |

The Android-only settings that must not be faked on iOS: "background update interval",
"battery optimisation exemption", "foreground service notification", "widget refresh
frequency". Replace the interval picker with an on/off switch and a sentence that explains the
platform, or omit it. A picker that stores a number nothing reads is defect catalog §27.

Minimal wiring:

```swift
// Info.plist: BGTaskSchedulerPermittedIdentifiers = ["dev.example.refresh"]
BGTaskScheduler.shared.register(forTaskWithIdentifier: "dev.example.refresh", using: nil) { task in
    handleRefresh(task as! BGAppRefreshTask)
}

func scheduleRefresh(after minutes: Int) {
    let request = BGAppRefreshTaskRequest(identifier: "dev.example.refresh")
    request.earliestBeginDate = Date(timeIntervalSinceNow: Double(minutes) * 60)
    try? BGTaskScheduler.shared.submit(request)
}
```

`earliestBeginDate` is a floor, not a schedule. Anything the UI says about cadence has to be
"at most", never "every".

## 5. The cache lives in the store, and it is testable

```swift
@Observable final class ForecastStore {
    private var cache: [Place.ID: Fetched<Weather>] = [:]

    func weather(for place: Place, force: Bool = false) async throws -> Weather {
        let moved = cache[place.id].map { distance($0.value.place, place) } ?? .infinity
        if !force, !isStale(cache[place.id], policy: .mainWeather, movedMetres: moved),
           let hit = cache[place.id]?.value { return hit }
        let fresh = try await provider.fetch([.forecast, .current], at: place)
        cache[place.id] = Fetched(value: fresh, at: .now)
        return fresh
    }
}
```

Tests that pay for themselves:

- same place, 2 min later, no force → **no** network call (count calls in a fake provider);
- 6 min later → one call;
- place moved 6 km → one call even 1 min later;
- provider throws, cache exists → returns stale value and exposes the error;
- provider throws, no cache → throws.

## 6. The alarm that iOS actually does better

Upstream schedules two daily notifications: today's forecast at 07:00 and tomorrow's at 21:00
(both configurable). That is a cron job, and on iOS it is exactly
`UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 7, minute: 0), repeats: true)` —
no background task needed, no battery cost, and it fires even when the app has not run. Do not
build a background-refresh pipeline for what the notification scheduler does natively.

The *content* still has to be fetched, so compose the notification from the last cached
forecast and label it "as of <time>" if it is older than a few hours.

## 7. Gate

- [ ] Every feature has a validity rule, and the rule is a value in a test.
- [ ] The 5 km coordinate rule exists.
- [ ] Views never fetch; stores do, and the store takes an injectable clock for tests.
- [ ] A failed feature does not blank the others; stale data is shown with its age.
- [ ] Background refresh is `BGAppRefreshTask` **or** explicitly absent from settings.
- [ ] Nothing in the UI promises a refresh cadence the OS does not guarantee.