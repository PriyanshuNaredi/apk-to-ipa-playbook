# What REA is, and how it was used here

**REA** = `rea-agents`, an MIT-licensed reverse-engineering analysis toolkit by
[morluto](https://github.com/morluto/rea) (v6.9.0 here). It is a CLI (plus an optional MCP
server) that wraps the tools you would otherwise drive by hand — jadx for bytecode, apktool for
resources — and exposes their answers as JSON.

Why that matters for a port: a decompiler gives you a *tree of files*. A port needs *answers* —
"which activity is the launcher", "how many `LazyColumn`s exist in this class", "what does
`saveCities` actually write". REA answers those as structured data you can cite in a parity spec.

## What it provides

| Command | Output | Used for |
|---|---|---|
| signature | APK signing certificate facts | Recording which build was analysed |
| manifest | decoded `AndroidManifest.xml` | Activities, permissions, launcher entry |
| package inventory | every class, as JSON / text | Size assessment, dependency shape (19,287 classes) |
| class dump | members, annotations, string constants | Constants (timings, URLs), Compose structure |
| method dump | bytecode-level view of one method | Explaining behaviour without trusting decompiled prose |
| resources | compiled resource table | Strings, colours, drawables (incl. vector icon paths) |

## How it was installed (and what it must never touch)

The setup report is vendored at `03_rea/evidence/REA_SETUP_REPORT.md`. The rules that made it
acceptable to use:

1. **Project-local only.** `npm install --prefix 07_tools/rea-analysis/rea rea-agents@6.9.0` —
   `node_modules` never left the project.
2. **No global config writes.** `npx rea-agents setup` would register an MCP server into agent
   config files (`.claude.json`, `.codex/config.toml`, VS Code/Gemini/Claude Desktop configs).
   **Not run.** REA was used as a plain CLI.
3. **Runtime gate respected, not bypassed.** System Node 25.1.0 is outside REA's engines range
   (`^22.23.4 || ^24.22.1 || >=26.12.1`). Instead of patching the gate or changing the system
   Node, a portable Node v24.22.1 was extracted into the project.
4. **Tarball inspected before install.** Entry script, module layout and the jadx bridge were read
   first; the bundled `jadx-headless-mcp` jar is upstream and unmodified.

Generalisable rule: an analysis tool that wants to edit your agent configuration is asking for
more access than the analysis needs. Use the CLI, keep it in the repo, don't let it write outside.

## What it was used for in this port

REA produced 50 evidence files (vendored in `evidence/`, indexed in `EVIDENCE_INDEX.md`):

- **A structure map before any reading**: `out-package.json`, `out-classes.json`,
  `app-classes.txt` — which classes exist, and therefore which questions to ask.
- **Behaviour that the readable source left ambiguous**: the refresh policy, the pager identity,
  the back-handling order, the layer-clear timing (`out-m-*.json` method dumps).
- **Structural facts that become architecture**: single activity, no navigation library, the
  bottom bar living inside the weather branch, marker counts per scroll container.
- **The icon**: resource extraction gave the launcher's vector `pathData`, which the port
  renders directly (`05_tools/make-app-icon.swift`) instead of redrawing by hand.

The conclusions were then written up as three analysis documents, also vendored:

| File | Content |
|---|---|
| `ORIGINAL_APK_DEEP_ANALYSIS.md` | Areas A–E: UI architecture, weather screen, data layer, memory, parity risks — every line citing source or a dump |
| `MEMORY_AND_UI_FINDINGS.md` | Android's memory model vs the iOS port, plus the UI guarantees Android structurally provides |
| `ANDROID_IOS_PARITY.md` | 12-row Android↔iOS comparison with divergences, plus "why scrolling worked on Android and failed on iOS" post-mortems |

## Honest limits

- REA reads bytecode; it does not run the app. Anything about *runtime* behaviour (does the loop
  really refresh?) still needs a device, a log or a test.
- Decompiled Compose code is genuinely hard to read — nested lambdas and positional calls. The
  method dumps answered the specific questions; nobody read them end-to-end.
- If the APK is obfuscated, REA's answers are still useful but names stop meaning anything; keep a
  mapping table (`../01_method/02_source_recovery.md`, Situation C).