#!/usr/bin/env zsh
#
# run_perf_test.zsh - Performance test for the sorter on a large file
#
# Runs the sorter on a significative input (tests/data/random-words.txt,
# 2643 real words) in an isolated sandbox, in both directions (asc and
# desc), and for each run:
#   1. checks the exit code (must be 0),
#   2. checks the generated output file name,
#   3. compares the generated output byte-for-byte with an expected
#      file produced independently by combining zsh text tools,
#   4. checks that no WARN log was emitted.
#
# The input can be overridden for stress runs:
#       PERF_INPUT=/path/to/bigger/file zsh tests/run_perf_test.zsh
#
# Usage:  ./run_perf_test.zsh
# Exits 0 when every check passes, 1 otherwise.

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"
BINARY="${ROOT}/sorter"
SANDBOX="${SCRIPT_DIR}/_perf_sandbox"
MAX_LENGTH=256   # must match MAX_LENGTH in main.c

# Deterministic text processing regardless of the user's locale.
export LC_ALL=C

# L-04 fix: canonicalize the input path BEFORE cd.
PERF_INPUT="${PERF_INPUT:-${SCRIPT_DIR}/data/random-words.txt}"
PERF_INPUT="${PERF_INPUT:A}"

pass=0; fail=0
runs_pass=0; runs_fail=0
ok()  { pass=$((pass + 1)); print "      ✓ $1"; }
bad() { fail=$((fail + 1));  print "      ✗ $1"; }

# ---- preconditions ---------------------------------------------------
if [[ ! -x $BINARY ]]; then
  print "Building sorter ..."
  ( cd "$ROOT" && make build ) || {
    print -u2 "Build failed."; exit 1 }
fi
if [[ ! -f $PERF_INPUT ]]; then
  print -u2 "Performance input not found: $PERF_INPUT"
  exit 1
fi
# ---- sandbox -----------------------------------------------------------
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"
# L-04 fix: copy to a collision-proof name in the sandbox.
cp "$PERF_INPUT" "$SANDBOX/perf_input.txt"
cd "$SANDBOX"
input="perf_input.txt"

# Derive the output file name the same way the sorter does
# (build_output_path in io.c): insert "_ordered_<dir>" right before
# the last extension in the basename; a missing dot (or a leading dot)
# means the suffix is appended to the whole name.
derive_out() {  # $1 = asc|desc  ->  prints the expected output name
  local base="$input"
  if [[ $base == *.* && $base != .* ]]; then
    print -r -- "${base%.*}_ordered_$1.${base##*.}"
  else
    print -r -- "${base}_ordered_$1"
  fi
}

n_lines=$(wc -l < "$PERF_INPUT" | tr -d ' ')
n_bytes=$(wc -c < "$PERF_INPUT" | tr -d ' ')

print "== perf: large-file performance test =="
print "   input: $input ($n_lines lines, $n_bytes bytes)"

# Build expected output for a given direction.
make_expected() {  # $1 = asc|desc
  local dir=$1 flag=()
  [[ $dir == desc ]] && flag+=(-r)
  awk -v max="$MAX_LENGTH" \
      '{ sub(/\r$/, ""); if (length($0) > 0 && length($0) <= max) print }' \
    "$input" | LC_ALL=C sort $flag > "expected_${dir}.txt"
}
make_expected asc
make_expected desc

# ---- one run --------------------------------------------------------------
run_one() {  # $1 = order (asc|desc)
  local order=$1

  # M-08 fix: force LOG_LEVEL=INFO for consistent behavior.
  LOG_LEVEL=INFO "$BINARY" --order "$order" "$input" \
    > /dev/null 2> "${order}.log"
  RUN_RC=$?

  RUN_ELAPSED=$(awk -F'Elapsed time: ' '/Elapsed time:/ {
      split($2, a, " "); print a[1] }' "${order}.log")

  if [[ -z $RUN_ELAPSED ]] || [[ $RUN_ELAPSED == *[!0-9.]* ]]; then
    bad "could not read elapsed time from the log"
    RUN_ELAPSED=0
  fi

  RUN_MS=$(awk -v e="$RUN_ELAPSED" 'BEGIN { printf "%d", e * 1000 + 0.5 }')
  RUN_LOG="${order}.log"
}

# Check everything for one completed run.
check_one() {  # $1 = order  $2 = expected file  $3 = output file name
  local order=$1 exp=$2 outfile=$3
  RUN_BAD=0

  # 1. exit code
  if (( RUN_RC == 0 )); then
    ok "$order: exit code is 0"
  else
    bad "$order: expected exit code 0, got $RUN_RC"; RUN_BAD=1
  fi

  # 2. generated output file name
  if [[ -f "$outfile" ]]; then
    ok "$order: output file named \"$outfile\""
  else
    bad "$order: expected output file \"$outfile\" was not created"; RUN_BAD=1
  fi

  # 3. content comparison
  if [[ -f "$outfile" ]]; then
    if diff -q "$exp" "$outfile" > /dev/null 2>&1; then
      ok "$order: content matches expected ($n_lines lines)"
    else
      bad "$order: content mismatch for $outfile:"; RUN_BAD=1
      diff "$exp" "$outfile" | head -10 | sed 's/^/          /'
    fi
  fi

  # 4. no WARN log expected on this clean input
  if grep -q "\[WARN " "$RUN_LOG" 2> /dev/null; then
    bad "$order: unexpected WARN log:"; RUN_BAD=1
    grep "\[WARN " "$RUN_LOG" | head -5 | sed 's/^/          /'
  else
    ok "$order: no WARN log"
  fi
}

# ---- ascending run -------------------------------------------------------
ASC_OUT=$(derive_out asc)
print ""
print -r -- "-- asc run --"
run_one asc
ASC_RC=$RUN_RC; ASC_ELAPSED=$RUN_ELAPSED; ASC_MS=$RUN_MS
ASC_LOG=$RUN_LOG
check_one asc "expected_asc.txt" "$ASC_OUT"
if (( RUN_BAD )); then runs_fail=$((runs_fail + 1)); else runs_pass=$((runs_pass + 1)); fi

# ---- descending run ------------------------------------------------------
DESC_OUT=$(derive_out desc)
print ""
print -r -- "-- desc run --"
run_one desc
DESC_RC=$RUN_RC; DESC_ELAPSED=$RUN_ELAPSED; DESC_MS=$RUN_MS
DESC_LOG=$RUN_LOG
check_one desc "expected_desc.txt" "$DESC_OUT"
if (( RUN_BAD )); then runs_fail=$((runs_fail + 1)); else runs_pass=$((runs_pass + 1)); fi

# ---- recap ---------------------------------------------------------------
print ""
print "==================================================="
print " Performance test recap"
print "---------------------------------------------------"
print "   input   : ${PERF_INPUT:t}"
print "            $n_lines lines, $n_bytes bytes"
print "   asc     : exit=$ASC_RC  elapsed=${ASC_ELAPSED}s (${ASC_MS} ms)"
print "   desc    : exit=$DESC_RC  elapsed=${DESC_ELAPSED}s (${DESC_MS} ms)"
print "---------------------------------------------------"
if (( fail > 0 )); then
  print " Results: $runs_pass/$((runs_pass + runs_fail)) runs passed, $pass/$((pass + fail)) checks passed"
  print "           $runs_fail run(s), $fail check(s) failed"
else
  print " Results: $runs_pass runs and $pass checks passed, 0 runs and 0 checks failed"
fi
print "==================================================="

# ---- cleanup -------------------------------------------------------------
cd "$ROOT"
if (( fail > 0 )); then
  print "Sandbox kept for inspection: $SANDBOX"
  exit 1
fi
rm -rf "$SANDBOX"
exit 0
