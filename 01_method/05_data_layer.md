# Stage 5 — Data layer

Port the data layer before any screen. It is the part where the Android source is nearly
literal (HTTP, JSON, files, caches), and the part where a silent difference is hardest to spot
once UI is in the way.

## Four layers, in dependency order

```
Client (transport)  →  Repository (policy: cache, refresh, prune)  →  Codec (wire ↔ model)  →  Projection (model ↔ view)
```

**Client** — one place that knows the base URL, parameters and status handling. Keep the Android
parameter *names* (`current`, `forecast_days`, `timeformat`, `cell_selection`); a rename is a
behaviour change you cannot test against recorded responses.

**Repository** — the policy layer: cache-first vs network, staleness windows, eviction, pruning,
cancellation. This is where the parity spec rows cluster (900 s staleness, 15-minute refresh,
48 MiB of tiles, prune-to-saved-cities).

**Codec** — decode the exact wire format, including its cruft. Do not "improve" field names or
types semantically; keep a translation table in the file.

**Projection** — turn the wire model into the screen's model (units, rounding, localisation,
phrases like "Feels like"). Keeps UI free of conversion logic and makes units testable without a
view.

## Rules that survived this port

1. **Record real responses and replay them.** Every logic test decodes a captured payload. You
   then never need a network for CI, and a schema change shows up as a failing decode rather
   than a blank screen.
2. **Cache keys come from the original.** Tile cache namespaces keyed per radar frame
   (`cacheNamespace: frame.path`) came from the Android behaviour of clearing and re-adding
   layers. Colouring keys by "layer type" caused stale frames to flash.
3. **Prune on save, not on read.** The original prunes forecast cache entries to the saved-city
   set every time cities are saved. Ported as-is: it is O(n) on a tiny set and it bounds disk
   growth without a GC pass.
4. **Atomic writes.** Android uses `AtomicFile` with fail-write rollback; iOS uses
   `.atomic` `Data.write`. Both mean: a crash mid-write cannot leave a corrupt cache that the
   app then trusts.
5. **Fractional budgets are policy, not constants to tune.** 48 MiB of tiles, 30-minute
   temperature-grid validity, 900 s forecast staleness — copy them, then test them
   (`maxDiskBytes = 48 * 1024 * 1024` with an eviction test).
6. **Cancellation is part of the contract.** Any repository call the UI can abandon must be
   cancellation-aware. Two of this port's worst defects lived here; see
   `../02_case_study/DEFECTS.md` D3/D4.

## The two defects this layer produced

**O(n²) dedupe.** `Array.uniqued` rebuilt the array per element; fine at 10 items, wrong as a
pattern. `Set`-based dedupe is the fix; the lesson is to grep the original for the idiom and port
its *intent* with iOS's data structures.

**Numeric ids read as strings.** GeoNames city ids arrive as JSON numbers. `row["id"] as? String`
always failed, so every city silently fell back to a `"lat,lon"` key — cache friction that would
have shown up much later as "the app forgets the forecast sometimes". Kotlin's `optString`
accepted numbers, so parity required stringifying numbers on the Swift side.

Both were invisible in the UI until measured. That is the argument for doing this layer first.

## The tile cache is the interesting case

Android delegates tiles to MapLibre's OkHttp disk cache (48 MiB). There is no MapLibre on iOS
here, so the port had to build the equivalent: an LRU memory index plus a disk budget, with
eviction that runs when the budget is exceeded — not a full re-sort of the index per stored tile
(the audit caught that one; D11).

If your port replaces a library, replicate its *resource policy* explicitly, or memory behaviour
will drift until a real device punishes you.

## Exit gate

- Every endpoint has a recorded-response test.
- Cache eviction is tested against a byte budget, not asserted in a comment.
- Persistence survives a relaunch test with the same data.
- Cancelling a repository call leaves no continuation unresolved (test the timeout).