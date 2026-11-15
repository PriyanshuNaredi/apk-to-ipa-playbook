#!/usr/bin/env bash
# Stage-1/2 recon for an APK you do not have source for.
#
#   ./apk-recon.sh <app.apk> [outdir]
#
# Produces everything stage 1 (recon) and stage 2 (source recovery) need, in one
# directory you can commit as evidence:
#
#   <outdir>/00-checksum.txt      sha256 + size, so the analysed artifact is pinned
#   <outdir>/01-signature.txt     signing certificate: who built it, when
#   <outdir>/02-manifest.txt      decoded AndroidManifest.xml
#   <outdir>/03-permissions.txt   permissions with a first guess at the iOS equivalent
#   <outdir>/04-components.txt    activities / services / receivers / providers
#   <outdir>/05-strings.txt       user-visible strings from resources
#   <outdir>/06-resources.txt     resource table (colours, dims, drawables)
#   <outdir>/07-package.json      class inventory (scale assessment)
#   <outdir>/08-markers.txt       structural counts: Compose vs View, scroll containers
#   <outdir>/09-decompiled/       jadx output (Java-level, readable)
#   <outdir>/RECON.md             the summary a human reads first
#
# Deliberately does NOT run on the APK in place: everything goes to a copy-free
# read-only path, and no global tool config is written.

set -euo pipefail

APK="${1:?usage: apk-recon.sh <app.apk> [outdir]}"
OUT="${2:-$(basename "${APK%.apk}")-recon}"

[ -f "$APK" ] || { echo "no such file: $APK" >&2; exit 2; }

# Tool resolution: prefer a self-contained install in ~/.local/apk-tools (Temurin
# JDK + jadx + apktool jar, no sudo, no Homebrew). On x86_64 macOS, brew has no
# openjdk bottle, so `brew install jadx` compiles OpenJDK 27 and ~48 deps from
# source -- 30-60 minutes. The portable install is minutes and deletes cleanly.
APKTOOLS="${APKTOOLS:-$HOME/.local/apk-tools}"
if [ -x "$APKTOOLS/bin/jadx" ]; then
  # shellcheck disable=SC1091
  source "$APKTOOLS/bin/__env"
  export PATH="$APKTOOLS/bin:$PATH"
fi

for t in jadx apktool unzip openssl; do
  command -v "$t" >/dev/null || { echo "missing tool: $t -- install ~/.local/apk-tools (see 09_release notes) or brew install jadx apktool" >&2; exit 3; }
done

mkdir -p "$OUT"
echo "==> $APK"
echo "==> $OUT"

# --- 00 checksum (version fields appended after the decode step) --------------
{ echo "file:   $(basename "$APK")"
  echo "sha256: $(shasum -a 256 "$APK" | awk '{print $1}')"
  echo "size:   $(wc -c < "$APK" | tr -d ' ') bytes"
  echo "date:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "jadx:   $(jadx --version 2>&1 | head -1)"
  echo "apktool: $(apktool --version 2>&1 | head -1)"
  echo "java:   $(java -version 2>&1 | head -1)"
} > "$OUT/00-checksum.txt"

# --- decode resources once (manifest + strings + resources all come from this) --
DECODED="$OUT/decoded"
if [ ! -d "$DECODED" ]; then
  apktool d -f -q -o "$DECODED" "$APK" >/dev/null 2>&1 || echo "apktool decode failed" >&2
fi

# Package/version only exist after decoding, so they are appended to the pin file.
{
  echo "package: $(sed -n 's/.*package="\([^"]*\)".*/\1/p' "$DECODED/AndroidManifest.xml" 2>/dev/null | head -1)"
  VNAME=$(grep -E "versionName" "$DECODED/apktool.yml" 2>/dev/null | sed 's/.*versionName: //; s/"//g' | head -1)
  VCODE=$(grep -E "versionCode" "$DECODED/apktool.yml" 2>/dev/null | sed "s/[^0-9]//g" | head -1)
  echo "version: ${VNAME:-?} (code ${VCODE:-?})"
} >> "$OUT/00-checksum.txt"

# --- 01 signature ------------------------------------------------------------
# Most modern APKs carry no META-INF/*.RSA (v1 JAR signature) at all -- only a
# v2/v3 APK Signing Block between the file data and the central directory. So
# parse that block: scheme IDs are visible, and the embedded certificate can be
# handed to openssl. No apksigner, no Android SDK needed.
python3 - "$APK" > "$OUT/01-signature.txt" 2>&1 <<'PY'
import re, struct, subprocess, sys, tempfile, os

apk = sys.argv[1]
data = open(apk, 'rb').read()

# v1 JAR signature: any META-INF/*.RSA entry means the old scheme is present.
has_v1 = bool(re.search(rb'META-INF/[^/]*\.(RSA|DSA|EC)', data))
print(f'v1 (JAR) signature: {"yes" if has_v1 else "no"}')

eocd = data.rfind(b'PK\x05\x06')
if eocd < 0:
    print('no ZIP EOCD: not a valid APK'); sys.exit()
cd_off = struct.unpack_from('<I', data, eocd + 16)[0]

if data[cd_off - 16:cd_off] != b'APK Sig Block 42':
    print('APK Signing Block: absent')
    print('=> the APK is unsigned, or v1-only. Treat as a redistributed/repacked build.')
    sys.exit()

size = struct.unpack_from('<Q', data, cd_off - 24)[0]
start = cd_off - size - 8
print(f'APK Signing Block: present ({size} bytes)')

SCHEMES = {0x7109871a: 'v2', 0xf05368c0: 'v3', 0x1b93ad61: 'v3.1'}
pos, end = start + 8, cd_off - 24
blobs = []
while pos < end - 4:
    ln = struct.unpack_from('<Q', data, pos)[0]
    pos += 8
    if ln < 4 or pos + ln > end:
        break
    pid = struct.unpack_from('<I', data, pos)[0]
    name = SCHEMES.get(pid)
    print(f'  scheme {name or hex(pid)}: {ln} bytes')
    if name:
        blobs.append(data[pos + 4:pos + ln])
    pos += ln

# The signed-data structure begins with length-prefixed sequences; rather than
# model v2 and v3 exactly, scan for DER SEQUENCE headers and let openssl decide
# whether the bytes are a certificate. Robust across scheme versions.
seen = set()
for blob in blobs:
    for m in re.finditer(rb'\x30\x82', blob):
        off = m.start()
        if off + 4 > len(blob):
            continue
        clen = struct.unpack_from('>H', blob, off + 2)[0] + 4
        if off + clen > len(blob) or clen < 300:
            continue
        der = blob[off:off + clen]
        if der in seen:
            continue
        seen.add(der)
        with tempfile.NamedTemporaryFile(delete=False, suffix='.der') as f:
            f.write(der)
            path = f.name
        try:
            r = subprocess.run(['openssl', 'x509', '-inform', 'DER', '-noout', '-subject',
                                '-issuer', '-dates', '-fingerprint', '-sha256', '-in', path],
                               capture_output=True, text=True)
        finally:
            os.unlink(path)
        if r.returncode == 0 and 'subject=' in r.stdout:
            print('\n--- signing certificate ---')
            print(r.stdout.strip())
            print()
            print('Note: CN=Android Debug means the build was not signed by the original'
                  ' publisher -- verify provenance before porting.')
            sys.exit()
print('\nno parseable certificate found inside the signing block')
PY

# --- 02/03/04 manifest-derived ----------------------------------------------
cp "$DECODED/AndroidManifest.xml" "$OUT/02-manifest.txt" 2>/dev/null || true

# grep, not python: the manifest is XML text after decode, and this must work on
# a stripped-down machine. Captured into a variable -- see the pipefail note in
# the playbook: `producer | grep -q` fails the pipeline on SIGPIPE.
USES=$(grep -o 'uses-permission[^>]*android:name="[^"]*"' "$DECODED/AndroidManifest.xml" 2>/dev/null || true)
{
  echo "# Permissions, with the likely iOS counterpart"
  printf "%s\n" "$USES" | sed 's/.*android:name="//; s/"//' | while read -r p; do
    [ -z "$p" ] && continue
    case "$p" in
      *INTERNET*)          ios="none (always allowed)";;
      *ACCESS_NETWORK_STATE*) ios="NWPathMonitor";;
      *ACCESS_FINE_LOCATION*|*ACCESS_COARSE_LOCATION*) ios="CoreLocation whenInUse + NSLocationWhenInUseUsageDescription";;
      *WRITE_EXTERNAL_STORAGE*|*READ_EXTERNAL_STORAGE*|*READ_MEDIA*) ios="none (PhotoKit / no shared storage)";;
      *POST_NOTIFICATIONS*) ios="UNUserNotificationCenter request; no manifest key";;
      *CAMERA*)            ios="AVCaptureDevice + NSCameraUsageDescription";;
      *RECORD_AUDIO*)      ios="AVAudioSession + NSMicrophoneUsageDescription";;
      *VIBRATE*)           ios="UIImpactFeedbackGenerator (no permission)";;
      *BILLING*)           ios="StoreKit 2 (replace entirely)";;
      *WAKE_LOCK*)         ios="none (no equivalent; redesign)";;
      *FOREGROUND_SERVICE*) ios="BGTaskScheduler or drop the background work";;
      *RECEIVE_BOOT_COMPLETED*) ios="none (no boot hook)";;
      *QUERY_ALL_PACKAGES*) ios="none (no cross-app enumeration)";;
      *)                   ios="UNKNOWN - decide at stage 3";;
    esac
    printf "%-46s -> %s\n" "$p" "$ios"
  done
} > "$OUT/03-permissions.txt"

{
  echo "# Components"
  grep -o '<activity[^>]*android:name="[^"]*"' "$DECODED/AndroidManifest.xml" | sed 's/.*name="/activity   /; s/"//' || true
  grep -o '<service[^>]*android:name="[^"]*"'  "$DECODED/AndroidManifest.xml" | sed 's/.*name="/service    /; s/"//' || true
  grep -o '<receiver[^>]*android:name="[^"]*"' "$DECODED/AndroidManifest.xml" | sed 's/.*name="/receiver   /; s/"//' || true
  grep -o '<provider[^>]*android:name="[^"]*"' "$DECODED/AndroidManifest.xml" | sed 's/.*name="/provider   /; s/"//' || true
  echo
  echo "# Launcher"
  grep -o 'android.intent.category.LAUNCHER' "$DECODED/AndroidManifest.xml" >/dev/null && echo "single LAUNCHER activity expected" || echo "no LAUNCHER category found"
  echo
  echo "# Activity count (a port with 1 activity has no navigation graph to port)"
  grep -c '<activity' "$DECODED/AndroidManifest.xml" || true
} > "$OUT/04-components.txt"

# --- 05 user-visible strings -------------------------------------------------
# The APK bundles the strings of every library it links (87 locales of Material,
# telephony and Compose autofill copy). The app's own copy is a small subset, so
# filter the library key prefixes out -- but keep the unfiltered totals visible,
# because a "small" list is only trustworthy if you can see what was dropped.
LIBPREFIXES='^(mtrl_|abc_|androidx_|com_google_android_|notification_|call_notification|common_google_|material_|maplibre_|preference_|status_bar_notification_|sidecar_|fallback_menu_|expand_button|character_counter|m3c_|mc_|lib_|nav_|fab_transformation|bottomsheet_|design_|summary_collapsed)'
{
  echo "# strings.xml -- app copy first, library copy excluded"
  echo "# excluded key prefixes: ${LIBPREFIXES}"
  echo
  for f in $(find "$DECODED/res" -name "strings.xml" 2>/dev/null | sort); do
    total=$(grep -c "<string " "$f" 2>/dev/null || true)
    kept=$(sed -n 's/.*<string name="\([^"]*\)">\(.*\)<\/string>/\1/p' "$f" | grep -Evc "$LIBPREFIXES" || true)
    [ "${total:-0}" -eq 0 ] && continue
    echo "## ${f#"$DECODED"/}   ($kept of $total keys look app-owned)"
    sed -n 's/.*<string name="\([^"]*\)">\(.*\)<\/string>/\1 = \2/p' "$f" | grep -Ev "$LIBPREFIXES" || true
    echo
  done
} > "$OUT/05-strings.txt"

# --- 06 resource table -------------------------------------------------------
{
  echo "# colours"
  find "$DECODED/res" -name "colors.xml" 2>/dev/null | while read -r f; do
    sed -n 's/.*<color name="\([^"]*\)">\(.*\)<\/color>/\1 = \2/p' "$f"
  done
  echo
  echo "# dimens"
  find "$DECODED/res" -name "dimens.xml" 2>/dev/null | while read -r f; do
    sed -n 's/.*<dimen name="\([^"]*\)">\(.*\)<\/dimen>/\1 = \2/p' "$f"
  done
  echo
  echo "# vector drawables (icon candidates + their pathData)"
  # a quoted glob is a literal path: use -path instead
  find "$DECODED/res" -path "*drawable*" -name "*.xml" 2>/dev/null | while read -r f; do
    grep -q "<vector" "$f" && echo "vector: ${f#"$DECODED"/} $(grep -c 'pathData' "$f") path(s)"
  done
} > "$OUT/06-resources.txt"

# --- 07/08 class inventory + structural markers (jadx) -----------------------
DEC="$OUT/09-decompiled"
if [ ! -d "$DEC" ]; then
  echo "==> decompiling (this is the slow step)"
  jadx -d "$DEC" --no-res --deobf -j 4 "$APK" >/dev/null 2>&1 || echo "jadx failed or partially failed" >&2
fi

find "$DEC" -name "*.java" > "$OUT/07-package.json.tmp"
CLASSES=$(wc -l < "$OUT/07-package.json.tmp" | tr -d ' ')

# The app's own package, from the manifest. Everything outside it is a bundled
# library: counting it inflates "size" by two orders of magnitude and, worse,
# makes framework heuristics fire on code the author never wrote (the first
# version of this script reported "Fragments found" because a library uses them).
APP_PKG=$(sed -n 's/.*package="\([^"]*\)".*/\1/p' "$DECODED/AndroidManifest.xml" | head -1)
APP_DIR="$DEC/sources/$(printf "%s" "$APP_PKG" | tr '.' '/')"
[ -d "$APP_DIR" ] || APP_DIR="$DEC"
APP_FILES=$(find "$APP_DIR" -name "*.java" 2>/dev/null | wc -l | tr -d ' ' || true)
APP_LOC=$(find "$APP_DIR" -name "*.java" -exec cat {} + 2>/dev/null | wc -l | tr -d ' ' || true)
LIB_FILES=$((CLASSES - APP_FILES))

{
  echo "{"
  echo "  \"app_package\": \"$APP_PKG\","
  echo "  \"app_java_files\": $APP_FILES,"
  echo "  \"app_loc\": $APP_LOC,"
  echo "  \"library_java_files\": $LIB_FILES,"
  echo "  \"total_java_files\": $CLASSES,"
  echo "  \"top_library_packages\": ["
  sed "s|$DEC/||; s|/[^/]*$||" "$OUT/07-package.json.tmp" | grep -v "^sources/$(printf "%s" "$APP_PKG" | tr '.' '/')" \
    | sort | uniq -c | sort -rn | head -12 \
    | sed 's/ *\([0-9]*\) \(.*\)/    {"package": "\2", "files": \1},/' | sed '$ s/,$//'
  echo "  ]"
  echo "}"
} > "$OUT/07-package.json"
rm -f "$OUT/07-package.json.tmp"

# The marker counts that decided the architecture last time. Scoped to the app's
# own classes -- a library using HorizontalPager says nothing about this app.
{
  echo "# framework"
  if grep -rqs "androidx.compose" "$APP_DIR"; then echo "Compose (androidx.compose.*) - declarative"; else echo "no androidx.compose in app classes - likely Views/XML layouts"; fi
  if grep -rqs "androidx.fragment" "$APP_DIR"; then echo "Fragments used by app classes: there IS a navigation graph to port"; else echo "No app-owned fragments (library hits ignored)"; fi
  if grep -rqs "dagger\.\|hilt" "$APP_DIR"; then echo "DI in app classes: replace with explicit injection or @Observable"; else echo "No DI framework in app classes"; fi
  echo
  echo "# structural markers in app classes (files containing each)"
  for m in LazyColumn LazyRow LazyVerticalGrid verticalScroll horizontalScroll HorizontalPager \
           NavHost hiltViewModel RoomDatabase SharedPreferences DataStore WorkManager Canvas \
           WebView AndroidView MapView Glide Coil ExoPlayer OkHttp AtomicFile; do
    # `|| true` is load-bearing: grep exits 1 with no matches, and pipefail turns
    # that into a failed substitution, which set -e treats as fatal.
    n=$(grep -rl "$m" "$APP_DIR" 2>/dev/null | wc -l | tr -d ' ' || true)
    [ "$n" -gt 0 ] && printf "%-22s %s\n" "$m" "$n"
  done
  echo
  echo "# entry points (app classes with onCreate)"
  # decompiled Java says `void onCreate`, not Kotlin's `fun onCreate` -- the first
  # version of this script matched the Kotlin spelling and reported nothing.
  grep -rl "onCreate" "$APP_DIR" 2>/dev/null | head -6 | sed "s|$DEC/||" || true
  echo
  echo "# obfuscation signal (app classes with 1-2 char names)"
  echo "short-named app files: $(find "$APP_DIR" \( -name "?.java" -o -name "??.java" \) 2>/dev/null | wc -l | tr -d ' ' || true) of $APP_FILES"
  echo
  echo "# size"
  echo "app:     $APP_FILES java files, $APP_LOC lines"
  echo "bundled: $LIB_FILES classes of libraries (not ported, just dependencies)"
} > "$OUT/08-markers.txt"

# --- RECON.md ---------------------------------------------------------------
SHA=$(awk '/sha256/{print $2}' "$OUT/00-checksum.txt")
{
  echo "# Recon summary"
  echo
  echo "Artifact: \`$(basename "$APK")\`  "
  echo "SHA-256: \`$SHA\`  "
  echo "Recon: $(date -u +%Y-%m-%d)"
  echo
  echo "## Scale"
  echo
  echo "- App package: \`$APP_PKG\`"
  echo "- App classes: **$APP_FILES** java files, **$APP_LOC** lines of decompiled Java (the porting surface)"
  echo "- Note: decompiled Java overstates the Kotlin source (imports, lambda expansion, braces)."
  echo "  Compare *file counts* against the port, not line counts."
  echo "- Bundled library classes: $LIB_FILES (dependencies, not ported)"
  echo
  echo "## Framework shape"
  echo
  sed -n '/# framework/,/# structural/p' "$OUT/08-markers.txt" | grep -v '^#' | grep -v '^$' | sed 's/^/- /'
  echo
  echo "## Structural markers"
  echo
  echo '```'
  sed -n '/# structural markers/,/# entry points/p' "$OUT/08-markers.txt" | grep -v '^#' | grep -v '^$'
  echo '```'
  echo
  echo "## What to read first"
  echo
  echo "1. \`03-permissions.txt\` - permissions with no iOS equivalent are scope changes, not ports."
  echo "2. \`08-markers.txt\` - scroll containers per screen, and whether the app is Compose or Views."
  echo "3. \`05-strings.txt\` - the copy is parity; copy it, do not paraphrase."
  echo "4. \`09-decompiled\` - then one entry point, top-down."
  echo
  echo "## Gates before stage 3"
  echo
  echo "- [ ] Checksum recorded (above)"
  echo "- [ ] Permission deltas listed as decisions, not surprises"
  echo "- [ ] Screen graph written down from component + marker evidence"
  echo "- [ ] Compose vs Views decided (changes stage 6 entirely)"
  echo "- [ ] Obfuscated or not (short-named file count above)"
} > "$OUT/RECON.md"

echo "==> wrote $(find "$OUT" -maxdepth 1 -type f | wc -l | tr -d ' ') files + decompiled tree"
wc -l "$OUT"/0*.txt | sed 's|'"$OUT"'/||'
echo "==> read $OUT/RECON.md first"