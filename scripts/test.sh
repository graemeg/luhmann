#!/usr/bin/env bash
# Compile and run every unit-test program under src/test/pascal.
# Each test program prints "PASS=<n> FAIL=<n>" and exits non-zero on failure.
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SUITES=0; FAILED=0

for src in "$HERE"/src/test/pascal/test_*.pas; do
  name="$(basename "$src" .pas)"
  # test_adapters and test_http need a live network / corpus; skip in CI mode.
  case "$name" in
    test_adapters|test_http) continue ;;
  esac
  SUITES=$((SUITES+1))
  if ! "$HERE/scripts/blz.sh" "$src" "/tmp/$name" >"/tmp/$name.log" 2>&1; then
    echo "FAIL (compile) $name: $(grep -iE error "/tmp/$name.log" | head -1)"
    FAILED=$((FAILED+1)); continue
  fi
  if "/tmp/$name" >"/tmp/$name.out" 2>&1; then
    echo "ok   $name: $(grep -oE 'PASS=[0-9]+ FAIL=[0-9]+' "/tmp/$name.out" | tail -1)"
  else
    echo "FAIL (runtime) $name"
    tail -3 "/tmp/$name.out"
    FAILED=$((FAILED+1))
  fi
done

echo "----"
echo "suites: $SUITES, failed: $FAILED"
[ "$FAILED" -eq 0 ]
