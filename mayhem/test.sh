#!/usr/bin/env bash
# Runs the checks mayhem/build.sh built:
#  * stb_png_regress_check: stb_image PNG decoding vs. upstream's tests/pngsuite/ref_results.csv
#    (dimensions, component count, error string, pixel hash for every file)
#  * stb_ds_unit_tests: upstream's tests/test_ds_cpp.cpp (stb_ds unit tests + hash-map churn asserts)
# Every check must print its summary/"Ok!" line; a neutered binary prints nothing and so fails.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
SRC="${SRC:-/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

for b in stb_png_regress_check stb_ds_unit_tests; do
  [ -x "$SRC/$b" ] || { echo "missing $SRC/$b — mayhem/build.sh should have built it" >&2; emit_ctrf stb-selftests 0 1; exit 1; }
done

passed=0; failed=0
expected=$(( $(wc -l < tests/pngsuite/ref_results.csv) - 1 ))

out=$(cd tests && "$SRC/stb_png_regress_check" 2>&1); echo "$out" | tail -n 20
if [[ "$out" =~ PNGREGRESS\ total=([0-9]+)\ passed=([0-9]+)\ failed=([0-9]+) ]] && [ "${BASH_REMATCH[1]}" -eq "$expected" ]; then
  passed=$(( passed + BASH_REMATCH[2] )); failed=$(( failed + BASH_REMATCH[3] ))
else
  echo "png regression check produced no valid summary (expected $expected rows)" >&2
  failed=$(( failed + expected ))
fi

out=$(cd tests && "$SRC/stb_ds_unit_tests" 2>&1); rc=$?; echo "$out" | tail -n 5
if [ $rc -eq 0 ] && [[ "$out" == *"Ok!"* ]]; then passed=$(( passed + 1 )); else echo "stb_ds unit tests failed (rc=$rc)" >&2; failed=$(( failed + 1 )); fi

emit_ctrf stb-selftests "$passed" "$failed"
