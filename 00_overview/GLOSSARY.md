# Glossary — the words used across this repo

**APK** — Android application package: a ZIP containing `classes.dex` (bytecode), resources,
manifest and native libs. What you distribute on Android.

**IPA** — iOS application archive: a ZIP containing `Payload/<Name>.app/`. What you distribute
on iOS — but see *unsigned*.

**Unsigned IPA** — an IPA whose app bundle carries no code signature (`_CodeSignature`,
`embedded.mobileprovision`) and whose Mach-O has no `LC_CODE_SIGNATURE`. iOS refuses to launch
it as-is; it must be signed by the installer's own Apple ID. Every artifact this playbook
produces is unsigned, on purpose: signing needs a team and a certificate, neither of which a
CI runner should hold.

**SideStore** — an on-device app store/signer (AltStore fork, no AltServer needed). It signs
your unsigned IPA with your own Apple ID and refreshes the 7-day development certificate over
Wi-Fi. <https://sidestore.io/>

**LiveContainer** — runs apps inside a container so each app does not consume one of the 3
free-account slots; distributes a combined `LiveContainer + SideStore` build.
<https://github.com/LiveContainer/LiveContainer>

**REA (`rea-agents`)** — reverse-engineering analysis CLI/MCP server (MIT,
[morluto/rea](https://github.com/morluto/rea)). Wraps jadx and apktool behind commands that
dump signature, manifest, package inventory, and per-method bytecode as JSON. Used in the case
study for evidence; see `../03_rea/WHAT_REA_IS.md`.

**jadx** — DEX → Java decompiler. **apktool** — resource-manifest unpacker (keeps the original
resource IDs and `res/` layout).

**Compose** — Jetpack Compose: declarative Android UI toolkit. The mental model maps to SwiftUI
more closely than the API names suggest; see `../04_patterns/COMPOSE_TO_SWIFTUI.md`.

**Remembers / state** — Compose `remember`/`rememberSaveable` ≡ SwiftUI `@State` /
`@SceneStorage`. Compose `LaunchedEffect(key)` ≡ `.task(id:)`. Compose `derivedStateOf` ≡ a
computed property. These equivalences are where most port bugs come from, because they are
*almost* the same.

**LaunchedEffect(key)** — a coroutine scoped to the composition, restarted when `key` changes.
Its SwiftUI twin is `.task(id:)`, which *cancels and restarts* — and cancellation is cooperative,
so a loop that ignores cancellation leaks. Two defects in the case study came from exactly this.

**Invariant / invalidation loop** — a SwiftUI `@Observable` model writing state during
`init` or during view evaluation, which marks the view dirty, which re-evaluates, which writes
again. On this port it ran at 22 Hz and pinned a CPU core. Compose tolerates some of this;
SwiftUI punishes all of it.

**Parity gate** — a test or capture that proves an Android behaviour survived translation. The
playbook's rule: a screen is not done until its gate exists.

**Visual audit** — a scripted UI test that navigates every surface and writes named
screenshots, so layout claims can be checked by eye and by a vision model, not memory.

**Idle CPU budget** — the percentage of one core the app burns doing nothing. This port's
budget: <6%. It caught the worst defect in the codebase.