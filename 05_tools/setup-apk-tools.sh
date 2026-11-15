#!/usr/bin/env bash
# Installs the APK-analysis toolchain without sudo and without Homebrew formulas.
#
#   ./setup-apk-tools.sh [target-dir]      # default: ~/.local/apk-tools
#
# Why not `brew install jadx apktool` on this machine: on x86_64 macOS 15 the
# openjdk formula has no bottle, so brew compiles OpenJDK 27 *and* ~48
# dependencies (cmake, glib, cairo, harfbuzz, icu, ...) from source. That is
# 30-60 minutes and fails against older Command Line Tools. Prebuilt Temurin +
# the jadx release zip + the apktool jar is ~2 minutes and deletes cleanly.
#
# Installs: Temurin JDK 21 (LTS), jadx 1.5.6, apktool 2.11.1, plus wrappers in
# <target>/bin so `jadx`/`apktool` work without touching PATH globally.

set -euo pipefail

DEST="${1:-$HOME/.local/apk-tools}"
JDK_VER=21
JADX_VER=1.5.6
APKTOOL_VER=2.11.1
ARCH="$(uname -m)"                       # x86_64 | arm64
case "$ARCH" in
  arm64)  JDK_ARCH=aarch64;;
  x86_64) JDK_ARCH=x64;;
  *) echo "unsupported arch: $ARCH" >&2; exit 2;;
esac

mkdir -p "$DEST/bin"
cd "$DEST"

echo "==> Temurin JDK $JDK_VER ($JDK_ARCH)"
curl -fsSL -o jdk.tar.gz \
  "https://api.adoptium.net/v3/binary/latest/$JDK_VER/ga/mac/$JDK_ARCH/jdk/hotspot/normal/eclipse?project=jdk"
tar xzf jdk.tar.gz && rm jdk.tar.gz
JH="$(ls -d "$DEST"/jdk-*/Contents/Home | head -1)"
[ -x "$JH/bin/java" ] || { echo "JDK extraction failed" >&2; exit 3; }

echo "==> jadx $JADX_VER"
curl -fsSL -o jadx.zip "https://github.com/skylot/jadx/releases/download/v$JADX_VER/jadx-$JADX_VER.zip"
mkdir -p jadx && unzip -q -o jadx.zip -d jadx && rm jadx.zip

echo "==> apktool $APKTOOL_VER"
curl -fsSL -o apktool.jar \
  "https://github.com/iBotPeaches/Apktool/releases/download/v$APKTOOL_VER/apktool_$APKTOOL_VER.jar"

cat > bin/__env <<EOF
export JAVA_HOME="$JH"
export PATH="\$JAVA_HOME/bin:$DEST/jadx/bin:\$PATH"
EOF
printf '#!/bin/bash\nsource "%s/bin/__env"\nexec "%s/jadx/bin/jadx" "$@"\n' "$DEST" "$DEST" > bin/jadx
printf '#!/bin/bash\nsource "%s/bin/__env"\nexec java -jar "%s/apktool.jar" "$@"\n' "$DEST" "$DEST" > bin/apktool
printf '#!/bin/bash\nsource "%s/bin/__env"\nexec java "$@"\n' "$DEST" > bin/java
chmod +x bin/jadx bin/apktool bin/java

# Verify, rather than assume.
source bin/__env
printf "java:    %s\njadx:    %s\napktool: %s\n" \
  "$(java -version 2>&1 | head -1)" "$(jadx --version 2>&1 | head -1)" "$(apktool --version 2>&1 | head -1)"
echo
echo "OK. apk-recon.sh finds this automatically at $DEST."
echo "Optional, for your shell:  export PATH=\"$DEST/bin:\$PATH\""