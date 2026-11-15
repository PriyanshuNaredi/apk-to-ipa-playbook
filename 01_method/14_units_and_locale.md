# 14 — Units, and the default nobody sets

Units look like a formatting problem and are actually a **behaviour** problem: the same
forecast must read `72°F`, `13 mph`, `29.92 inHg` for a user in Chicago and `22°C`, `21 km/h`,
`1013 hPa` for a user in Berlin, out of the same stored numbers, without a settings visit.

Breezy's `weather-unit` module is 35 files / 5,549 lines of pure Kotlin and has no Android
dependency except in formatting. It is the most directly portable module in the app; this
port copied its arithmetic and then got the *defaults* wrong, which no arithmetic test can
catch.

---

## 1. The model

Seven unit families, each an enum with an id, a display name and a conversion to a reference
unit: **temperature, speed, distance, pressure, precipitation, ratio (humidity), pollen /
pollutant concentration**.

Values are stored as `WeatherValue<Int64, Unit>` in reference units (Kelvin ×10, m/s in cm/s,
Pa, mm, percent) — integers, so there is no float drift between fetch and render, and no
"23.000000000000004 °C". Formatting happens once, at the edge, and takes a **width**:

```kotlin
enum class UnitWidth { NORMAL, SHORT, LONG, LONG_WITH_UNIT }   // "24", "24°", "24 °C", "24 degrees Celsius"
```

`useMeasureFormat` switches between `Locale`-aware `MeasureFormat` ("24 °C" with a
non-breaking space) and the app's own compact form ("24°"). Both exist because a headline
temperature and an accessibility label have different needs.

## 2. The defaults are per-locale and partly hand-written

```kotlin
fun TemperatureUnit.Companion.getDefaultUnit(locale: Locale): TemperatureUnit =
    when (LocalePreferences.getTemperatureUnit()) {
        CELSIUS -> CELSIUS; FAHRENHEIT -> FAHRENHEIT; KELVIN -> KELVIN
        else -> when (locale.country) {
            "BS", "BZ", "KY", "PR", "PW", "US" -> FAHRENHEIT
            else -> CELSIUS
        }
    }
```

The other five families ignore the OS preference and use hard country lists:

| Family | Country overrides | Else |
|---|---|---|
| speed | `CN DK FI JP KR NO NL PL RU SE` → m/s; `GB US` → mph | km/h |
| distance | `NL` → m; `GB US` → mile | km |
| pressure | `BR EG GB IL TH` → mbar; `MX RU` → mmHg; `US` → inHg; `CA` → kPa | hPa |
| precipitation | `BR` → cm; `US` → inch | mm |

Read the table twice. It encodes real editorial decisions (Norwegians use m/s; the Dutch read
distance in metres; Britons use miles but °C) that CLDR does not fully carry, which is exactly
why `breezy-weather/work/DEFAULT_UNITS_PER_COUNTRY.md` exists in the repo as a 249-row table waiting to be
completed.

## 3. The iOS default, done properly

iOS exposes the same information on `Locale` (iOS 16+, fine for a 17.0 target):

```swift
let locale = Locale.current
locale.measurementSystem     // .metric / .uk / .us
locale.temperatureUnit       // .celsius / .fahrenheit / .kelvin
locale.firstWeekday, locale.hourCycle
```

So the first-launch default is:

```swift
public enum UnitDefaults {
    public static func temperature(_ l: Locale = .current) -> TemperatureUnit {
        switch l.temperatureUnit {
        case .fahrenheit: return .fahrenheit
        case .kelvin:     return .kelvin
        default:          return .celsius
        }
    }
    public static func speed(_ l: Locale = .current) -> SpeedUnit {
        switch l.region?.identifier {           // .uk → mph, .us → mph, others metric
        case "GB", "US": return .milePerHour
        case "CN", "DK", "FI", "JP", "KR", "NO", "NL", "PL", "RU", "SE": return .metrePerSecond
        default: return .kilometrePerHour
        }
    }
    // distance, pressure, precipitation: same tables as upstream
}
```

Two portability notes:

- `measurementSystem == .uk` means "miles for distance, Celsius for temperature" — do **not**
  collapse it into `.us`.
- `region` can be nil; fall back to metric, never to US.

## 4. Where this bites: the property test that finds it

The defect in this port was a hardcoded `.celsius`, `.kilometrePerHour`, `.hectopascal`. It is
invisible in a Berlin simulator. Make it visible:

```swift
func testDefaultsFollowLocale() {
    for id in ["en_US", "en_GB", "de_DE", "fr_FR", "nb_NO", "nl_NL", "ja_JP", "pt_BR"] {
        let l = Locale(identifier: id)
        let t = UnitDefaults.temperature(l), s = UnitDefaults.speed(l)
        // en_US → °F + mph, en_GB → °C + mph, nb_NO → °C + m/s, pt_BR → °C + km/h
        XCTAssertEqual(Formatter.temperature(293.15, unit: t, locale: l).contains("F"),
                       id == "en_US", "temperature default wrong for \(id)")
        _ = s
    }
}
```

And a second one that catches a worse bug — defaulting the **display** while the stored value
stays in the wrong unit:

```swift
func testStoredReferenceUnitIsIndependentOfDisplayUnit() {
    let k = 293.15
    XCTAssertEqual(Formatter.temperature(k, unit: .celsius).prefix(3), "20°")
    XCTAssertEqual(Formatter.temperature(k, unit: .fahrenheit).prefix(3), "68°")
}
```

## 5. Formatting traps, in the order they will hit you

1. **Non-breaking space before the unit.** CLDR uses `\u{00A0}`. A UI test asserting `"24 °C"`
   with a normal space fails on a correct app.
2. **Rounding direction.** Upstream rounds half away from zero, not banker's rounding. `-0.4 °C`
   must render `0°`, not `-0°`.
3. **The unit belongs in its own accessible label.** The header shows a 92 pt number and a
   40 pt unit; a single `"24 °C"` element reads better and is what this port's first attempt
   got wrong (two elements, one of them unnamed).
4. **Wind speed has three common units plus Beaufort.** Beaufort is not a unit conversion, it
   is a table on **integer** cm/s — switching on truncated integers, as upstream does, is the
   difference between 5 and 6 Bft at the boundary.
5. **12/24-hour clock is a locale property, not a setting.** Provide a settings override (upstream
   does) but derive the default from `Locale.hourCycle`.
6. **Never format in the model.** Formats are locale- and width-dependent, models are not; a
   cached formatted string survives a locale change and stays wrong.
7. **Sub-zero Fahrenheit and negative zero** are the two values that break naive `String(format:)`
   code; add both to the test list.

## 6. Gate

- [ ] Five unit families (temperature, speed, distance, pressure, precipitation) plus ratio,
      each with an id, a display name and a reference-unit conversion.
- [ ] Defaults derived from `Locale`, tested against at least eight locales including `en_US`,
      `en_GB`, `nb_NO`, `pt_BR`.
- [ ] Formatting takes a width (`normal/short/long/longWithUnit`) and a locale, and is never
      cached.
- [ ] Stored values are in one reference unit and unit tests prove display independence.
- [ ] Negative zero, `-0.4`, `0`, and a unit boundary (Beaufort 5→6) are in the tests.
- [ ] A "Restore defaults" control exists, because a user who visited the pickers once can
      otherwise never get back to the locale default.