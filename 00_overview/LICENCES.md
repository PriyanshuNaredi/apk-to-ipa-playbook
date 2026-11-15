# Licences: what a port inherits

A port is a derivative work. The licence of the app you port decides what you may ship, what you
must ship with it, and sometimes what you may call it. Check this **before** the first commit, not
before the release — it changes naming, repo visibility and file headers.

## The classes you will actually meet

| Upstream licence | Port must be | Must publish source? | Naming/trademark | Practical effect |
|---|---|---|---|---|
| **MIT** | anything, but keep the notice | no | none | Cheapest. Weather 1.1.1 was MIT: the port stayed MIT with an attribution footer and CREDITS.md |
| **Apache-2.0** | Apache-2.0 (or compatible) | no | patent grant, no trademark grant | Keep `NOTICE`; mark modified files |
| **BSD-3** | keep copyright + no-endorsement clause | no | **no endorsement by the original author** | The "no endorsement" clause is the one people forget in the App Store listing |
| **GPL-3.0** | GPL-3.0 | **yes, to recipients** | no trademark grant | Distribution (App Store included) triggers source obligations |
| **LGPL-3.0** | LGPL-3.0 | yes for the library/derived work | no trademark grant | What Breezy Weather uses. Weaker copyleft than GPL, but a *port* is a derivative work, not mere linking, so the derived code is LGPL |
| **AGPL-3.0** | AGPL-3.0 | yes, **including network users** | no trademark grant | A back end behind the app counts as use |
| **No licence / "all rights reserved"** | nothing | — | — | You may not port it. This is the answer regardless of how tempting the idea is |
| **Proprietary / closed APK** | — | — | — | Porting is a licensing question with the rightsholder, not an engineering one |

Two traps that are not visible in the licence table:

1. **`LICENSE_ADDITIONAL` / `NOTICE` / `TRADEMARKS` files.** Breezy ships `LICENSE_ADDITIONAL` with
   a no-misrepresentation clause and a trademark disclaimer. Result: the port can exist, but it must
   be visible as a *modified* version and must not present itself as Breezy Weather or use its logo
   as the app's identity. Hence the port is named `Gust` with a "based on Breezy Weather 6.2.2"
   attribution, not "Breezy Weather for iOS".
2. **Bundled third-party assets.** Icon packs, map styles, fonts and data providers often have their
   own terms. The APK's `assets/` and `res/` carry no licence metadata; the upstream repo's
   `3RD_PARTY.md` (or equivalent) does — read it during recon, not after the UI is done.

## How this shows up in the repository

- **File headers.** Every Swift file states the licence and the upstream origin. It is tedious and
  it is exactly what a licence audit checks first.
- **`CREDITS.md`** — upstream author and project, the licence of each, and every service used
  (data providers, tiles, geocoding) with its own terms. A port that quietly ships somebody's API
  without attribution is a support problem waiting for the first complaint.
- **Repo visibility.** Copyleft does not forbid a private repository, but the *distributed binary*
  must come with source for its recipients. Decide where that source lives before you publish the
  IPA, not after.
- **The app icon.** Rendered from the upstream vector (as Weather's was) only when the licence
  permits it and the mark is not a trademark you may not use. When in doubt, draw a new icon.

## A rule for the assistant, not the code

Do not treat "it's open source" as "we can ship it however we like". Read the licence file in the
APK's upstream repo during **stage 1**, write the finding into the parity spec, and raise the naming
question with the owner early — it is a one-line decision then, and a rebrand later.
