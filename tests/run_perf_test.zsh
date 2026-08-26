#!/usr/bin/env zsh
#
# run_perf_test.zsh - Performance test for the sorter on a large file
#
# Runs the sorter on a significative input (tests/data/random-words.txt,
# 2643 real words) in both directions (asc and desc), and for each run:
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

# ---- color support (disabled if not a terminal) ----------------------
if [[ -t 1 ]]; then
  c_green=$'\033[32m'; c_red=$'\033[31m'; c_dim=$'\033[2m'; c_reset=$'\033[0m'
else
  c_green=; c_red=; c_dim=; c_reset=
fi

# L-04 fix: canonicalize the input path BEFORE cd.
PERF_INPUT="${PERF_INPUT:-${SCRIPT_DIR}/data/random-words.txt}"
PERF_INPUT="${PERF_INPUT:A}"

pass=0; fail=0
typeset -a failure_details=()

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

derive_out() {
  local base="$input"
  if [[ $base == *.* && $base != .* ]]; then
    print -r -- "${base%.*}_ordered_$1.${base##*.}"
  else
    print -r -- "${base}_ordered_$1"
  fi
}

n_lines=$(wc -l < "$PERF_INPUT" | tr -d ' ')
n_bytes=$(wc -c < "$PERF_INPUT" | tr -d ' ')

print "  ${c_dim}${PERF_INPUT:t}: $n_lines lines, $n_bytes bytes${c_reset}"

# Build expected output for a given direction.
make_expected() {
  local dir=$1 flag=()
  [[ $dir == desc ]] && flag+=(-r)
  awk -v max="$MAX_LENGTH" \
      '{ sub(/\r$/, ""); if (length($0) > 0 && length($0) <= max) print }' \
    "$input" | LC_ALL=C sort $flag > "expected_${dir}.txt"
}
make_expected asc
make_expected desc

# ---- one run --------------------------------------------------------------
run_one() {
  local order=$1
  LOG_LEVEL=INFO "$BINARY" --order "$order" "$input" \
    > /dev/null 2> "${order}.log"
  RUN_RC=$?

  RUN_ELAPSED=$(awk -F'Elapsed time: ' '/Elapsed time:/ {
      split($2, a, " "); print a[1] }' "${order}.log")

  if [[ -z $RUN_ELAPSED ]] || [[ $RUN_ELAPSED == *[!0-9.]* ]]; then
    RUN_ELAPSED=0
  fi

  RUN_MS=$(awk -v e="$RUN_ELAPSED" 'BEGIN { printf "%d", e * 1000 + 0.5 }')
  RUN_LOG="${order}.log"
}

# Check everything for one completed run. Prints one PASS/FAIL line.
check_one() {
  local order=$1 exp=$2 outfile=$3
  local case_fail=0
  local case_errors=()

  # 1. exit code
  if (( RUN_RC == 0 )); then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); case_fail=1
    case_errors+=("expected exit 0, got $RUN_RC")
  fi

  # 2. generated output file name
  if [[ -f "$outfile" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1)); case_fail=1
    case_errors+=("expected output file \"$outfile\" was not created")
  fi

  # 3. content comparison
  if [[ -f "$outfile" ]]; then
    if diff -q "$exp" "$outfile" > /dev/null 2>&1; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1)); case_fail=1
      case_errors+=("content mismatch for $outfile")
    fi
  fi

  # 4. no WARN log expected on clean input
  if grep -q "\[WARN " "$RUN_LOG" 2> /dev/null; then
    fail=$((fail + 1)); case_fail=1
    case_errors+=("unexpected WARN log")
  else
    pass=$((pass + 1))
  fi

  if (( case_fail == 0 )); then
    print "  ${c_green}PASS${c_reset}  ${order} ${c_dim}(${RUN_MS} ms)${c_reset}"
  else
    print "  ${c_red}FAIL${c_reset}  ${order} ${c_dim}(${RUN_MS} ms)${c_reset}"
    failure_details+=("${order}:")
    for err in "${case_errors[@]}"; do
      failure_details+=("        $err")
    done
  fi
}

# ---- ascending run -------------------------------------------------------
ASC_OUT=$(derive_out asc)
run_one asc
check_one asc "expected_asc.txt" "$ASC_OUT"

# ---- descending run ------------------------------------------------------
DESC_OUT=$(derive_out desc)
run_one desc
check_one desc "expected_desc.txt" "$DESC_OUT"

# ---- print failure details if any ----------------------------------------
if (( ${#failure_details[@]} > 0 )); then
  print ""
  print "  ${c_red}Failures:${c_reset}"
  for line in "${failure_details[@]}"; do
    print "    $line"
  done
fi

# ---- summary -------------------------------------------------------------
print ""
total=$((pass + fail))
if (( fail == 0 )); then
  print "  ${c_green}$pass passed${c_reset}${c_dim}, $total assertions (2 runs)${c_reset}"
else
  print "  ${c_green}$pass passed${c_reset}, ${c_red}$fail failed${c_reset}${c_dim}, $total assertions (2 runs)${c_reset}"
fi

# ---- cleanup -------------------------------------------------------------
cd "$ROOT"
if (( fail > 0 )); then
  print "  Sandbox kept for inspection: $SANDBOX"
  exit 1
fi
rm -rf "$SANDBOX"
exit 0
