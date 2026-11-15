# Compose → SwiftUI: paste-grade equivalents

The patterns that recur, with the port's actual implementations. Where the two frameworks only
*look* equivalent, that is called out — those rows are the defect sources.

## State

| Compose | SwiftUI | Note |
|---|---|---|
| `remember { mutableStateOf(x) }` | `@State private var x = …` | Same lifecycle (view-scoped) |
| `rememberSaveable { … }` | `@SceneStorage("key")` | Compose survives process death; `@State` does not — a real parity gap if you forget |
| `remember(key) { … }` | `.id(key)` on the view, or a keyed subview | Rebuild identity, not value |
| `derivedStateOf { … }` | computed property | Never store derived state beside its source |
| `mutableStateListOf<T>()` | `@State private var items: [T] = []` | Mutate the array, do not mutate elements in place |
| ViewModel `StateFlow` | `@Observable` class + `@State` ownership | One instance, injected down; do not recreate per body pass (see D1) |
| `collectAsStateWithLifecycle()` | `.onChange` + owned model | No automatic lifecycle binding; cancel explicitly |

**The trap**: Compose tolerates a state write during composition far more freely than SwiftUI.
Writing state from `init`, from a `body` computation, or from a model's initialiser creates an
invalidation loop. This port burned 100% of a core that way.

## Effects and lifecycle

| Compose | SwiftUI | Note |
|---|---|---|
| `LaunchedEffect(key)` | `.task(id: key)` | Both cancel and restart on key change — but cancellation is cooperative; loops must check `Task.isCancelled` |
| `DisposableEffect(Unit)` | `.onAppear` / `.onDisappear` | `onDisappear` is the only reliable cancellation point |
| `LaunchedEffect(Unit) { while(true) }` | `.task { while !Task.isCancelled }` | Unguarded `while true` outlives the view; it never stops |
| `repeatOnLifecycle(RESUMED)` | `scenePhase` + explicit start/stop | iOS has no structured equivalent; you own the state machine (see D17) |
| `rememberCoroutineScope()` | `Task {}` with an owner, or `.task` | Detached tasks are invisible leaks |
| `snapshotFlow` | `.onChange(of:)` | Values, not flows |

**The trap**: `withTaskGroup` is not a timeout. It awaits *every* child, so a "race the operation
against a sleep" timeout built with it never fires. Use `withTaskCancellationHandler` and resolve
the continuation from `onCancel`.

## Layout

| Compose | SwiftUI | Note |
|---|---|---|
| `Column(Modifier.verticalScroll())` | `ScrollView { VStack }` | One vertical scroller per screen |
| `Row(Modifier.horizontalScroll())` | `ScrollView(.horizontal) { HStack }` | A different axis; do not wrap it in a pager |
| `LazyColumn` | `LazyVStack` in `ScrollView` | `Lazy*` only where the original used it |
| `Arrangement.spacedBy(12.dp)` | `HStack/VStack(spacing: 12)` | |
| `Modifier.weight(1f)` | `.frame(maxWidth: .infinity)` | |
| `Spacer()` | `Spacer()` | |
| `Box` + `Alignment` | `ZStack(alignment:)` | Overlays compete for hit-testing; prefer siblings |
| `Modifier.fillMaxSize()` | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | |
| `Modifier.padding(12.dp)` | `.padding(12)` | 1 dp ≈ 1 pt at default scale (both ~1/160 vs 1/163 inch) |
| `Modifier.height(112.dp)` | `.frame(height: 112)` | |
| `ConstraintLayout`-ish equal heights | `Grid` + `GridRow`, or `LazyVGrid` | `.frame(maxHeight:)` cannot equalise inside a `ScrollView` |
| `Surface`/`Card` wrapping a column | container view with modifiers **inside** | A `@ViewBuilder` tuple is not a container (D8) |
| `HorizontalPager(state, key = { items[it].id })` | `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)` + `ForEach(items, id: \.id)` | Keep the original's identity key; indices recycle the wrong page |
| `PullToRefreshBox` | `.refreshable` (where available) or custom | Parity gap if absent; document it |

## Drawing and custom views

| Compose | SwiftUI | Note |
|---|---|---|
| `Canvas { drawRect/drawPath }` | `Canvas { context, size in … }` | Coordinate space is top-left, y-down, in both |
| `drawPath(path, color)` | `context.fill(Path, with: .color)` | |
| `Modifier.fillMaxSize()` + `pointerInput` | `.gesture(DragGesture)` | `translation` is cumulative — diff against the last frame |
| `detectTransformGestures` | `MagnificationGesture` + `DragGesture` via `.simultaneousGesture` | Pinch and pan must be simultaneous or they cancel |
| Compose vector from an XML `pathData` | `CGPath` built from the same commands | `05_tools/make-app-icon.swift` parses M/L/C/A/Z, including endpoint→centre arc conversion |
| Layer opacity (`FillLayer(opacity = .42f)`) | `.opacity(0.42)` on the overlay view | Keep the literal |

## Text, colour, units

| Compose | SwiftUI | Note |
|---|---|---|
| `stringResource(R.string.x)` / literal | literal, copied exactly | Copy is parity |
| `Color(0xFF765BD5)` | `Color(red: 0x76/255, green: 0x5B/255, blue: 0xD5/255)` | Or an asset colour; keep the hex in a comment |
| `MaterialTheme.typography.bodyLarge` | `.font(.body)` | Sizes diverge; if parity matters, use explicit sizes |
| `LocalConfiguration.current` | `GeometryReader` / `@Environment(\.horizontalSizeClass)` | |
| `fontScale`-aware compact layout | Dynamic Type via relative fonts | iOS equivalent only if you build it |
| `Build.VERSION.SDK_INT` branches | `if #available(iOS 18, *)` | |
| `NumberFormat`/`SimpleDateFormat` | `DateFormatter` **cached** (never per render) | Formatter allocation per row is a measurable cost (D5) |
| `Locale`-aware `String.format` | `String(format:locale:)` | Use the user's locale for display, POSIX for wire values |

## Persistence and files

| Android | iOS |
|---|---|
| `SharedPreferences` | `UserDefaults(suiteName:)` — or a file for anything structured |
| `AtomicFile` + `startWrite/finishWrite/failWrite` | `Data.write(to:options: .atomic)` |
| `cacheDir` | `FileManager.default.urls(for: .cachesDirectory)` — or Application Support if it must survive restore |
| `context.filesDir` | `.applicationSupportDirectory` |
| 48 MiB OkHttp disk cache | own LRU: index + byte budget + eviction when over |
| `Instant`/`System.currentTimeMillis()` | `Date`/`ContinuousClock`; keep epoch seconds for wire parity |

## Navigation and back

| Compose | SwiftUI |
|---|---|
| `when (screen)` over an enum | `switch viewModel.screen` in a `ViewBuilder` |
| `BackHandler(enabled) { … }` | `onBack` closure + explicit button; no system back on iOS gesture-only |
| Manual `rememberSaveable` screen | `@SceneStorage` or an explicit restoration test |

## Chrome: bars, sheets, and what a test can see

The material-to-SwiftUI translation is the easy half. The half that silently changes the product is
container choice and bar treatment.

| Android | SwiftUI | Trap |
|---|---|---|
| `MaterialCardView` + `app:shapeAppearance` | `RoundedRectangle(cornerRadius:)` or `Circle()` behind a `ZStack` | A circle drawn behind a taller `VStack` lets the content spill outside the circle. `ZStack { Circle(); content }` with `aspectRatio(1, .fit)` keeps content inside |
| `MaterialCardView` with no shape attribute | plain background, no shape | "Every card is rounded" is an assumption; three containers in the measured upstream have no shape at all |
| Activity with up button + overflow menu | `NavigationStack` + leading/trailing `ToolbarItem` | Do not fill the vacuum with a `TabView`. If upstream has no bottom navigation, a tab bar is a new feature (§40) |
| App bar tinted with the weather colour | `.toolbarBackground(color, for: .navigationBar)` | A colour that depends on loaded data is captured before the data exists and never re-applied; store nothing, choose a news-free treatment and record the deviation (§41) |
| `startActivity` to a settings screen | `.sheet { }` | A sheet whose content has its *own* `NavigationStack` swallows the presenter's `Done` toolbar item. Either the screen owns its dismiss button (`.toolbar` inside its stack, driven by an `onDone` closure) or the sheet does not wrap it again |
| `RecyclerView` with `LinearLayoutManager(VERTICAL)` | `ForEach` in a `VStack` | Check the column width and item height in `dimens.xml` first; a horizontal strip and a vertical list look identical in a thumbnail (§39) |
| Icon from `res/drawable` by computed name | `UIImage(named:)` on a bundled asset | Loose PNGs copied by the resources phase are not in `Assets.car`; load them via `Bundle.main.path(forResource:ofType:)` + `UIImage(contentsOfFile:)`, or convert to an asset catalogue. A silent fallback symbol hides the mistake |

### Making accessories testable

| Want | Works | Does not work |
|---|---|---|
| Identify a card | identifier on the `NavigationLink`, with `.accessibilityElement(children: .contain)` | identifier on a `VStack` inside it — the link collapses the subtree |
| Identify a metric | identifier on the leaf `Text` | identifier on the container `HStack` |
| Tap the overflow menu | `Button` + `confirmationDialog` | `Menu` in a toolbar: the tap is treated as a scroll and can fail with `kAXErrorCannotComplete` |
| Tap a back button | `app.navigationBars["Appearance"].buttons.firstMatch` | `app.navigationBars.buttons.firstMatch` — matches the presenter's bar under a sheet |

## Verification equivalents

| Need | Android | This port's iOS answer |
|---|---|---|
| Logic tests | JUnit | Swift Testing + XCTest, host target, <1 s |
| UI tests | Espresso / Compose test rule | XCUITest with accessibility labels |
| Screenshot baseline | Paparazzi / Roborazzi | scripted UI test writing named PNGs |
| Performance budget | Macrobenchmark | `ps aux` idle CPU + `sample` |
| Crash/behaviour trace | logcat | `DiagLog` session file in Application Support |