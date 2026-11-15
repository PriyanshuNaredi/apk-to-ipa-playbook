# 12 — The source layer: 74 integrations behind one interface

Breezy Weather talks to **9 worldwide + 59 national weather services**, plus 3 location
sources, 1 place-search service and 3 reverse-geocoding services. All of it sits behind four
small interfaces, and the selection rules are the part a port is most likely to skip — because
a screenshot cannot show which provider produced the number.

This port hardcoded one provider. That is a legitimate scope decision, but it silently deleted
a whole subsystem, and the deletion showed up later as three separate bugs (a pollen
coverage gate that looked arbitrary, no fallback when a request failed, and an air-quality
failure that blanked the card instead of restoring the last good value).

---

## 1. The interfaces

```kotlin
interface Source { val id: String; val name: String; fun getGroup(location, feature): Int }

abstract class HttpSource : Source {
    abstract val privacyPolicyUrl: String
    open val attributionLinks: Map<String, String> = emptyMap()
    abstract val continent: SourceContinent
}

interface FeatureSource : Source {
    val supportedFeatures: Map<SourceFeature, String>   // feature → attribution text
    fun isFeatureSupportedForLocation(location, feature): Boolean = true
    fun getFeaturePriorityForLocation(location, feature): Int = PRIORITY_NONE
    fun getAttributionIcon(): Int? = null
}

interface LocationSource : Source { fun requestLocation(context): Observable<…>; val permissions: Array<String> }
```

`SourceFeature` is a closed set of eight capabilities, not a per-endpoint flag:

```
FORECAST  CURRENT  AIR_QUALITY  POLLEN  MINUTELY  ALERT  NORMALS  REVERSE_GEOCODING
```

Each provider declares which it supports **and the attribution string per feature**, so
Open-Meteo maps `FORECAST`/`CURRENT`/`MINUTELY` to the weather attribution and
`AIR_QUALITY`/`POLLEN` to the Copernicus one. Attribution is therefore data, not a licence
paragraph someone remembers to add at release time.

## 2. The selection rule (the bit that is easy to miss)

```kotlin
PRIORITY_HIGHEST = 100; HIGH = 75; MEDIUM = 50; LOW = 25; LOWEST = 0; NONE = -1
```

- `isFeatureSupportedForLocation` decides *geographic* availability. Open-Meteo's pollen is
  gated on CAMS's bounding box (`COPERNICUS_POLLEN_BBOX.contains(lat, lng)`); a national
  service returns false outside its country.
- `getFeaturePriorityForLocation` ranks providers for that location. `>= 0` means
  "recommended here", `-1` means "possible but not recommended".
- Sources are grouped for the picker as **Recommended → Worldwide → continent (collated by
  locale)**, and inside "Recommended" sorted by descending priority — never alphabetically.
- Sources that need an API key are `ConfigurableSource`; unconfigured ones are shown but
  disabled. `NonFreeNetSource` is hidden in F-Droid builds. `RemovedSource` is shown so a
  saved location can be repaired instead of silently breaking.
- Selection is **per feature and per location**: a location can take its forecast from one
  provider, its air quality from a second, its alerts from a third.

## 3. Porting it to Swift, minimally but honestly

Even with one provider, build the seam — it costs ~80 lines and it is what makes the second
provider a file, not a refactor.

```swift
public enum SourceFeature: String, Codable, CaseIterable {
    case forecast, current, airQuality, pollen, minutely, alert, normals, reverseGeocoding
}

public protocol WeatherProvider: Sendable {
    var id: String { get }
    var name: String { get }
    var continent: Continent { get }
    var supportedFeatures: [SourceFeature: String] { get }   // feature → attribution
    func isSupported(_ feature: SourceFeature, at place: Place) -> Bool
    func priority(_ feature: SourceFeature, at place: Place) -> Int
    func fetch(_ features: Set<SourceFeature>, at place: Place) async throws -> ProviderPayload
}

public struct SourceResolver {
    public static let highest = 100, high = 75, medium = 50, low = 25, lowest = 0, none = -1

    /// Highest-priority provider that supports the feature here; nil = not covered.
    public func provider(for feature: SourceFeature, at place: Place,
                         among providers: [any WeatherProvider]) -> (any WeatherProvider)? {
        providers
            .filter { $0.isSupported(feature, at: place) && $0.priority(feature, at: place) >= 0 }
            .max { $0.priority(feature, at: place) < $1.priority(feature, at: place) }
    }
}
```

Then the two tests that matter, written before the second provider exists:

```swift
func testResolverPrefersHigherPriorityProvider() { … }
func testResolverReturnsNilWhenNoProviderCoversFeature() { … }
```

The second one is the test this port lacked: "no coverage" is a **fact the UI must be able to
render**, not a nil that becomes a zero. See `../04_patterns/DEFECT_CATALOG.md` §26.

## 4. Failure semantics are per feature, not per request

Upstream's rules, from `breezy-weather/docs/UPDATES.md` and the update service:

| Situation | Behaviour |
|---|---|
| A feature's request fails | attempt to **restore previously saved data for that feature only**; other features still update |
| Current weather fails | fall back to the current-hour forecast, unless the current value is < 30 min old |
| Whole refresh fails | keep the location's last successful data, show the error next to the timestamp |
| Coordinates moved > 5 km | ignore caches; full refetch |
| Source removed for this location | mark it, keep the data, offer repair in settings |

An all-or-nothing refresh (`if any request fails, show the error screen`) is simpler and
wrong: it throws away air quality because pollen timed out.

Model it explicitly:

```swift
public struct FeatureResult<Value> { public let value: Value?; public let stale: Bool; public let error: String? }
```

and let the card ask for `result.value` while the header asks `is any feature stale` to
decide whether to show the "updated 2 h ago" line in an error colour.

## 5. API keys and per-provider configuration

Upstream splits "configuration" from "settings": a provider owns its own preference
keys (Open-Meteo: which models; Météo-France: which model; AccuWeather: key), rendered by a
`SourcePreferences` composable the provider supplies.

If you port more than one provider you will need this, so decide the shape early:

```swift
protocol ConfigurableProvider {
    var isConfigured: Bool { get }
    func configurationView() -> AnyView      // or: [ProviderSetting] rendered by a generic form
}
```

The generic-form route (`[ProviderSetting]` with `.toggle/.picker/.secureField`) keeps
SwiftUI out of your data layer and is testable; the `AnyView` route is fewer lines but
unreachable from tests. Prefer the data.

## 6. What one provider costs, measured

| Work | Weather port (1 provider, 1 endpoint per feature) | This port (1 provider, 6 endpoints) |
|---|---|---|
| Provider protocol + resolver | none — direct client | ~80 lines, 2 tests |
| Request builder | 1 | 3 (forecast, air quality, geocoding) |
| Response mapping | ~250 lines | ~700 lines |
| Fixtures | 1 recorded response | 3 recorded responses |
| Attribution/licence plumbing | 1 text file | 3 text files + UI screen |

Adding a second provider is then: request + response + mapping + one `supportedFeatures` map +
one priority function + fixtures. Roughly 300–500 lines, no UI changes.

## 7. Gate

- [ ] There is a `WeatherProvider` protocol, even with one implementation.
- [ ] `SourceFeature` is a closed enum shared by UI and clients.
- [ ] Attribution is a value returned per feature, and the licences screen reads it.
- [ ] "Not covered here" is representable and rendered as words, not as `0`.
- [ ] Failure is per feature: stale values survive, and the UI can say which are stale.
- [ ] Resolver tests exist and pass — including the "no provider" case.