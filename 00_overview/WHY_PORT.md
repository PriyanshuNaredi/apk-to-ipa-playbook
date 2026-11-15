# Why port an APK to a native IPA at all

Before the method, the decision. A port is the most expensive option on this list, so it has
to earn it.

## The options, honestly

| Option | Effort | Fidelity | Longevity | When it wins |
|---|---|---|---|---|
| **A. Native rewrite (this playbook)** | High — every screen hand-built | Highest: platform-native gestures, typography, performance | Best: no framework between you and the OS | The app is the product; you will maintain it for years |
| **B. Kotlin Multiplatform (share logic, native UI)** | Medium-high | High | Good, but you now own two UI codebases and a shared module boundary | Existing team is Kotlin-heavy and wants both platforms first-class |
| **C. Compose Multiplatform** | Medium | Medium: iOS rendering is Compose's, not UIKit's | Medium — you inherit Compose-iOS's gaps | UI is simple, team size is 1–2, iOS is a checkbox |
| **D. Flutter / React Native rewrite** | Medium | Medium: platform look has to be faked | Medium | You are rewriting anyway and want one codebase |
| **E. Web wrapper** | Low | Low | Low | Throwaway internal tool |
| **F. Ship the APK on Android only** | Zero | — | — | Perfectly valid. Ask this first |

## Why A was right here

1. **There was readable MIT source.** Porting a Compose app when you can read
   `MainActivity.kt` is translation, not archaeology. Option A's usual risk — guessing at
   behaviour — mostly disappeared.
2. **The app is mostly drawing.** A custom map renderer, a 13-frame radar loop, an
   interpolated temperature layer. Framework options (C/D) would have fought the framework
   on exactly these screens; SwiftUI + CoreGraphics did not.
3. **The original was small.** 2,144 lines of Kotlin. A rewrite is only reckless at scale.
4. **Fidelity was the requirement**, not "an iOS version". Screens, wording, colour stops
   (`#765BD5 → #CC427D`), timings (700/1300 ms), cache budgets (48 MiB) had to match.

## When you should not do this

- The APK is obfuscated *and* you have no source: you will be guessing at behaviour, and
  every guess costs a test you cannot ground.
- The app is 50k+ lines with a server contract you do not control: port the client, but budget
  months, not days.
- The Android app is a thin WebView already: port the web app instead (option E).
- You need both platforms from one team, forever: pick B or C deliberately, not by accident.

## What a port actually costs (measured here)

| Phase | Share of the work | Notes |
|---|---|---|
| Reading the original and writing the parity spec | ~20% | Cheapest phase, highest leverage |
| Data layer + persistence + cache | ~15% | Mechanical once the spec exists |
| Screens | ~30% | Fast until layout equality is enforced |
| Custom rendering (map/canvas) | ~20% | The only phase with real unknowns |
| Verification, visual audit, defect fixing | ~15% | Where the port stops lying to itself |

Two thirds of the schedule is translation. The last third — making it *indistinguishable* — is
where ports fail, and it is why `../01_method/08_verification.md` exists.