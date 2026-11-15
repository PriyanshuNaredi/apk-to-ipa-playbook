# Recon summary

Artifact: `Weather_v1.1.1.apk`  
SHA-256: `49a502b2b2747c6cd6bf10e2d8ace1dad832d1e645e31b935e014ef8417199c1`  
Recon: 2026-11-15

## Scale

- App package: `dev.kiankonrad.weather`
- App classes: **43** java files, **18450** lines of decompiled Java (the porting surface)
- Note: decompiled Java overstates the Kotlin source (imports, lambda expansion, braces).
  Compare *file counts* against the port, not line counts.
- Bundled library classes: 19228 (dependencies, not ported)

## Framework shape

- Compose (androidx.compose.*) - declarative
- No app-owned fragments (library hits ignored)
- No DI framework in app classes

## Structural markers

```
LazyColumn             1
verticalScroll         2
horizontalScroll       1
HorizontalPager        1
SharedPreferences      1
Canvas                 2
AndroidView            1
MapView                1
OkHttp                 2
AtomicFile             1
```

## What to read first

1. `03-permissions.txt` - permissions with no iOS equivalent are scope changes, not ports.
2. `08-markers.txt` - scroll containers per screen, and whether the app is Compose or Views.
3. `05-strings.txt` - the copy is parity; copy it, do not paraphrase.
4. `09-decompiled` - then one entry point, top-down.

## Gates before stage 3

- [ ] Checksum recorded (above)
- [ ] Permission deltas listed as decisions, not surprises
- [ ] Screen graph written down from component + marker evidence
- [ ] Compose vs Views decided (changes stage 6 entirely)
- [ ] Obfuscated or not (short-named file count above)
