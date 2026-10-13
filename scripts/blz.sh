#!/usr/bin/env bash
# Helper to compile a Blaise source against this project's units + the
# stdlib/runtime source trees. Clears the unit cache each time (units change
# often during development and a stale cache produces phantom link errors).
#
# Usage: scripts/blz.sh [--target <os>-<cpu>] <source.pas> <output-binary> [extra blaise flags...]
#
# --target cross-compiles; the default is the host (linux-x86_64). The Blaise
# assembler and linker are internal, so a cross build needs no foreign sysroot
# or toolchain. freebsd-x86_64 requires the compiler to be >= v0.14.0, which
# is where dynamic linking against FreeBSD libc landed -- luhmann binds C
# libraries, so it cannot use the freestanding static path.
#
# Environment:
#   BLAISE_REPO     compiler checkout (default /data/devel/new-pascal-compiler)
#   BLAISE_VERSION  release under $BLAISE_REPO/releases (default v0.14.0)
#   BLAISE          full path to a compiler binary; overrides the two above
#   BLZ_CACHE       unit cache directory (default /tmp/luhmann-blzcache-<target>)
set -euo pipefail

TARGET=""
case "${1:-}" in
  --target)   TARGET="${2:?--target needs a value, e.g. freebsd-x86_64}"; shift 2 ;;
  --target=*) TARGET="${1#--target=}"; shift ;;
esac

R="${BLAISE_REPO:-/data/devel/new-pascal-compiler}"
BLAISE="${BLAISE:-$R/releases/${BLAISE_VERSION:-v0.14.0}/blaise}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${BLZ_CACHE:-/tmp/luhmann-blzcache-${TARGET:-host}}"

if [ ! -x "$BLAISE" ]; then
  echo "blz.sh: no compiler at $BLAISE" >&2
  echo "  set BLAISE_VERSION to one of:" >&2
  ls "$R/releases" 2>/dev/null | grep '^v' | sed 's/^/    /' >&2
  exit 1
fi

if [ $# -lt 2 ]; then
  echo "usage: scripts/blz.sh [--target <os>-<cpu>] <source.pas> <output> [flags...]" >&2
  exit 2
fi

SRC="$1"; OUT="$2"; shift 2

rm -rf "$CACHE"; mkdir -p "$CACHE"

# luhmann binds C libraries (sockets, process spawn), so it must link against
# libc. The compiler decides static vs dynamic automatically from the set of
# unresolved C symbols, and on FreeBSD that decision currently comes out
# "static" -- which links without error but produces a libc-free binary whose
# socket calls cannot work. On Linux the same --static build is correctly
# refused. Ask for dynamic explicitly rather than relying on the auto decision.
DYNAMIC=""
case "$TARGET" in
  freebsd-*) DYNAMIC="--dynamic" ;;
esac

exec "$BLAISE" --source "$SRC" --output "$OUT" \
  ${TARGET:+--target "$TARGET"} \
  ${DYNAMIC:+$DYNAMIC} \
  --unit-path "$HERE/src/main/pascal" \
  --unit-path "$R/runtime/src/main/pascal" \
  --unit-path "$R/stdlib/src/main/pascal" \
  --unit-cache "$CACHE" "$@"
