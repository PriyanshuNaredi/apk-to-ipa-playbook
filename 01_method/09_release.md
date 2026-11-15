# Stage 9 — Release

An unsigned IPA is the honest artifact for a port you cannot sign: no Apple ID, no team, no
certificate in CI. It is also the artifact SideStore and LiveContainer were built to accept.

## Build it unsigned, on purpose

```bash
xcodebuild -project WeatheriOS.xcodeproj -scheme WeatheriOS \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

Then package `Payload/<Name>.app` into a ZIP named `.ipa`, and strip anything Xcode left that must
not ship (`__preview.dylib`, `WeatheriOS.debug.dylib`, `_CodeSignature`, `embedded.mobileprovision`).

## Prove it is unsigned — in the build, not in the release notes

Four independent checks, all failing the build if they disagree with the claim:

```bash
LISTING="$(unzip -l "$IPA")"                    # no _CodeSignature, no provisioning profile
[[ "$LISTING" == *"Payload/WeatheriOS.app/WeatheriOS"* ]]   # executable actually inside
unzip -tq "$IPA"                                            # archive not corrupt
codesign -dv "$STAGE/Payload/WeatheriOS.app" 2>&1 | grep "not signed"
otool -l "$STAGE/Payload/WeatheriOS.app/WeatheriOS" | grep -c LC_CODE_SIGNATURE  # → 0
```

**`Learned:`** the first version of these checks reported failures that were not there:
`unzip -l | grep -q` and `codesign -dv | grep -q` exit at the first match, the producer takes
SIGPIPE, and `set -o pipefail` turns a *successful* match into a failed pipeline. Capture output
into a variable and compare strings instead of piping into `grep -q`.

## Document the install path, or the artifact is useless

A reader who downloads an unsigned IPA and double-clicks it gets nothing. The README and the
release notes must say, in this order:

1. **This IPA is unsigned.** No Apple ID, certificate or profile is inside it.
2. **What that means**: it cannot be installed with Finder/Xcode and will not launch on its own.
3. **How to install**: [SideStore](https://sidestore.io/) (signs with your Apple ID, refreshes the
   7-day certificate) or [LiveContainer](https://github.com/LiveContainer/LiveContainer) (runs apps
   in a container; ships a combined SideStore build).
4. **What the free account limits are** — 3 active apps, 10 new App IDs per 7 days, 7-day
   certificates — so the first refresh does not look like a bug.
5. **How to verify the download**: the `.sha256` next to the `.ipa`.

## Automate it

CI on a macOS runner: build → upload the IPA as a workflow artifact → on `v*` tags, create the
GitHub release with the install notes. Pin the runner image (`macos-15`) because the iOS SDK is a
build input; a moving `latest` will break a port silently at some future date.

Guard rails worth having in CI:

- `xcodegen --version || brew install xcodegen` (the tool is a build input too).
- Fail if no `.ipa` was produced (`if-no-files-found: error`).
- Publish the SHA-256 into the run summary, so a released binary is attributable.
- `workflow_dispatch` so you can build on demand without inventing a tag.

## Physical-device honesty

An unsigned IPA does **not** prove the app runs on hardware. This port never ran on a real iPhone
(no team available). Say so in the README rather than letting a release page imply otherwise —
"simulator-verified, device-unverified" is a claim a reader can act on.

## Exit gate

- `.ipa` exists, `arm64`, and every unsigned check passes.
- `.sha256` published next to it.
- README + release notes explain the install path with links and the account limits.
- CI reproduces the artifact from a tag.