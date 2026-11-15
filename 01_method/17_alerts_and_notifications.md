# 17 — Alerts and notifications: the rules, not just the banner

Alerts are the one feature a weather app gets blamed for. Miss a red warning and the user
notices; send six of them and the user turns notifications off forever. Breezy encodes a set
of exact rules, and they are the part worth porting even when the alert *provider* is not in
scope.

This port omitted alerts entirely (no provider in its single-source scope sends any) and wrote
that into the deviations table. That is defensible **only** because the rules below are known
and can be implemented later against the same model.

---

## 1. The model, per severity

```kotlin
data class Alert(
    val alertId: String,          // source id, or hash(type, level, start) when absent
    val startDate: Date?, val endDate: Date?,
    val headline: String?,        // HTML allowed in description; \n → <br/>
    val description: String?, val instruction: String?,
    val source: String?,
    val severity: AlertSeverity = UNKNOWN,
    @ColorInt val color: Int,
)
```

| Severity | Colour (upstream literal) |
|---|---|
| EXTREME | `rgb(212, 45, 65)` |
| SEVERE | `rgb(240, 140, 17)` |
| MODERATE | `rgb(244, 207, 0)` |
| MINOR | `rgb(57, 156, 199)` |
| UNKNOWN | `rgb(130, 168, 223)` |

`alertId` is the identity used for de-duplication. When a source gives none, upstream
constructs one from **type or title + level + start time** — deliberately, so that "same
warning, updated text" stays one alert rather than becoming a new one.

## 2. The notification rules (from `breezy-weather/docs/UPDATES.md`)

Sent only after a **background** refresh, and only for the **first location**:

| Condition | Result |
|---|---|
| severity MINOR | no notification |
| severity UNKNOWN | notification (unknown is treated as possibly serious) |
| alert already known, text or severity edited | no notification |
| source removed the alert and created a new one | new notification |
| location is not the first location | no notification |
| the alert source does not cover this country | no notification |
| setting "Notifications of weather alerts" off | no notification |

Plus a separate precipitation notification: only when minute-by-minute data exists, only first
location, only if the source covers the place, only if its setting is on.

The asymmetry is the design: **background and first location only**. A manual refresh never
notifies, because the user is looking at the screen.

## 3. Channels and scheduling

| Android channel | Importance | Contents |
|---|---|---|
| `alert` | HIGH | severe weather alerts |
| `forecast` | DEFAULT | daily forecast at 07:00 and 21:00 (both configurable) |
| `widget` | DEFAULT | notification-widget |
| `background` | MIN | "refreshing…", background failures |
| `app_apk_update_channel` | — | new version available (Android-only concept) |
| `crash_logs` | — | crash log export (Android-only) |

Forecast notifications are **calendar alarms**, not background work. On iOS that is
`UNCalendarNotificationTrigger` and it needs no `BGTaskScheduler` at all — see
`13_refresh_and_cache.md` §6.

## 4. Porting to `UNUserNotificationCenter`

```swift
enum NotificationKind: String, CaseIterable { case alert, forecast, precipitation, background }

func requestAuthorisation() async -> Bool {
    (try? await UNUserNotificationCenter.current()
        .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
}

/// Alert diffing must be idempotent: same alertId, same content → no request.
func notify(_ alerts: [WeatherAlert], place: Place, alreadyShown: Set<String>) async {
    let newOnes = alerts.filter {
        alreadyShown.contains($0.id) == false && $0.severity != .minor
    }
    for alert in newOnes {
        let content = UNMutableNotificationContent()
        content.title = alert.headline ?? String(localized: "alert.title")
        content.body = alert.description?.strippingHTML() ?? ""
        content.userInfo = ["route": "alert", "alertId": alert.id, "placeId": place.id]
        content.interruptionLevel = alert.severity == .extreme ? .timeSensitive : .active
        let request = UNNotificationRequest(identifier: "alert.\(alert.id)", content: content,
                                           trigger: nil)   // immediate
        try? await UNUserNotificationCenter.current().add(request)
    }
}
```

Three things to get right:

1. **Deduplicate by `alertId`**, and persist the shown ids. `UNUserNotificationCenter` already
   replaces a request with the same identifier — use that, and still keep the set so the body
   is not re-sent after the user clears it.
2. **Deep-link.** Put `route` in `userInfo` and route it in
   `userNotificationCenter(_:didReceive:)`; a notification that opens the app to the main
   screen instead of the alert is the most common complaint about weather apps.
3. **`.timeSensitive` needs the entitlement** (`com.apple.developer.usernotifications.time-sensitive`)
   and a reason; do not set it for every notification. `EXTREME` only.

## 5. The alert card on the main screen

Upstream pins the alert block to the top and refuses to let the user hide it
(`CardDisplay.CARD_ALERTS` is not in the default list and the settings screen excludes it).
Do the same: an alert card is not a preference.

Layout that survives long text: headline (2 lines, bold), severity chip with the colour above,
then "until 18:00" or the day+time range, then a disclosure to a full-screen detail. The
description is HTML — strip tags for the card, render formatted text in the detail, and never
`Text(html)` into a `Text` view (it shows markup).

## 6. Alert-worthy vs not

If you later add alerts from a provider, the single biggest quality lever is the severity
mapping. Providers disagree on names ("Warning", "Advisory", "Orange"). Map them to the four
levels in one table, in code, once:

```swift
func severity(from providerLevel: String) -> AlertSeverity {
    switch providerLevel.lowercased() {
    case "red", "extreme", "take action": .extreme
    case "orange", "severe", "warning":   .severe
    case "yellow", "moderate", "advisory": .moderate
    case "blue", "minor": .minor
    default: .unknown
    }
}
```

Unknown is **not** "ignore": upstream notifies unknown, and shows it in the neutral colour.

## 7. Gate

- [ ] Alert model with `alertId`, start/end, description, source, four severities + unknown.
- [ ] Severity → colour table copied as literals, with a test.
- [ ] De-duplication by `alertId`, and a stable fallback id when the source has none.
- [ ] Notifications: background only, first location only, MINOR suppressed, unknown allowed.
- [ ] Notification payload carries a route and it is handled.
- [ ] Forecast notifications use `UNCalendarNotificationTrigger` at the user's chosen times.
- [ ] The alert card cannot be hidden, and is at the top of the stack.
- [ ] If alerts are out of scope: the deviations table says which provider would have to be
      added, and the settings row is absent rather than disabled.