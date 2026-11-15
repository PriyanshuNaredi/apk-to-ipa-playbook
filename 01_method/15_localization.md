# 15 — Localization: 63 human languages, one launch language

Breezy ships **1,162 English strings** across **63 language directories** (plus regional
variants `en-rGB`, `pt-rBR`, `zh-rCN`, `zh-rTW`, `nb-rNO`, …), one plurals file, and four
right-to-left locales: `ar`, `fa`, `he`, `ur`. Across all locales the resource files hold
**39,756** translated strings.

A port that ships English-only is not "the same app in another language"; it is a different
product for most of the people who used the original. And the damage is not only visible: an
English-only layout hides truncation that a German or Finnish string exposes immediately.

---

## 1. What upstream does that is trivially portable

| Android | iOS |
|---|---|
| `res/values/strings.xml` | `Localizable.xcstrings` (String Catalog) or `en.lproj/Localizable.strings` |
| `values-de/strings.xml` | `de.lproj/Localizable.strings` |
| `values/plurals.xml` `<plurals quantity>` | String Catalog plural variants (`one`/`other`, plus `zero`/`two`/`few`/`many` where the language needs them) |
| `values-ar/` layout mirroring | automatic with leading/trailing constraints; **manual** for any drawing done in `Canvas` |
| `contentDescription` | `.accessibilityLabel` |
| `READ_APP_SPECIFIC_LOCALES` + `AppLocalesMetadataHolderService` | iOS 13+ per-app language in Settings; requires the app to declare `CFBundleLocalizations` |
| `LocalePreferences.getTemperatureUnit()` | `Locale.current.temperatureUnit` (see `14_units_and_locale.md`) |
| `getFormattedTime(location, context, is12Hour)` | `Date.FormatStyle` with an explicit `timeZone` |

The layout mirroring point is the one that costs money: everything SwiftUI does with
`.leading/.trailing` mirrors for free, and everything drawn by hand (compass arrows, wind
barbs, our `TrendChart`, upstream's `Canvas`-drawn snowflakes) does not. Test an RTL locale on
the two or three screens that draw.

## 2. Order of work when you cannot translate 1,162 strings

1. **Extract all strings before writing behaviour-dependent tests.** A literal `"Feels like"`
   inside a view is invisible to extraction tooling and to translators; a string key is not.
2. **Key by meaning, not by English text**: `header.feelsLike`, not `"Feels like"`. This port's
   identifier convention (`header.feelsLike`, `cardLink.daily`, `settings.appearance`) doubles
   as the test hook — one vocabulary for keys, identifiers and tests.
3. **Ship English + the two or three locales your testers speak**, machine-translated and marked
   `unreviewed` in the catalog. Upstream's translations are community-reviewed; do not
   pretend yours are.
4. **Localize the screenshot-visible shell first**: header, card titles, settings sections,
   unit names, weekday/month names. That is ~120 of the 1,162 and it is what "the app is in my
   language" means to a user.
5. **Never localize** provider data (condition text from the API), place names, or units-as-ids.

## 3. Plurals, and the language that breaks naive code

The single upstream plurals entry is instructive:

```xml
<plurals name="notification_update_error">
    <item quantity="one">%1$d update failed</item>
    <item quantity="other">%1$d updates failed</item>
</plurals>
```

English needs two forms. Polish needs four (`one/few/many/other`), Arabic six, and Japanese
one. If the port contains `"\(n) update\(n == 1 ? "" : "s") failed"`, it is wrong in every
language that is not English — and it is wrong *in English too* for `n == 0` in a strict
sense ("0 updates failed" is fine; "0 update failed" is not).

In a String Catalog the entry carries the variants; in Swift:

```swift
String(localized: "notification.updateError \(count)", defaultValue: "^[\(count) update](inflect: true) failed")
```

or, without automatic grammar agreement:

```swift
String(localized: "notification.updateError", bundle: .main,
       plural: .init(count: count))    // "1 update failed" / "7 updates failed"
```

Either way the plural logic lives in the resource, not in an `if`.

## 4. Truncation is a test, not a review

The three longest English strings in upstream are 302, 293 and 262 characters; German and
Finnish compound words inflate titles by 30–40 %. Both failure modes are visible in one
pseudo-locale run:

```bash
# Double every string length and wrap it in brackets, like Apple's own pseudo-language
xcodebuild test -scheme Gust \
  -testLanguage en -testRegion ZZ \
  -only-testing:GustUITests/ShellTests
```

If a title truncates into "Precipitat…" in pseudo-locale, it will in German. Two cheap rules:
give labels `.lineLimit(2)` and `.minimumScaleFactor(0.8)`, and prefer wrapping over ellipsis
for anything a user reads rather than a value.

## 5. Dates, times and the time-zone bug everyone ships

Upstream formats every time with the **location's** time zone, never the device's:

```kotlin
currentDate.getFormattedTime(location, context, context.is12Hour)   // uses location.timeZone
```

This port shipped a version that used the device zone; a forecast for Tokyo viewed from
Berlin showed Berlin hours. The fix is a model property, not a formatter option sprinkled at
call sites:

```swift
extension Weather {
    var timeZone: TimeZone { TimeZone(identifier: raw.timezone) ?? .current }
}

var timeFormat: Date.FormatStyle {
    var f = Date.FormatStyle(date: .omitted, time: .shortened)
    f.timeZone = weather.timeZone
    return f
}
```

Test it with a fixed pair: a Tokyo forecast formatted while the test process is in
`Europe/Berlin` must say `09:00`, not `02:00`.

## 6. The accessibility labels are strings too

Upstream's `contentDescription`s are localized. In this port every card and control has an
`accessibilityIdentifier` (for tests) **and** a spoken label; the label is the localized string,
the identifier is stable English. Conflating them produces a VoiceOver user hearing
`cardLink.daily`, which is defect catalog §24 seen from the other side.

## 7. Gate

- [ ] No user-visible string literals in view code; every one is a key.
- [ ] String Catalog (or `.strings`) exists for at least English, and the shell is translated
      for one non-English locale as proof the pipeline works.
- [ ] Every count string uses plural variants.
- [ ] A pseudo-locale UI run has been made and any truncation fixed.
- [ ] All times and dates are formatted in the **location's** zone, tested against a fixed pair.
- [ ] `CFBundleLocalizations` declares the shipped languages so per-app language appears in Settings.
- [ ] RTL is checked on every hand-drawn view, not only on text-heavy screens.
- [ ] Accessibility labels are localized; identifiers are not.