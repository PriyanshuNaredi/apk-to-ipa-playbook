# Metrics — how each number was measured (so you can reproduce or dispute it)

Numbers without a method are decoration. Everything here has a command.

## Idle CPU

```bash
ps aux | grep "[W]eatheriOS.app/WeatheriOS" | awk '{print $3}'   # %CPU of one core
sample <pid> 2                                                   # stack profile when it is high
```

On macOS, `ps -o %cpu,rss` is rejected in the form it works on Linux; the `awk` column above is
the reliable read. Measured 30 s after launch, with the app foregrounded on the forecast screen.

| State | Value |
|---|---|
| Before the fix | ~100% (one core saturated) |
| After | 5.7% |
| After the tile-cache and formatter fixes | 5.4% (clean-clone run) |

Diagnosis when it was high: `sample` showed the time in `ForecastPageModel` construction and the
view-model callback, which is what led to the `init` → `.task` change.

## Test counts and runtime

```bash
./07_tools/macos-tests.sh all      # prints Executed N tests per layer + RESULT
./07_tools/macos-tests.sh logic    # 59 XCTest + 28 swift-testing, ~0.9 s
```

The suite is split so the fast loop stays fast. The UI layer takes ~5 minutes because it drives a
real simulator; the visual audit class is excluded from normal runs with `-skip-testing:`.

## Visual audit coverage

```bash
./07_tools/visual-audit.sh    # fails if fewer than 10 screenshots export
ls 07_logs/shots/audit/       # audit-01 … audit-10
```

The failure mode this guards: an earlier version silently exported zero attachments and the script
still exited 0. Ten named captures is the contract; they are copied into
`06_evidence/screenshots/` here.

## Radar playback (temporal behaviour)

```bash
C=$(xcrun simctl get_app_container <udid> dev.kiankonrad.weather data)
grep "radar frame" "$C/Library/Application Support/weather-diag/"session-*.log
```

Produced: `frames 2/13` … `13/13` with timestamps, then nothing — i.e. the window plays once and
stops. The 0.7 s cadence and 13-frame count are also visible in those timestamps, which is how the
"~10 s" figure is justified rather than estimated.

## Tile cache budget

```bash
grep maxDiskBytes 05_ios_port/WeatheriOS/Sources/WeatheriOS/Models/TileCachePolicy.swift
# static let maxDiskBytes = 48 * 1024 * 1024
```

Behaviour is tested against a byte budget in the logic suite, not asserted in prose.

## Release artifact

```bash
./07_tools/ipa-build.sh
# OK: …/Weather-1.1.1-6-unsigned.ipa   size 1.2M   sha256 8aeb7c61…
unzip -l <ipa> | head        # Payload/WeatheriOS.app/…
codesign -dv Payload/WeatheriOS.app 2>&1     # "code object is not signed at all"
otool -l Payload/WeatheriOS.app/WeatheriOS | grep -c LC_CODE_SIGNATURE   # 0
lipo -archs Payload/WeatheriOS.app/WeatheriOS                             # arm64
```

## Source and test volume

```bash
find 05_ios_port/WeatheriOS/Sources -name "*.swift" | wc -l          # 30
find 05_ios_port/WeatheriOS/Sources -name "*.swift" -exec wc -l {} + # 6,079
find 00_original/source/Weather -name "*.kt" -exec wc -l {} +        # 2,144
```

## What is *not* measured

- **Device performance.** No physical iPhone was available; every performance number is simulator
   + host logic.
- **Memory under pressure.** The cache policy is tested; a real memory warning was never induced.
- **Battery.** Not measured. The idle-CPU figure is a proxy, and it is the proxy that mattered.
- **Screenshot diff scores.** Captures were reviewed by eye and by a vision model, not by pixel
   diffing against Android screenshots (no Android device was available to produce baselines).