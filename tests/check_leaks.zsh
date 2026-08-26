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
RULE="================================================================"

# Deterministic test behavior.
export LOG_LEVEL=INFO
export LC_ALL=C

# ---- report formatting ------------------------------------------------
print_header() {
  print "$RULE"
  print " Sorter sanitizer and memory checks"
  print "$RULE"
}

print_section() {
  local number=$1
  local title=$2

  print ""
  printf '[%s/3] %s\n' "$number" "$title"
}

print_status() {
  local state=$1
  local message=$2

  printf '  %-8s %s\n' "[$state]" "$message"
}

print_result() {
  local state=$1
  local message=$2

  print ""
  print "$RULE"
  printf ' RESULT: %s - %s\n' "$state" "$message"
  print "$RULE"
}

abort_precondition() {
  print_status "FAIL" "$1"
  print_result "FAIL" "precondition check failed"
  exit 1
}

print_log_excerpt() {
  local log=$1

  if [[ -s $log ]]; then
    print "    Captured output (last 60 lines):"
    tail -n 60 "$log" | sed 's/^/      /'
  fi
  return 0
}

report_command_failure() {
  local label=$1
  local log=$2

  print_status "FAIL" "$label"
  print_log_excerpt "$log"
  return 0
}

summarize_runner_log() {
  local log=$1
  local summary

  if ! summary="$(awk '
      /^[[:space:]]*Results:/ { line = $0 }
      END {
        sub(/^[[:space:]]*Results:[[:space:]]*/, "", line)
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

show_sanitizer_diagnostics() {
  local suite_root=$1
  local log
  local relative

  for log in "$suite_root"/tests/**/*.log(N); do
    if grep -Eq \
      'AddressSanitizer|UndefinedBehaviorSanitizer|ThreadSanitizer|runtime error:|SUMMARY:.*Sanitizer' \
      "$log"; then
      relative="${log#$suite_root/}"
      print "    Sanitizer diagnostic from $relative (last 80 lines):"
      tail -n 80 "$log" | sed 's/^/      /'
    fi
  done
  return 0
}

# ---- platform and tool preconditions ----------------------------------
print_header

os="$(uname -s)"
if [[ $os != "Darwin" ]]; then
  abort_precondition "macOS required (current system: $os)"
fi
if ! command -v cc > /dev/null; then
  abort_precondition "C compiler not found in PATH"
fi
if ! command -v leaks > /dev/null; then
  abort_precondition "leaks not found; install the Xcode command-line tools"
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
    print_status "FAIL" "Suite setup - could not create directories"
    return 1
  fi
  if ! cp "$RUN_TESTS" "$RUN_PERF" "$suite_root/tests/"; then
    print_status "FAIL" "Suite setup - could not copy test runners"
    return 1
  fi
  if ! cp -R "$FIXTURES" "$PERF_DATA" "$suite_root/tests/"; then
    print_status "FAIL" "Suite setup - could not copy test data"
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
    print_status "PASS" "Build"
    return 0
  fi

  report_command_failure "$label build" "$log"
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
    print_status "PASS" "$label - $summary"
    return 0
  fi

  report_command_failure "$label" "$log"
  show_sanitizer_diagnostics "$suite_root"
  return 1
}

run_asan_ubsan_tests() {
  local suite_root="${SANDBOX}/asan-ubsan-suite"
  local asan_options="detect_leaks=0:halt_on_error=1"
  local ubsan_options="halt_on_error=1:print_stacktrace=1"

  print_section 1 "AddressSanitizer + UndefinedBehaviorSanitizer"

  if ! prepare_suite "$suite_root"; then
    return 1
  fi
  if ! build_sanitizer_binary "ASan/UBSan" "$suite_root" \
       -fsanitize=address,undefined -fno-sanitize-recover=all; then
    return 1
  fi
  if ! run_quiet_runner "Correctness suite" \
       "${suite_root}/logs/correctness.log" "$suite_root" \
       env ASAN_OPTIONS="$asan_options" UBSAN_OPTIONS="$ubsan_options" \
       zsh "${suite_root}/tests/run_tests.zsh" -k; then
    return 1
  fi
  if ! run_quiet_runner "Threaded performance" \
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

  print_section 2 "ThreadSanitizer"

  if ! prepare_suite "$suite_root"; then
    return 1
  fi
  if ! build_sanitizer_binary "TSan" "$suite_root" -fsanitize=thread; then
    return 1
  fi
  if ! run_quiet_runner "Threaded performance" \
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

  print_section 3 "macOS leaks"

  if ! (
    cd "$ROOT"
    cc -Wall -Wextra -O0 -g -o "$TEST_BIN" "${SRC[@]}" -pthread
  ) > "$build_log" 2>&1; then
    report_command_failure "Build" "$build_log"
    return 1
  fi

  if ! "$PLIST_BUDDY" \
       -c "Add :com.apple.security.get-task-allow bool true" \
       "${SANDBOX}/tmp.entitlements" > "$setup_log" 2>&1; then
    report_command_failure "Code-sign setup" "$setup_log"
    return 1
  fi
  if ! codesign -s - --entitlements "${SANDBOX}/tmp.entitlements" \
       -f "$TEST_BIN" >> "$setup_log" 2>&1; then
    report_command_failure "Code-sign" "$setup_log"
    return 1
  fi
  if ! cp "$FIX_INPUT" "$SANDBOX/" >> "$setup_log" 2>&1; then
    report_command_failure "Fixture setup" "$setup_log"
    return 1
  fi
  print_status "PASS" "Build and code-sign"

  if ! (
    cd "$SANDBOX"
    export MallocStackLogging=1
    export MallocScribble=1
    leaks -quiet -groupByType -conservative -atExit -- \
      ./sort_test_leaks --order asc basic.txt
  ) > "$run_log" 2>&1; then
    report_command_failure "Leak scan" "$run_log"
    return 1
  fi

  summary="$(summarize_leaks_log "$run_log")"
  print_status "PASS" "Leak scan - $summary"
  return 0
}

# ---- execute all checks -----------------------------------------------
if ! run_asan_ubsan_tests; then
  print_result "FAIL" "stopped during ASan/UBSan checks"
  exit 1
fi
if ! run_tsan_tests; then
  print_result "FAIL" "stopped during TSan checks"
  exit 1
fi
if ! run_leaks_test; then
  print_result "FAIL" "stopped during macOS leaks check"
  exit 1
fi

print_result "PASS" "all sanitizer and memory checks completed"
exit 0
