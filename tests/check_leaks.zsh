#!/usr/bin/env zsh
#
# check_leaks.zsh - Sanitizer and memory leak checks for the sorter (macOS).
#
# Builds disposable binaries and runs:
#   1. ASan + UBSan against the full correctness and performance suites;
#   2. TSan against the threaded performance suite;
#   3. Apple's `leaks` tool against a signed debug binary.
#
# Child output is captured and summarized on success. Relevant captured output
# is printed on failure. The project binary and fixtures remain untouched.
# Exits 0 only when every check passes and removes all temporary artifacts.
#
set -euo pipefail

# ---- project layout ---------------------------------------------------
SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"
SRC=(main.c logging.c list.c io.c mergesort.c)
FIXTURES="${SCRIPT_DIR}/fixtures"
FIX_INPUT="${FIXTURES}/basic_asc/basic.txt"
PERF_DATA="${SCRIPT_DIR}/data"
PERF_INPUT="${PERF_DATA}/random-words.txt"
RUN_TESTS="${SCRIPT_DIR}/run_tests.zsh"
RUN_PERF="${SCRIPT_DIR}/run_perf_test.zsh"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

# Deterministic test behavior.
export LOG_LEVEL=INFO
export LC_ALL=C

# ---- color support (disabled if not a terminal) ----------------------
if [[ -t 1 ]]; then
  c_green=$'\033[32m'; c_red=$'\033[31m'; c_dim=$'\033[2m'; c_reset=$'\033[0m'
else
  c_green=; c_red=; c_dim=; c_reset=
fi

# ---- report formatting ------------------------------------------------
pass=0; fail=0
typeset -a failure_details=()

step_pass() {
  pass=$((pass + 1))
  print "  ${c_green}PASS${c_reset}  $1"
}

step_fail() {
  fail=$((fail + 1))
  print "  ${c_red}FAIL${c_reset}  $1"
  failure_details+=("$1")
}

abort_precondition() {
  step_fail "precondition: $1"
  print ""
  print "  ${c_red}1 failed${c_reset}${c_dim}, aborted${c_reset}"
  exit 1
}

print_log_excerpt() {
  local log=$1
  if [[ -s $log ]]; then
    failure_details+=("    last 60 lines of $log:")
    while IFS= read -r line; do
      failure_details+=("      $line")
    done < <(tail -n 60 "$log")
  fi
  return 0
}

show_sanitizer_diagnostics() {
  local suite_root=$1
  local log relative
  for log in "$suite_root"/tests/**/*.log(N); do
    if grep -Eq \
      'AddressSanitizer|UndefinedBehaviorSanitizer|ThreadSanitizer|runtime error:|SUMMARY:.*Sanitizer' \
      "$log"; then
      relative="${log#$suite_root/}"
      failure_details+=("    sanitizer diagnostic from $relative (last 80 lines):")
      while IFS= read -r line; do
        failure_details+=("      $line")
      done < <(tail -n 80 "$log")
    fi
  done
  return 0
}

summarize_runner_log() {
  local log=$1
  local summary
  if ! summary="$(awk '
      /passed/ { line = $0 }
      END {
        sub(/^[[:space:]]*/, "", line)
        print line
      }
    ' "$log")"; then
    summary=""
  fi
  print -r -- "${summary:-completed successfully}"
  return 0
}

summarize_leaks_log() {
  local log=$1
  local summary
  if ! summary="$(awk '
      /[0-9]+ leaks for [0-9]+ total leaked bytes/ { line = $0 }
      END {
        sub(/^.*: /, "", line)
        print line
      }
    ' "$log")"; then
    summary=""
  fi
  print -r -- "${summary:-completed without reported leaks}"
  return 0
}

# ---- platform and tool preconditions ----------------------------------
os="$(uname -s)"
if [[ $os != "Darwin" ]]; then
  abort_precondition "macOS required (current system: $os)"
fi
if ! command -v cc > /dev/null; then
  abort_precondition "C compiler not found in PATH"
fi
if ! command -v leaks > /dev/null; then
  abort_precondition "leaks not found; install Xcode command-line tools"
fi
if ! command -v codesign > /dev/null; then
  abort_precondition "codesign not found in PATH"
fi
if [[ ! -x $PLIST_BUDDY ]]; then
  abort_precondition "PlistBuddy not found at $PLIST_BUDDY"
fi
if [[ ! -d $FIXTURES || ! -f $FIX_INPUT ]]; then
  abort_precondition "fixtures missing under $FIXTURES (run 'make fixtures')"
fi
if [[ ! -d $PERF_DATA || ! -f $PERF_INPUT ]]; then
  abort_precondition "performance input missing: $PERF_INPUT"
fi
if [[ ! -f $RUN_TESTS || ! -f $RUN_PERF ]]; then
  abort_precondition "test runner scripts are missing"
fi

# One unique sandbox owns every disposable suite, binary, and captured log.
if ! SANDBOX="$(mktemp -d "${SCRIPT_DIR}/_leak_sandbox.XXXXXX")"; then
  abort_precondition "could not create the temporary sandbox"
fi
TEST_BIN="${SANDBOX}/sort_test_leaks"

cleanup() {
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

# ---- sanitizer helpers ------------------------------------------------
prepare_suite() {
  local suite_root=$1
  if ! mkdir -p "$suite_root/tests" "$suite_root/logs"; then
    step_fail "suite setup: could not create directories"
    return 1
  fi
  if ! cp "$RUN_TESTS" "$RUN_PERF" "$suite_root/tests/"; then
    step_fail "suite setup: could not copy test runners"
    return 1
  fi
  if ! cp -R "$FIXTURES" "$PERF_DATA" "$suite_root/tests/"; then
    step_fail "suite setup: could not copy test data"
    return 1
  fi
  return 0
}

build_sanitizer_binary() {
  local label=$1
  local suite_root=$2
  shift 2
  local -a sanitizer_flags=("$@")
  local output="${suite_root}/sorter"
  local log="${suite_root}/logs/build.log"

  if (
    cd "$ROOT"
    cc -std=c17 -Wall -Wextra -O1 -g -fno-omit-frame-pointer \
      "${sanitizer_flags[@]}" -o "$output" "${SRC[@]}" -pthread
  ) > "$log" 2>&1; then
    step_pass "$label build"
    return 0
  fi

  step_fail "$label build"
  print_log_excerpt "$log"
  return 1
}

run_quiet_runner() {
  local label=$1
  local log=$2
  local suite_root=$3
  shift 3
  local summary

  if "$@" > "$log" 2>&1; then
    summary="$(summarize_runner_log "$log")"
    step_pass "$label ${c_dim}($summary)${c_reset}"
    return 0
  fi

  step_fail "$label"
  print_log_excerpt "$log"
  show_sanitizer_diagnostics "$suite_root"
  return 1
}

run_asan_ubsan_tests() {
  local suite_root="${SANDBOX}/asan-ubsan-suite"
  local asan_options="detect_leaks=0:halt_on_error=1"
  local ubsan_options="halt_on_error=1:print_stacktrace=1"

  print ""
  print "  ${c_dim}[1/3] ASan + UBSan${c_reset}"

  if ! prepare_suite "$suite_root"; then return 1; fi
  if ! build_sanitizer_binary "ASan/UBSan" "$suite_root" \
       -fsanitize=address,undefined -fno-sanitize-recover=all; then
    return 1
  fi
  if ! run_quiet_runner "ASan/UBSan correctness" \
       "${suite_root}/logs/correctness.log" "$suite_root" \
       env ASAN_OPTIONS="$asan_options" UBSAN_OPTIONS="$ubsan_options" \
       zsh "${suite_root}/tests/run_tests.zsh" -k; then
    return 1
  fi
  if ! run_quiet_runner "ASan/UBSan performance" \
       "${suite_root}/logs/performance.log" "$suite_root" \
       env ASAN_OPTIONS="$asan_options" UBSAN_OPTIONS="$ubsan_options" \
       zsh "${suite_root}/tests/run_perf_test.zsh"; then
    return 1
  fi
  return 0
}

run_tsan_tests() {
  local suite_root="${SANDBOX}/tsan-suite"
  local tsan_options="halt_on_error=1"

  print ""
  print "  ${c_dim}[2/3] TSan${c_reset}"

  if ! prepare_suite "$suite_root"; then return 1; fi
  if ! build_sanitizer_binary "TSan" "$suite_root" -fsanitize=thread; then
    return 1
  fi
  if ! run_quiet_runner "TSan performance" \
       "${suite_root}/logs/performance.log" "$suite_root" \
       env TSAN_OPTIONS="$tsan_options" \
       zsh "${suite_root}/tests/run_perf_test.zsh"; then
    return 1
  fi
  return 0
}

run_leaks_test() {
  local build_log="${SANDBOX}/leaks-build.log"
  local setup_log="${SANDBOX}/leaks-setup.log"
  local run_log="${SANDBOX}/leaks-run.log"
  local summary

  print ""
  print "  ${c_dim}[3/3] macOS leaks${c_reset}"

  if ! (
    cd "$ROOT"
    cc -Wall -Wextra -O0 -g -o "$TEST_BIN" "${SRC[@]}" -pthread
  ) > "$build_log" 2>&1; then
    step_fail "leaks build"
    print_log_excerpt "$build_log"
    return 1
  fi

  if ! "$PLIST_BUDDY" \
       -c "Add :com.apple.security.get-task-allow bool true" \
       "${SANDBOX}/tmp.entitlements" > "$setup_log" 2>&1; then
    step_fail "leaks code-sign setup"
    print_log_excerpt "$setup_log"
    return 1
  fi
  if ! codesign -s - --entitlements "${SANDBOX}/tmp.entitlements" \
       -f "$TEST_BIN" >> "$setup_log" 2>&1; then
    step_fail "leaks code-sign"
    print_log_excerpt "$setup_log"
    return 1
  fi
  if ! cp "$FIX_INPUT" "$SANDBOX/" >> "$setup_log" 2>&1; then
    step_fail "leaks fixture setup"
    print_log_excerpt "$setup_log"
    return 1
  fi
  step_pass "leaks build + code-sign"

  if ! (
    cd "$SANDBOX"
    export MallocStackLogging=1
    export MallocScribble=1
    leaks -quiet -groupByType -conservative -atExit -- \
      ./sort_test_leaks --order asc basic.txt
  ) > "$run_log" 2>&1; then
    step_fail "leak scan"
    print_log_excerpt "$run_log"
    return 1
  fi

  summary="$(summarize_leaks_log "$run_log")"
  step_pass "leak scan ${c_dim}($summary)${c_reset}"
  return 0
}

# ---- execute all checks -----------------------------------------------
if ! run_asan_ubsan_tests; then
  print ""
  print "  ${c_red}Failures:${c_reset}"
  for line in "${failure_details[@]}"; do print "    $line"; done
  print ""
  print "  ${c_green}$pass passed${c_reset}, ${c_red}$fail failed${c_reset}${c_dim}, aborted during ASan/UBSan${c_reset}"
  exit 1
fi
if ! run_tsan_tests; then
  print ""
  print "  ${c_red}Failures:${c_reset}"
  for line in "${failure_details[@]}"; do print "    $line"; done
  print ""
  print "  ${c_green}$pass passed${c_reset}, ${c_red}$fail failed${c_reset}${c_dim}, aborted during TSan${c_reset}"
  exit 1
fi
if ! run_leaks_test; then
  print ""
  print "  ${c_red}Failures:${c_reset}"
  for line in "${failure_details[@]}"; do print "    $line"; done
  print ""
  print "  ${c_green}$pass passed${c_reset}, ${c_red}$fail failed${c_reset}${c_dim}, aborted during leaks${c_reset}"
  exit 1
fi

# ---- summary ----------------------------------------------------------
if (( ${#failure_details[@]} > 0 )); then
  print ""
  print "  ${c_red}Failures:${c_reset}"
  for line in "${failure_details[@]}"; do print "    $line"; done
fi

print ""
total=$((pass + fail))
if (( fail == 0 )); then
  print "  ${c_green}$pass passed${c_reset}${c_dim}, all sanitizer and memory checks clean${c_reset}"
else
  print "  ${c_green}$pass passed${c_reset}, ${c_red}$fail failed${c_reset}"
fi

(( fail == 0 )) || exit 1
exit 0
