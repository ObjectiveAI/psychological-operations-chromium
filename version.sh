#!/usr/bin/env bash
# version.sh — set OUR release version. Lives in a single-line VERSION
# file at the repo root; that's what .github/workflows/release.yml reads
# to decide what GitHub release to cut.
#
# Upstream ungoogled-chromium tracking is *not* touched here — those
# tags live as constants near the top of build.sh and are bumped by
# hand when refreshing upstream.
#
# Usage:
#   bash version.sh <new-version>
# Example:
#   bash version.sh 0.2.0

set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  echo "Usage: $0 <new-version>" >&2
  echo "Example: $0 0.2.0" >&2
  exit 1
fi

NEW_VERSION="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting version to $NEW_VERSION"
printf '%s\n' "$NEW_VERSION" > "$REPO_ROOT/VERSION"
echo "  wrote VERSION"
