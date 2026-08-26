#!/usr/bin/env zsh
#
# check_leaks.zsh - Memory leak check for the sorter using `leaks` (macOS).
#
# Builds a disposable test binary (sort_test_leaks) from the project
# sources in an isolated sandbox, re-signs it ad-hoc with the
# com.apple.security.get-task-allow entitlement so that `leaks` can
# examine it, and runs:
#
#   leaks -quiet -groupByType -conservative -atExit -- ./sort_test_leaks ...
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

# L-05 fix: use mktemp for a unique sandbox (no stale-state conflicts).
SANDBOX="$(mktemp -d "${SCRIPT_DIR}/_leak_sandbox.XXXXXX")"
TEST_BIN="${SANDBOX}/sort_test_leaks"

# M-08 fix: deterministic log level.
export LOG_LEVEL=INFO
export LC_ALL=C

# ---- OS check (macOS only) --------------------------------------------
os="$(uname -s)"
if [[ $os != "Darwin" ]]; then
  print -u2 "check_leaks.zsh: this script runs only on macOS (current system: $os)."
  exit 1
fi

# ---- automatic cleanup before exit -------------------------------------
cleanup() {
  rm -rf "$SANDBOX"
}
trap cleanup EXIT

# ---- tool check ---------------------------------------------------------
if ! command -v leaks > /dev/null; then
  print -u2 "check_leaks.zsh: leaks not found in PATH. Install the Xcode command-line tools (xcode-select --install)."
  exit 1
fi

# ---- input preconditions -------------------------------------------------
if [[ ! -f $FIX_INPUT ]]; then
  print -u2 "check_leaks.zsh: fixture input not found: $FIX_INPUT (run 'make fixtures' first?)"
  exit 1
fi

# ---- build the disposable test binary ------------------------------------
print "Building disposable test binary (sort_test_leaks) ..."
if ! ( cd "$ROOT" && cc -Wall -Wextra -O0 -g -o "${TEST_BIN}" "${SRC[@]}" -pthread ); then
  print -u2 "check_leaks.zsh: failed to build sort_test_leaks."
  exit 1
fi

# L-05 fix: create entitlements fresh in the unique sandbox (no stale file).
/usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" "${SANDBOX}/tmp.entitlements" > /dev/null
if ! codesign -s - --entitlements "${SANDBOX}/tmp.entitlements" -f "$TEST_BIN" > /dev/null; then
  print -u2 "check_leaks.zsh: failed to sign sort_test_leaks."
  exit 1
fi

cp "$FIX_INPUT" "$SANDBOX/"

# ---- leak check -----------------------------------------------------------
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
