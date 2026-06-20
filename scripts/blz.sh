#!/usr/bin/env bash
# Helper to compile a Blaise source against this project's units + the
# stdlib/runtime source trees. Clears the unit cache each time (units change
# often during development and a stale cache produces phantom link errors).
#
# Usage: scripts/blz.sh <source.pas> <output-binary> [extra blaise flags...]
set -euo pipefail

R="${BLAISE_REPO:-/data/devel/new-pascal-compiler}"
BLAISE="$R/releases/v0.12.0-pre/blaise"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${BLZ_CACHE:-/tmp/luhmann-blzcache}"

SRC="$1"; OUT="$2"; shift 2

rm -rf "$CACHE"; mkdir -p "$CACHE"

"$BLAISE" --source "$SRC" --output "$OUT" \
  --unit-path "$HERE/src/main/pascal" \
  --unit-path "$R/runtime/src/main/pascal" \
  --unit-path "$R/stdlib/src/main/pascal" \
  --unit-cache "$CACHE" "$@"
