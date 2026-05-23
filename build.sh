#!/usr/bin/env bash
# build.sh — fetch the upstream ungoogled-chromium release for the host
# platform, repackage to a uniform .zip in .build/<platform>/, and
# (with --release + GH_TOKEN) upload as a GitHub release asset on this
# fork. Matches the publish pattern in
# psychological-operations/.github/workflows/release.yml.
#
# Usage:
#   bash build.sh [--target <platform>] [--release]
#
# <platform> is one of:
#   linux-x86_64  macos-x86_64  macos-aarch64  windows-x86_64
# When omitted, the host platform is auto-detected from `uname`. Other
# hosts are rejected — matches psychological-operations's release matrix.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
TARGET=""
RELEASE=0

# ── Args ───────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -ge 2 ] || { echo "ERROR: --target needs an argument" >&2; exit 1; }
      TARGET="$2"; shift 2 ;;
    --target=*)
      TARGET="${1#--target=}"; shift ;;
    --release)
      RELEASE=1; shift ;;
    -h|--help)
      sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      echo "ERROR: unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ── Upstream tracking ──────────────────────────────────────────────────
# Tags of OUR per-platform packaging forks (each forked from
# ungoogled-software/ungoogled-chromium-{windows,macos,portablelinux}
# with their `ungoogled-chromium` submodule redirected at THIS repo).
# Their CI builds Chromium with our psyops patches applied and publishes
# binaries to releases on the matching fork. Bump when refreshing.
PSYOPS_WIN_TAG="148.0.7778.178-1"
PSYOPS_MAC_TAG="148.0.7778.178-1"
PSYOPS_LINUX_TAG="148.0.7778.178-1"

# ── Host detection ─────────────────────────────────────────────────────
if [ -z "$TARGET" ]; then
  case "$(uname -s)" in
    CYGWIN*|MINGW*|MSYS*) host_os="windows" ;;
    Darwin*)              host_os="macos"   ;;
    Linux*)               host_os="linux"   ;;
    *) echo "ERROR: unsupported host OS: $(uname -s)" >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  host_arch="x86_64"  ;;
    arm64|aarch64) host_arch="aarch64" ;;
    *) echo "ERROR: unsupported host arch: $(uname -m)" >&2; exit 1 ;;
  esac
  TARGET="${host_os}-${host_arch}"
fi

# ── Resolve platform → upstream repo + asset name ──────────────────────
# Asset naming conventions inherited from the upstream packaging repos
# (our forks didn't touch the build scripts, so they produce identical
# names):
#   portablelinux: ungoogled-chromium-<tag>-<arch>_linux.tar.xz   (dash sep)
#   macos:         ungoogled-chromium_<tag>_<arch>-macos.dmg       (underscore sep, dash-arch)
#   windows:       ungoogled-chromium_<tag>_windows_<arch>.zip     (underscore sep, underscore-arch)
case "$TARGET" in
  linux-x86_64)
    UPSTREAM_REPO="ObjectiveAI/psychological-operations-chromium-portablelinux"
    UPSTREAM_TAG="$PSYOPS_LINUX_TAG"
    UPSTREAM_ASSET="ungoogled-chromium-${UPSTREAM_TAG}-x86_64_linux.tar.xz"
    EXTRACT_KIND="tarxz"
    ;;
  macos-x86_64)
    UPSTREAM_REPO="ObjectiveAI/psychological-operations-chromium-macos"
    UPSTREAM_TAG="$PSYOPS_MAC_TAG"
    UPSTREAM_ASSET="ungoogled-chromium_${UPSTREAM_TAG}_x86_64-macos.dmg"
    EXTRACT_KIND="dmg"
    ;;
  macos-aarch64)
    UPSTREAM_REPO="ObjectiveAI/psychological-operations-chromium-macos"
    UPSTREAM_TAG="$PSYOPS_MAC_TAG"
    UPSTREAM_ASSET="ungoogled-chromium_${UPSTREAM_TAG}_arm64-macos.dmg"
    EXTRACT_KIND="dmg"
    ;;
  windows-x86_64)
    UPSTREAM_REPO="ObjectiveAI/psychological-operations-chromium-windows"
    UPSTREAM_TAG="$PSYOPS_WIN_TAG"
    UPSTREAM_ASSET="ungoogled-chromium_${UPSTREAM_TAG}_windows_x64.zip"
    EXTRACT_KIND="zip"
    ;;
  *)
    echo "ERROR: unsupported target: $TARGET" >&2
    echo "       valid: linux-x86_64, macos-x86_64, macos-aarch64, windows-x86_64" >&2
    exit 1
    ;;
esac

# ── Read VERSION ───────────────────────────────────────────────────────
VERSION_FILE="$REPO_ROOT/VERSION"
[ -f "$VERSION_FILE" ] || { echo "ERROR: $VERSION_FILE not found" >&2; exit 1; }
VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
[ -n "$VERSION" ] || { echo "ERROR: VERSION file is empty" >&2; exit 1; }

# ── Paths ──────────────────────────────────────────────────────────────
BUILD_DIR="$REPO_ROOT/.build/$TARGET"
RAW_DIR="$BUILD_DIR/raw"
EXTRACTED_DIR="$BUILD_DIR/extracted"
OUT_NAME="psychological-operations-chromium-${TARGET}.zip"
OUT_PATH="$BUILD_DIR/$OUT_NAME"

mkdir -p "$RAW_DIR"
rm -rf "$EXTRACTED_DIR"
mkdir -p "$EXTRACTED_DIR"

# ── Download upstream ──────────────────────────────────────────────────
echo "==> Downloading $UPSTREAM_REPO @ $UPSTREAM_TAG :: $UPSTREAM_ASSET"
if [ -f "$RAW_DIR/$UPSTREAM_ASSET" ]; then
  echo "    (cached: $RAW_DIR/$UPSTREAM_ASSET)"
else
  gh release download "$UPSTREAM_TAG" \
    --repo "$UPSTREAM_REPO" \
    --pattern "$UPSTREAM_ASSET" \
    --dir "$RAW_DIR"
fi
[ -f "$RAW_DIR/$UPSTREAM_ASSET" ] || {
  echo "ERROR: expected download at $RAW_DIR/$UPSTREAM_ASSET" >&2
  exit 1
}

# ── Extract ────────────────────────────────────────────────────────────
echo "==> Extracting ($EXTRACT_KIND)"
case "$EXTRACT_KIND" in
  tarxz)
    tar -xJf "$RAW_DIR/$UPSTREAM_ASSET" -C "$EXTRACTED_DIR"
    ;;
  zip)
    if command -v unzip >/dev/null 2>&1; then
      unzip -q "$RAW_DIR/$UPSTREAM_ASSET" -d "$EXTRACTED_DIR"
    else
      # Git-Bash on Windows ships python but not always unzip.
      python -m zipfile -e "$RAW_DIR/$UPSTREAM_ASSET" "$EXTRACTED_DIR"
    fi
    ;;
  dmg)
    command -v hdiutil >/dev/null 2>&1 || {
      echo "ERROR: .dmg extraction requires macOS hdiutil (target=$TARGET on non-macOS host)" >&2
      exit 1
    }
    MNT="$BUILD_DIR/mnt"
    mkdir -p "$MNT"
    hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$RAW_DIR/$UPSTREAM_ASSET" >/dev/null
    # ungoogled-chromium-macos ships a single .app at the dmg root.
    cp -R "$MNT"/*.app "$EXTRACTED_DIR/"
    hdiutil detach -quiet "$MNT"
    ;;
  *)
    echo "ERROR: unknown EXTRACT_KIND=$EXTRACT_KIND" >&2
    exit 1
    ;;
esac

# ── Repackage to uniform .zip ──────────────────────────────────────────
echo "==> Packaging $OUT_PATH"
rm -f "$OUT_PATH"
if command -v zip >/dev/null 2>&1; then
  ( cd "$EXTRACTED_DIR" && zip -qr "$OUT_PATH" . )
else
  python - "$EXTRACTED_DIR" "$OUT_PATH" <<'PY'
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, src))
PY
fi
[ -f "$OUT_PATH" ] || { echo "ERROR: package missing: $OUT_PATH" >&2; exit 1; }

# stat -c is GNU, stat -f is BSD; one of them works on every host we target.
OUT_SIZE=$(stat -c '%s' "$OUT_PATH" 2>/dev/null || stat -f '%z' "$OUT_PATH")
echo "    -> $OUT_PATH ($OUT_SIZE bytes)"

# ── Optional release upload ────────────────────────────────────────────
if [ "$RELEASE" = 1 ]; then
  REPO="${GITHUB_REPOSITORY:-ObjectiveAI/psychological-operations-chromium}"
  : "${GH_TOKEN:?ERROR: --release requires GH_TOKEN env var}"
  echo "==> Uploading to release v$VERSION on $REPO"
  gh release upload "v$VERSION" "$OUT_PATH" \
    --clobber \
    --repo "$REPO"
fi

echo "Done."
