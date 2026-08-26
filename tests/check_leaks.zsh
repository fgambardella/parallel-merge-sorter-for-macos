#!/usr/bin/env zsh
#
# check_leaks.sh - Memory leak check for the sorter using `leaks` (macOS).
#
# Builds a disposable test binary (sort_test_leaks) from the project
# sources in an isolated sandbox, re-signs it ad-hoc with the
# com.apple.security.get-task-allow entitlement so that `leaks` can
# examine it, and runs:
#
#   leaks -quiet -groupByType -conservative -atExit -- ./sort_test_leaks ...
#
# `-atExit` launches the process, enables MallocStackLogging, reports
# leaks at process exit, and exits non-zero when leaks are found.
# The test binary is compiled with -O0 -g because, on this platform,
# `leaks` (running with restricted memory access) only reliably detects
# leaks in unoptimized builds.
#
# Exits 0 when `leaks` reports no leaks, non-zero otherwise.
# All temporary artifacts are removed before the script exits.
#
set -euo pipefail

# ---- project layout ---------------------------------------------------
SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"
SRC=(main.c logging.c list.c io.c mergesort.c)
FIX_INPUT="${SCRIPT_DIR}/fixtures/basic_asc/basic.txt"
SANDBOX="${SCRIPT_DIR}/_leak_sandbox"
TEST_BIN="${SANDBOX}/sort_test_leaks"

# ---- OS check (macOS only) --------------------------------------------
os="$(uname -s)"
if [[ $os != "Darwin" ]]; then
  print -u2 "check_leaks.sh: this script runs only on macOS (current system: $os)."
  exit 1
fi

# ---- automatic cleanup before exit -------------------------------------
cleanup() {
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

# ---- tool check ---------------------------------------------------------
if ! command -v leaks > /dev/null; then
  print -u2 "check_leaks.sh: leaks not found in PATH. Install the Xcode command-line tools (xcode-select --install)."
  exit 1
fi

# ---- input preconditions -------------------------------------------------
# Same invocation style as run_tests.zsh:
#   sorter --order asc <input_file>
if [[ ! -f $FIX_INPUT ]]; then
  print -u2 "check_leaks.sh: fixture input not found: $FIX_INPUT (run 'make fixtures' first?)"
  exit 1
fi

# ---- build the disposable test binary ------------------------------------
# -O0 -g: leak detection with `leaks` on this platform requires an
#         unoptimized build.
# -pthread: same linkage as the normal build (see Makefile).
print "Building disposable test binary (sort_test_leaks) ..."
mkdir -p "$SANDBOX"
if ! ( cd "$ROOT" && cc -Wall -Wextra -O0 -g -o "${SANDBOX}/sort_test_leaks" "${SRC[@]}" -pthread ); then
  print -u2 "check_leaks.sh: failed to build sort_test_leaks."
  exit 1
fi

# Make the test binary debuggable for `leaks`: ad-hoc re-sign it with
# the com.apple.security.get-task-allow entitlement.
if ! /usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" "${SANDBOX}/tmp.entitlements" > /dev/null; then
  print -u2 "check_leaks.sh: failed to create the entitlements file."
  exit 1
fi
if ! codesign -s - --entitlements "${SANDBOX}/tmp.entitlements" -f "$TEST_BIN" > /dev/null; then
  print -u2 "check_leaks.sh: failed to sign sort_test_leaks."
  exit 1
fi

cp "$FIX_INPUT" "$SANDBOX/"

# ---- leak check -----------------------------------------------------------
# `leaks -atExit` launches the process, enables MallocStackLogging for
# backtraces, and reports leaks at process exit. Its output is left
# visible; a non-zero exit code means leaks were detected.
print "Running memory leak check (leaks -atExit) ..."
if (
  cd "$SANDBOX"
  export MallocStackLogging=1
  export MallocScribble=1
  leaks -quiet -groupByType -conservative -atExit -- ./sort_test_leaks --order asc basic.txt
); then
  print "==================================================="
  print " Memory leak check passed: no leaks detected."
  print "==================================================="
  exit 0
else
  print -u2 "==================================================="
  print -u2 " Memory leak check failed: leaks detected."
  print -u2 "==================================================="
  exit 1
fi