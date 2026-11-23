# 18 · The port you do not rewrite

Stages 1–17 assume the Android app is Kotlin and the iOS app will be Swift. Most APKs are not
that. A large share of the Play Store is a C++ engine (Unity, Unreal, cocos2d-x, axmol, Godot)
with a thin platform layer, and for those the right move is not a rewrite at all: it is
**cross-compiling the same source for iOS and replacing only the platform layer**.

Port 3 of this playbook — [Bim!](https://github.com/j-jorge/bim) at version 17 — was done that
way. The game is 300 000 lines of C++ on axmol, and the port adds one app target, four patches
and 21 scripted edits. No game code was reimplemented, so there is no parity gap to close and
nothing to diff screenshot by screenshot. The failure modes are completely different from a
rewrite, which is why they get their own document.

**Choose this route when** you can identify the engine, the upstream source is available under
a licence that allows a derivative (AGPL here, so the port ships the same licence), and the
engine already supports iOS. **Do not choose it** to avoid reading a licence, and do not
choose it for a Compose app dressed up with an NDK library — the surface is Kotlin and stages
1–17 apply.

---

## What changes in the stage map

| Stage | Rewrite (1–17) | Engine port |
|---|---|---|
| 1 Recon | screens, keys, calls | the same, **plus** engine identification and the exact upstream commit |
| 2 Source recovery | decompile, read | give the decompiled APK to the *upstream source*, not to a rewrite; read the platform layer for what the APK does that the source does not |
| 3 Parity spec | Android behaviour → iOS implementation | Android behaviour → **which upstream file already implements it** → what the port adds |
| 4 Scaffolding | app project + tests | a cross-compilation tree: toolchain file, dependency stack, one app target, an empty window |
| 5 Data layer | rewrite the repositories | nothing to do — it is the same code, minus the parts that talk to the platform |
| 6 UI port | rebuild the screens | nothing to do — the layout data ships in the APK's assets |
| 7 Custom rendering | reimplement the canvas | confirm the engine's renderer is Metal, and that its **compiled shaders travel in the bundle** |
| 8 Verification | logic + UI + visual audit | build both architectures, run it in the simulator, and drive it with seams (§below); the visual audit becomes a safe-area and asset audit |
| 9 Release | IPA from xcodebuild | IPA from `cmake --build` output; there is no `.xcassets`, no icon until you make one |
| 10 Retrospective | defects of the rewrite | defects of the *toolchain*, which is a different catalog (see §50–§58) |

The compression is real: recon, pinning and verification carry the port; the middle stages
collapse. The effort moves into the toolchain, and the toolchain is where you will lose days.

---

## 1. The pin is not the tag

The APK's manifest says `versionName = "17"`. The obvious move is to check out the `v17` tag
and build. That builds a different game.

The APK was built from the **end** of the version-17 line: the tag is 73 commits behind, and
the APK's style data references a screen and a popup (player profile, nickname editor) that do
not exist at the tag. What found it was not reading the changelog, it was diffing the APK's own
assets against the source tree's style declarations and noticing a widget the source could not
have produced.

**Do this:** take a string or asset the source tree defines in one place only, find the last
commit where the APK matches, and pin that. Record why in a decisions file, with the commit
before and after.

---

## 2. Dependencies are part of the port

The upstream pins a version of everything in `setup/dependencies/recipes/*.sh`. All of it has to
be built for iOS before the game links: the engine, a C++ HTTP stack, a JSON library, an ECS,
a gettext reader, the platform-services library. Two rules learned the hard way:

* **One source of truth per version.** The Boost version appeared in four places (the tree, the
  tarball URL, the CMake package directory name, the version reported to `find_package`), and
  one of them said 1.89 while the rest said 1.91 — so a stale tree from an earlier pin stayed
  in place and linked against a Boost the game was not pinned to.
* **Report the package the way upstream reports it.** Hand-writing the `BoostConfig.cmake`
  upstream's own setup would generate produced `Boost_FOUND FALSE` on a Boost that was
  present, building and linked. Write the file with the project's conventions, not yours.

---

## 3. The engine's ABI is a switch, and it is not in your build

axmol is a C++ framework with an ABI-affecting compile definition (`AX_*` flags). The library
was configured one way and the app target another, and the result was a link that succeeded
into a crash on the first widget. The lesson generalises: **anything that changes the ABI must
be passed by every stage of the build**, and a build system that lets each stage have its own
flags will silently mix two.

The same class produced the crash that the pin fixed: a widget dereferencing a null
`ref_ptr<Node>` because the version-17 layout code and the version-18 style data disagreed
about a field.

---

## 4. Shaders must travel in the bundle

The APK ships GLES shaders. iOS needs Metal, compiled by the engine's own `axslcc`. The port
must build them and copy the compiled bytecode **into the bundle**, at the path the engine
looks for. Missing them is not a link error and not a compile error; it is a black screen or a
missing sprite, which reads as a graphics bug and is a packaging bug.

---

## 5. The simulator cannot press buttons — build seams, not synthetic taps

Two facts, both checked: `simctl` has no input API, and on a machine without Accessibility
permission (`AXIsProcessTrusted()` false) synthetic `CGEvent` clicks are dropped. A port that
cannot press its own buttons can only be verified up to the first screen.

`getenv`-gated seams in the game's own event handlers fix that: `BIM_AUTOPLAY`,
`BIM_AUTOFIGHT`, `BIM_AUTORETURN`, `BIM_AUTOPRESS`, plus `BIM_AUDIOLOG`/`BIM_AUTOMUTE`/
`BIM_AUTOEFFECT` for audio. Inert when unset, so a seam-bearing build behaves like a plain one,
and they were worth it: one unassisted run went lobby → authentication → matchmaking against a
live server → arena → result → second match.

Two rules for seams, both learned by breaking them:

* **Put the seam where the user acts, not where the object is built.** A "return to lobby" seam
  scheduled from the result screen's *constructor* fired while the match was still running,
  pressed NEW GAME before a result existed, and left a blank oversized arena. The screen is
  constructed long before it is shown; the seam belongs in `displayed()`.
* **A seam cannot replace a click that carries meaning.** The arena seams call handlers
  directly, so no click sound is ever requested — which is why the audio check needed an
  effect-playing seam rather than hoping a match would produce one.

---

## 6. Layout data is data: fix the notch in the assets, not the frame

Insetting the canvas into the safe area is right for a list app and wrong for a game whose
backdrop *bleeds off screen by design*. The port instead rewrites a copy of the APK's
`style/application.json`, lowering every `anchor.reference.y` between 0.90 and 0.99 by the
safe-area fraction and leaving the 1.0 anchors alone. The art still reaches every edge and the
settings gear is 210 px below the top instead of 128 px.

This is the engine-port version of "the look is in the layouts" (§37): you still do not invent
geometry, you adjust the number that the original author wrote.

---

## 7. Release has no `.xcassets`, no icon, and no Xcode

A `cmake`-built bundle has no asset catalog, so:

* **the home-screen icon does not exist** until you generate a flat PNG set and list it under
  `CFBundleIcons`. The APK's own `ic_launcher` is the source (one 432 px bitmap, no vector —
  check the adaptive-icon XML before assuming otherwise);
* **the plist keys Xcode injects are yours to write**, and `CFBundleSupportedPlatforms` missing
  reads as "not supported on this device" at install time;
* **orientation and minimum OS come from the Android manifest**, not from taste;
* **nothing is signed**. An unsigned IPA installs through SideStore or LiveContainer, which
  re-sign on the device with the user's own Apple ID.

---

## 8. Verification that is honest about what it cannot see

Three claims a simulator cannot settle: audibility, haptics, and device performance. Do not
report them as verified. Do not report them as broken either — measure one layer down (did the
audio API create a source? does the haptic file exist in the target's file list?) and put the
device check on a written checklist with, for each step, what a failure would mean.

The check that paid off here was the cheapest one: sample two rows of pixels after every plist
change. An unresolvable launch screen put the app in compatibility mode — black bands, artwork
scaled wrongly, a huge glow over the menu — and it looked exactly like a renderer bug for hours
before the pixels said "you are not full screen".

---

## Exit gate for this route

* Both architectures build: `ARM64 SIMULATOR=FALSE` and the host's own simulator arch.
* The tree is generated from a script, and the script **fails loudly** if a patch point is
  missing (see §57 — a silent no-op cost two rounds of debugging).
* A fresh `git clone` builds with the commands in the README, because everything needed is
  either tracked or fetched by a script (§56).
* The bundled IPA is checked as an artefact: arch, the ten installer keys, no
  `_CodeSignature`, icon files present.
* Every claim in the README is either run and evidenced, or listed as not verified.
