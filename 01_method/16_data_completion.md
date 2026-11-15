# 16 — Data completion: the forecast a source does not send

Every provider sends a subset. Breezy's `RefreshHelper` turns what arrived into a complete
weather object in four named passes, and each pass contains a rule a port will otherwise
implement three different ways in three different views.

The four passes, in order (from `RefreshHelper.calculateFeaturesData`):

```kotlin
// 1) fill hours/days back to yesterday 00:00 using previously stored data
// 2) compute every derivable hourly value (weather code, text, dew point, feels like, …)
// 3) build daily objects from hourly + air quality + pollen + sunshine
// 4) complete hourly from daily (UV, isDaylight) and attach hourly air quality
```

## 1. Backfill: "today" needs yesterday

```kotlin
val yesterdayMidnight = Date(Date().time - 1.days.inWholeMilliseconds)
completeNewWeatherWithPreviousData(newWrapper, location.weather, yesterdayMidnight, …)
```

A 7-day forecast fetched at 14:00 covers today from 14:00. The hourly chart should still show
00:00–14:00, so the storage keeps the previous fetch's hours and grafts them in, discarding
anything older than yesterday midnight. Consequences for a port:

- Storage holds **more** than what the UI shows: at least 48 h of hourly.
- The "hourly" list is `past + future`, and the view starts at the current hour, not at index 0.
- `fullNextHourlyForecast` is defined as `date >= now - 1 h`, so the current hour is included even
  when the source timestamps it a few minutes in the past:

```kotlin
val fullNextHourlyForecast = hourlyForecast.filter {
    it.date.time >= System.currentTimeMillis() - 1.hours.inWholeMilliseconds
}
```

That `- 1 hour` is the difference between a chart whose first point is the current hour and one
that starts one hour late, every hour of the day.

## 2. `todayIndex` — the rule that is not "index 0"

```kotlin
val todayIndex = dailyForecast.indexOfFirst { it.date.time > Date().time - 1.days.inWholeMilliseconds }
```

Daily entries are dated at local midnight, and "today" is **the first entry newer than 24 hours
ago**, not the first entry in the list and not the entry whose date is today's calendar date.
The three readings differ at 00:30 local, on a DST shift, and when a provider sends
"yesterday" as its first row.

If a port uses `daily[0]`, then at 00:10 the header shows yesterday's max temperature. This is
the kind of defect that only shows up in a screenshot taken at the wrong hour — so make it a
test:

```swift
func testTodaySkipsYesterdayEntryAtLocalMidnight() {
    // entries: [2024-05-01T00:00Z, 2024-05-02T00:00Z]; now = 2024-05-02T00:10Z
    XCTAssertEqual(forecast.todayIndex, 1)
}
```

## 3. Derivable values: derive once, in the model

`computeMissingHourlyData` fills what sources omit. The portable set, with the identities:

| Value | Rule |
|---|---|
| Dew point from `T`, `RH` | Magnus: `γ = ln(RH/100) + a·T/(b+T)`, `Td = b·γ/(a−γ)`, `a=17.62`, `b=243.12` |
| Humidity from `T`, `Td` | inverse of the above |
| Feels-like | heat index when `T ≥ 27 °C`, wind chill when `T ≤ 10 °C` and wind > 4.8 km/h, else `T` |
| Wet-bulb | Stull's approximation from `T`, `RH` |
| Weather code | from cloud cover + precipitation type/amount + visibility when the source has no code |
| Condition text | from the code |
| Is-daylight | source flag if present, else `sunrise ≤ t ≤ sunset` |
| UV index per hour | daily UV distributed to the peak hour |
| Sunshine duration | from cloud cover and daylight length |

Two portability notes:

- **Derive in the model layer, not the view.** Three views that each compute feels-like will
  disagree at the boundary, and the disagreement is a one-star review: "the header says 12° but
  the detail says 13°".
- **Keep "absent" distinguishable from "derived".** If a port writes `0` where a source sent
  nothing, the card shows a confident zero — the same class of bug as pollen coverage
  (`../04_patterns/DEFECT_CATALOG.md` §26). Use an optional, or an enum
  `Value.known(x) / derived(x) / missing`.

## 4. Computed astronomy

Sunrise, sunset, moonrise, moonset and moon phase are computed locally, not fetched. The port's
`MoonPhase` uses the mean synodic month (29.530588853 days) from a reference new moon, which is
accurate to a few hours — enough for an 8-name phase label, not enough for an eclipse time.

For sun times, upstream calls `SunMoonCalculator`; in Swift the shape is:

```swift
struct SunMoon {
    static func sunrise(_ date: Date, at place: Place) -> Date?   // nil above the polar circles
    static func sunset(_ date: Date, at place: Place) -> Date?
    static func phase(_ date: Date) -> MoonPhase                  // 8 names + illumination
}
```

Test at: the equator, Berlin in June and December, Tromsø in June (**no sunrise — return nil,
do not invent one**) and a known new moon (2024-04-08).

## 5. Normals and degree days: the climatology you probably cannot port

Upstream shows "2° above normal" and heating/cooling degree days. Both need a monthly climate
normal per location (`Normals`, refreshed only when this month is missing). With a single public
forecast API you usually have none, so:

- do **not** subtract "the forecast average of the visible days" and call it normal — that is a
  different, meaningless number;
- omit the rows and put them in the deviations table, with the sentence "requires monthly
  climate normals that this port's provider does not publish";
- if you do have climatology, keep the formula in a tested function:
  `deviation = value − normal`, and degree days `max(0, 18 − Tmean)` / `max(0, Tmean − 18)`.

## 6. Validity, and why "stale but valid" exists

```kotlin
fun isValid(pollingIntervalHours: Duration?): Boolean   // used to decide if a cached Weather may be shown
```

A weather object carries six timestamps: forecast, current, air quality, pollen, minutely,
alerts (plus normals' coordinates). A port that stores one timestamp cannot answer "may I show
this?" per feature, and ends up either refetching everything or showing hour-old air quality
with a fresh timestamp. Store them as a small struct:

```swift
struct FetchedAt { var forecast, current, airQuality, pollen, minutely, alerts: Date? }
```

## 7. Gate

- [ ] Hourly storage reaches back to yesterday 00:00; the view starts at `now − 1 h`.
- [ ] `todayIndex` is the first entry newer than 24 h ago, with a test at 00:10 local.
- [ ] Derivable values are computed in the model, once, with tests for dew point, feels-like
      and weather-code derivation at their boundaries.
- [ ] Absent ≠ zero: optional or three-state values everywhere a source can omit a number.
- [ ] Sun/moon return `nil` at the poles instead of inventing times; a phase test pins a known
      new moon.
- [ ] Per-feature fetch timestamps exist.
- [ ] Every unported completion feature (normals, degree days, …) is in the deviations table
      with its reason.