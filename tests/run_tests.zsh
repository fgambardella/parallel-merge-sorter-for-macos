#!/usr/bin/env zsh
#
# run_tests.zsh - Automated test runner for the sorter.
#
# For every fixture case under tests/fixtures/<case>/ it:
#   1. runs the sorter in an isolated sandbox directory,
#   2. checks the exit code,
#   3. checks the generated output file name,
#   4. compares the generated output content with the expected file,
#   5. verifies whether a WARN log was (not) expected.
#
# Usage:  ./run_tests.zsh [-k]
#   -k  keep the sandbox directories for inspection
#
set -uo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT="${SCRIPT_DIR:h}"
BINARY="${ROOT}/sorter"
FIX="${SCRIPT_DIR}/fixtures"
SANDBOX_ROOT="${SCRIPT_DIR}/_sandbox"

KEEP=0
[[ ${1:-} == "-k" ]] && KEEP=1

# M-08 fix: deterministic environment for all test invocations.
export LC_ALL=C

# ---- color support (disabled if not a terminal) ----------------------
if [[ -t 1 ]]; then
  c_green=$'\033[32m'; c_red=$'\033[31m'; c_dim=$'\033[2m'; c_reset=$'\033[0m'
else
  c_green=; c_red=; c_dim=; c_reset=
fi

# ---- preconditions ---------------------------------------------------
if [[ ! -x $BINARY ]]; then
  print "Building sorter ..."
  ( cd "$ROOT" && make build ) || {
    print -u2 "Build failed."; exit 1 }
fi
if [[ ! -d $FIX ]]; then
  print "No fixtures found; generating ..."
  zsh "${SCRIPT_DIR}/generate_fixtures.zsh"
fi

rm -rf "$SANDBOX_ROOT"
mkdir -p "$SANDBOX_ROOT"

pass=0; fail=0; cases=0
# Collect failure details to print at the end of the suite.
typeset -a failure_details=()

# ---- human-readable labels for fixture cases --------------------------
typeset -A labels=(
  [bad_cli_invalid_order]="invalid --order value"
  [bad_cli_missing_order_val]="missing --order value"
  [bad_cli_multi_files]="multiple input files"
  [bad_cli_unknown_opt]="unknown option"
  [basic_asc]="basic ascending sort"
  [basic_desc]="basic descending sort"
  [boundary_255]="boundary line 255 bytes"
  [boundary_256]="boundary line 256 bytes"
  [boundary_257]="boundary line 257 bytes (rejected)"
  [crlf]="CRLF line endings"
  [dashdash]="-- end-of-options marker"
  [default_asc]="default order (ascending)"
  [duplicates]="duplicate lines"
  [embedded_cr]="embedded CR mid-line"
  [empty_file]="empty input file"
  [empty_lines]="empty lines skipped"
  [hidden_file]="hidden file (dotfile)"
  [missing_input]="missing input file"
  [no_trailing_lf]="no trailing newline"
  [noext]="file without extension"
  [nul_at_eof]="NUL byte at EOF"
  [nul_midline]="NUL byte mid-line"
  [numbers]="numeric strings (lexicographic)"
  [overlong]="overlong line (>256 bytes)"
  [random]="50 random strings"
  [single]="single element"
  [special]="spaces, quotes, tabs"
  [tarball]="multi-dot extension"
  [ultralong]="ultra-long line (>4096 bytes)"
)

# ---- run every case ---------------------------------------------------
for meta in "$FIX"/*/.meta(N); do
  dir="${meta:h}"
  case_name="${dir:t}"
  cases=$((cases + 1))

  # read .meta
  order=asc; input=; output=; exit_code=0; expect_warn=no; use_default=no; use_dashdash=no; cli_override=
  while IFS='=' read -r k v; do
    case $k in
      order) order=$v ;;
      input) input=$v ;;
      output) output=$v ;;
      exit) exit_code=$v ;;
      expect_warn) expect_warn=$v ;;
      use_default) use_default=$v ;;
      use_dashdash) use_dashdash=$v ;;
      cli_override) cli_override=$v ;;
    esac
  done < "$meta"

  # sandbox for this case
  sb="$SANDBOX_ROOT/$case_name"
  mkdir -p "$sb"
  copied_files=()
  if [[ -n $cli_override ]]; then
    for src_file in "$dir"/*(ND.); do
      [[ "${src_file:t}" == ".meta" ]] && continue
      cp "$src_file" "$sb/"
      copied_files+=("${src_file:t}")
    done
  elif [[ -f "$dir/$input" ]]; then
    cp "$dir/$input" "$sb/"
    copied_files+=("$input")
  fi

  log="$sb/run.log"
  (
    cd "$sb"
    if [[ -n $cli_override ]]; then
      LOG_LEVEL=INFO "$BINARY" ${=cli_override}
    elif [[ $use_default == yes ]]; then
      LOG_LEVEL=INFO "$BINARY" "$input"
    elif [[ $use_dashdash == yes ]]; then
      LOG_LEVEL=INFO "$BINARY" --order "$order" -- "$input"
    else
      LOG_LEVEL=INFO "$BINARY" --order "$order" "$input"
    fi
  ) > /dev/null 2> "$log"
  actual_exit=$?

  # ---- collect assertion results for this case ----
  case_pass=0; case_fail=0
  case_errors=()

  # 1. exit code
  if (( actual_exit == exit_code )); then
    case_pass=$((case_pass + 1))
  else
    case_fail=$((case_fail + 1))
    case_errors+=("exit code: expected $exit_code, got $actual_exit")
  fi

  # 2. generated output file name
  generated=()
  for f in "$sb"/*(ND.); do
    base="${f:t}"
    [[ $base == "run.log" ]] && continue
    is_input=0
    for cf in "${copied_files[@]}"; do
      [[ $base == "$cf" ]] && { is_input=1; break; }
    done
    (( is_input )) && continue
    generated+=("$base")
  done

  if [[ $output != NONE ]]; then
    cnt=${#generated[@]}
    first=${generated[1]:-}
    if (( cnt == 1 )) && [[ "$first" == "$output" ]]; then
      case_pass=$((case_pass + 1))
    else
      case_fail=$((case_fail + 1))
      case_errors+=("output file: expected \"$output\", found: ${generated[*]:-<none>}")
    fi

    # 3. content comparison
    if [[ -f "$sb/$output" ]]; then
      if diff -q "$dir/$output" "$sb/$output" > /dev/null 2>&1; then
        case_pass=$((case_pass + 1))
      else
        case_fail=$((case_fail + 1))
        local diff_out
        diff_out=$(diff "$dir/$output" "$sb/$output" | head -10)
        case_errors+=("content mismatch for $output:" "$diff_out")
      fi
    else
      case_fail=$((case_fail + 1))
      case_errors+=("expected output file \"$output\" was not created")
    fi
  else
    if (( ${#generated[@]} == 0 )); then
      case_pass=$((case_pass + 1))
    else
      case_fail=$((case_fail + 1))
      case_errors+=("unexpected output file(s): ${generated[*]}")
    fi
  fi

  # 4. WARN log expectation
  if grep -q "\[WARN " "$log" 2> /dev/null; then got_warn=yes; else got_warn=no; fi
  if [[ $expect_warn == $got_warn ]]; then
    case_pass=$((case_pass + 1))
  else
    case_fail=$((case_fail + 1))
    case_errors+=("WARN: expected=$expect_warn got=$got_warn")
  fi

  # ---- print one line per case ----
  pass=$((pass + case_pass))
  fail=$((fail + case_fail))
  display_name="${labels[$case_name]:-$case_name}"
  if (( case_fail == 0 )); then
    print "  ${c_green}PASS${c_reset}  $display_name"
  else
    print "  ${c_red}FAIL${c_reset}  $display_name"
    # Stash details for the failures section
    failure_details+=("$display_name")
    for err in "${case_errors[@]}"; do
      failure_details+=("        $err")
    done
  fi
done

# M-07 fix: require at least one test case.
if (( cases == 0 )); then
  print -u2 "ERROR: no test cases found under $FIX"
  exit 1
fi

# ---- integration tests -----------------------------------------------
print ""
print "  ${c_dim}Integration tests${c_reset}"

itg_pass=0; itg_fail=0
itg_errors=()

itg_ok()  { itg_pass=$((itg_pass + 1)); }
itg_bad() { itg_fail=$((itg_fail + 1)); itg_errors+=("$1"); }

# I-1: H-01 regression - dotted parent directory
itg_dir="$SANDBOX_ROOT/_integration"
mkdir -p "$itg_dir/release.v1.2"
printf 'cherry\napple\nbanana\n' > "$itg_dir/release.v1.2/data"
(LOG_LEVEL=INFO "$BINARY" --order asc "$itg_dir/release.v1.2/data") > /dev/null 2>&1
if [[ -f "$itg_dir/release.v1.2/data_ordered_asc" ]]; then
  expected=$(printf 'apple\nbanana\ncherry\n')
  actual=$(cat "$itg_dir/release.v1.2/data_ordered_asc")
  if [[ "$actual" == "$expected" ]]; then
    itg_ok
  else
    itg_bad "H-01: content mismatch with dotted parent"
  fi
else
  itg_bad "H-01: output not created beside input (dotted parent dir)"
fi

# I-2: H-02 regression - symlink at output path
mkdir -p "$itg_dir/symlink_test"
printf 'beta\nalpha\n' > "$itg_dir/symlink_test/input.txt"
mkdir -p "$itg_dir/symlink_test/trap"
ln -sf "$itg_dir/symlink_test/trap/victim" "$itg_dir/symlink_test/input_ordered_asc.txt"
(LOG_LEVEL=INFO "$BINARY" --order asc "$itg_dir/symlink_test/input.txt") > /dev/null 2>&1
if [[ -f "$itg_dir/symlink_test/input_ordered_asc.txt" ]] && \
   [[ ! -L "$itg_dir/symlink_test/input_ordered_asc.txt" ]]; then
  if [[ ! -e "$itg_dir/symlink_test/trap/victim" ]]; then
    itg_ok
  else
    itg_bad "H-02: symlink target was written to"
  fi
else
  itg_bad "H-02: symlink was followed or output missing"
fi

# I-3: M-01 regression - output permissions match input
mkdir -p "$itg_dir/perm_test"
printf 'beta\nalpha\n' > "$itg_dir/perm_test/secret.txt"
chmod 600 "$itg_dir/perm_test/secret.txt"
(LOG_LEVEL=INFO "$BINARY" --order asc "$itg_dir/perm_test/secret.txt") > /dev/null 2>&1
if [[ -f "$itg_dir/perm_test/secret_ordered_asc.txt" ]]; then
  out_perms=$(stat -f '%Lp' "$itg_dir/perm_test/secret_ordered_asc.txt")
  if [[ "$out_perms" == "600" ]]; then
    itg_ok
  else
    itg_bad "M-01: output perms are $out_perms, expected 600"
  fi
else
  itg_bad "M-01: output file not created"
fi

# I-4: M-03 regression - stale output replaced by empty run
mkdir -p "$itg_dir/stale_test"
printf 'stale content\n' > "$itg_dir/stale_test/empty_ordered_asc.txt"
: > "$itg_dir/stale_test/empty.txt"
(LOG_LEVEL=INFO "$BINARY" --order asc "$itg_dir/stale_test/empty.txt") > /dev/null 2>&1
if [[ -f "$itg_dir/stale_test/empty_ordered_asc.txt" ]]; then
  stale_size=$(wc -c < "$itg_dir/stale_test/empty_ordered_asc.txt" | tr -d ' ')
  if (( stale_size == 0 )); then
    itg_ok
  else
    itg_bad "M-03: stale output NOT replaced (size=$stale_size)"
  fi
else
  itg_bad "M-03: output file missing after empty run"
fi

# I-5: H-01 regression - ./relative dotfile path
mkdir -p "$itg_dir/dotfile_rel"
printf 'charlie\nalpha\n' > "$itg_dir/dotfile_rel/.secret"
(cd "$itg_dir/dotfile_rel" && LOG_LEVEL=INFO "$BINARY" --order asc ./.secret) > /dev/null 2>&1
if [[ -f "$itg_dir/dotfile_rel/.secret_ordered_asc" ]]; then
  itg_ok
else
  itg_bad "H-01: dotfile with ./ prefix failed"
fi

# Print integration results as one line
itg_total=$((itg_pass + itg_fail))
if (( itg_fail == 0 )); then
  print "  ${c_green}PASS${c_reset}  dotted parent directory"
  print "  ${c_green}PASS${c_reset}  symlink at output not followed"
  print "  ${c_green}PASS${c_reset}  permission preservation"
  print "  ${c_green}PASS${c_reset}  stale output replaced"
  print "  ${c_green}PASS${c_reset}  relative dotfile path"
else
  for err in "${itg_errors[@]}"; do
    print "  ${c_red}FAIL${c_reset}  $err"
  done
  # Print any that passed without naming them individually
  if (( itg_pass > 0 )); then
    print "  ${c_green}PASS${c_reset}  ($itg_pass other integration tests)"
  fi
  failure_details+=("Integration tests: ${itg_errors[*]}")
fi

pass=$((pass + itg_pass))
fail=$((fail + itg_fail))

# ---- print failure details if any ------------------------------------
if (( ${#failure_details[@]} > 0 )); then
  print ""
  print "  ${c_red}Failures:${c_reset}"
  for line in "${failure_details[@]}"; do
    print "    $line"
  done
fi

# ---- summary ----------------------------------------------------------
print ""
total=$((pass + fail))
if (( fail == 0 )); then
  print "  ${c_green}$pass passed${c_reset}${c_dim}, $total assertions ($cases fixture cases + 5 integration)${c_reset}"
else
  print "  ${c_green}$pass passed${c_reset}, ${c_red}$fail failed${c_reset}${c_dim}, $total assertions ($cases fixture cases + 5 integration)${c_reset}"
fi

if (( KEEP )); then
  print "  Sandbox kept at: $SANDBOX_ROOT"
else
  rm -rf "$SANDBOX_ROOT"
fi

(( fail == 0 )) || exit 1
exit 0
