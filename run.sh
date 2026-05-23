#!/usr/bin/env bash
# run.sh — launch the locally-built psyops Chromium with the required
# flags so our launch-args patch is satisfied. No performance tuning,
# no extension preloading — just the minimum to get the browser running
# for local dev / debugging.
#
# Usage:
#   bash run.sh --psyop <name> [--config-base-dir <path>] [-- <chrome-args>...]
#   bash run.sh --x-app        [--config-base-dir <path>] [-- <chrome-args>...]
#
# Anything after `--` is passed through to chrome unchanged.
# Default --config-base-dir is $REPO_ROOT/.run (sibling to .build/,
# gitignored). When .build/<target>/extracted/ doesn't exist yet, this
# script invokes build.sh once to populate it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

PSYOP=""
X_APP=0
CONFIG_BASE_DIR="$REPO_ROOT/.run"
EXTRAS=()

# ── Args ───────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --psyop)
      [ $# -ge 2 ] || { echo "ERROR: --psyop needs a name" >&2; exit 1; }
      PSYOP="$2"; shift 2 ;;
    --psyop=*)
      PSYOP="${1#--psyop=}"; shift ;;
    --x-app)
      X_APP=1; shift ;;
    --config-base-dir)
      [ $# -ge 2 ] || { echo "ERROR: --config-base-dir needs a path" >&2; exit 1; }
      CONFIG_BASE_DIR="$2"; shift 2 ;;
    --config-base-dir=*)
      CONFIG_BASE_DIR="${1#--config-base-dir=}"; shift ;;
    --)
      shift
      EXTRAS=("$@")
      break ;;
    -h|--help)
      sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 1 ;;
  esac
done

if [ "$X_APP" = 0 ] && [ -z "$PSYOP" ]; then
  echo "ERROR: must pass --psyop <name> or --x-app" >&2
  exit 1
fi

# ── Host detection ─────────────────────────────────────────────────────
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

# ── Ensure extracted Chromium tree exists ──────────────────────────────
EXTRACTED_DIR="$REPO_ROOT/.build/$TARGET/extracted"
if [ ! -d "$EXTRACTED_DIR" ] || [ -z "$(ls -A "$EXTRACTED_DIR" 2>/dev/null)" ]; then
  echo "==> No extracted Chromium at $EXTRACTED_DIR — running build.sh"
  bash "$REPO_ROOT/build.sh" --target "$TARGET"
fi

# ── Locate chrome binary ───────────────────────────────────────────────
case "$host_os" in
  windows)
    CHROME=$(find "$EXTRACTED_DIR" -maxdepth 2 -name 'chrome.exe' -type f 2>/dev/null | head -1) ;;
  macos)
    CHROME=$(find "$EXTRACTED_DIR" -maxdepth 4 -path '*.app/Contents/MacOS/*' -type f 2>/dev/null | head -1) ;;
  linux)
    CHROME=$(find "$EXTRACTED_DIR" -maxdepth 2 -name 'chrome' -type f -perm -u+x 2>/dev/null | head -1) ;;
esac

if [ -z "$CHROME" ] || [ ! -f "$CHROME" ]; then
  echo "ERROR: could not locate chrome binary under $EXTRACTED_DIR" >&2
  echo "       contents:" >&2
  ls "$EXTRACTED_DIR" >&2
  exit 1
fi

# ── Compose args ───────────────────────────────────────────────────────
mkdir -p "$CONFIG_BASE_DIR"

# Chromium on Windows parses paths via the Win32 API; the Git Bash
# /c/Users/... form would fail there. cygpath converts to native.
if [ "$host_os" = "windows" ] && command -v cygpath >/dev/null 2>&1; then
  CONFIG_BASE_DIR=$(cygpath -w "$CONFIG_BASE_DIR")
fi

ARGS=(
  "--config-base-dir=$CONFIG_BASE_DIR"
  # Suppress chromium's first-run UI (welcome page, default-browser prompt)
  # so positional URLs reliably open instead of getting hijacked by
  # ungoogled-chromium's first-run-page.patch on a fresh profile.
  "--no-first-run"
  "--no-default-browser-check"
)
if [ "$X_APP" = 1 ]; then
  ARGS+=( "--x-app" )
fi
if [ -n "$PSYOP" ]; then
  ARGS+=( "--psyop=$PSYOP" )
fi
ARGS+=( ${EXTRAS[@]+"${EXTRAS[@]}"} )

# Default x-app sessions to open the X developer console when the user
# didn't pass their own positional URL(s) in EXTRAS. Works on any
# chromium binary — patched or not — since chromium treats trailing
# positional args as URLs to open in the first window.
if [ "$X_APP" = 1 ] && [ ${#EXTRAS[@]} -eq 0 ]; then
  ARGS+=( "https://console.x.ai" )
fi

echo "==> $CHROME"
printf '    %s\n' "${ARGS[@]}"
exec "$CHROME" "${ARGS[@]}"
