#!/usr/bin/env zsh
#
# generate_fixtures.zsh - Generate all test fixtures for the sorter.
#
# For every case it creates tests/fixtures/<case>/ containing:
#   - the input file (with edge cases baked in),
#   - the expected output file (unless the case must produce none),
#   - a .meta file describing the case for run_tests.zsh.
#
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
FIX="${SCRIPT_DIR}/fixtures"

# L-04 fix: export LC_ALL=C for consistent awk/sort behavior.
export LC_ALL=C

rm -rf "$FIX"
mkdir -p "$FIX"

# write_case <name> <order> <input> <output|NONE> [warn] [use_default]
write_case() {
  local name="$1" order="$2" input="$3" output="$4"
  local warn="${5:-no}" use_default="${6:-no}"
  local dir="$FIX/$name" flag=()

  mkdir -p "$dir"

  if [[ $output != NONE ]]; then
    [[ $order == desc ]] && flag+=(-r)
    # Expected content = the lines the sorter must keep (non-empty and
    # <= MAX_LENGTH=256, CR stripped only at end), sorted in byte order.
    awk '{ sub(/\r$/, ""); if (length($0) > 0 && length($0) <= 256) print }' \
      "$dir/$input" | LC_ALL=C sort $flag > "$dir/$output"
  fi

  {
    print "order=$order"
    print "input=$input"
    print "output=$output"
    print "exit=0"
    print "expect_warn=$warn"
    print "use_default=$use_default"
  } > "$dir/.meta"
  print "  generated: $name"
}

echo "Generating fixtures in $FIX ..."

# 1. basic ascending
d="$FIX/basic_asc"; mkdir -p $d
printf 'banana\napple\ncherry\n' > "$d/basic.txt"
write_case basic_asc asc basic.txt basic_ordered_asc.txt

# 2. basic descending
d="$FIX/basic_desc"; mkdir -p $d
printf 'banana\napple\ncherry\n' > "$d/basic.txt"
write_case basic_desc desc basic.txt basic_ordered_desc.txt

# 3. default order: --order omitted, must sort ascending
d="$FIX/default_asc"; mkdir -p $d
printf 'delta\nalpha\ncharlie\nbravo\n' > "$d/default.txt"
write_case default_asc asc default.txt default_ordered_asc.txt no yes

# 4. line with 256 < len <= 4096 -> WARN + skipped
d="$FIX/overlong"; mkdir -p $d
{
  printf 'apple\n'
  awk 'BEGIN { for (i = 0; i < 300; i++) printf "x" }'
  printf '\ncherry\n'
} > "$d/overlong.txt"
write_case overlong asc overlong.txt overlong_ordered_asc.txt yes

# 5. line longer than the 4096-byte read buffer -> WARN + the whole
#    physical line must be consumed, not partially re-parsed
d="$FIX/ultralong"; mkdir -p $d
{
  printf 'apple\n'
  awk 'BEGIN { for (i = 0; i < 5000; i++) printf "x" }'
  printf '\nbanana\ncherry\n'
} > "$d/ultralong.txt"
write_case ultralong asc ultralong.txt ultralong_ordered_asc.txt yes

# 6. empty lines are skipped
d="$FIX/empty_lines"; mkdir -p $d
printf 'apple\n\ncherry\n\nbanana\n\n' > "$d/empty_lines.txt"
write_case empty_lines asc empty_lines.txt empty_lines_ordered_asc.txt

# 7. single element
d="$FIX/single"; mkdir -p $d
printf 'solo\n' > "$d/single.txt"
write_case single asc single.txt single_ordered_asc.txt

# 8. empty input file -> empty output file is written (M-03 fix)
d="$FIX/empty_file"; mkdir -p $d
: > "$d/empty.txt"
{
  print "order=asc"
  print "input=empty.txt"
  print "output=empty_ordered_asc.txt"
  print "exit=0"
  print "expect_warn=yes"
  print "use_default=no"
} > "$d/.meta"
# The expected output is an empty file (M-03: empty run writes empty output).
: > "$d/empty_ordered_asc.txt"
print "  generated: empty_file"

# 9. duplicates
d="$FIX/duplicates"; mkdir -p $d
printf 'apple\nbanana\napple\nbanana\napple\n' > "$d/duplicates.txt"
write_case duplicates asc duplicates.txt duplicates_ordered_asc.txt

# 10. input file without extension
d="$FIX/noext"; mkdir -p $d
printf 'zebra\nyak\n' > "$d/noext"
write_case noext asc noext noext_ordered_asc

# 11. multi-dot extension: suffix goes before the LAST extension
d="$FIX/tarball"; mkdir -p $d
printf 'gamma\nalpha\n' > "$d/data.tar.gz"
write_case tarball desc data.tar.gz data.tar_ordered_desc.gz

# 12. CRLF line endings
d="$FIX/crlf"; mkdir -p $d
printf 'peach\r\nkiwi\r\nmango\r\n' > "$d/crlf.txt"
write_case crlf asc crlf.txt crlf_ordered_asc.txt

# 13. spaces, quotes, tabs
d="$FIX/special"; mkdir -p $d
{
  printf 'hello world\n'
  printf 'hi!there\n'
  printf 'a"b\n'
  printf 'tab\there\n'
} > "$d/special.txt"
write_case special asc special.txt special_ordered_asc.txt

# 14. numeric strings sort lexicographically, not numerically
d="$FIX/numbers"; mkdir -p $d
printf '10\n2\n100\n20\n' > "$d/numbers.txt"
write_case numbers asc numbers.txt numbers_ordered_asc.txt

# 15. 50 deterministic (seeded) random strings
d="$FIX/random"; mkdir -p $d
python3 -c "
import random
random.seed(20260819)
for _ in range(50):
    print(''.join(random.choices('abcdefghijklmnopqrstuvwxyz',
                                 k=random.randint(3, 12))))
" > "$d/random.txt"
write_case random asc random.txt random_ordered_asc.txt

# 16. hidden file (dotfile) - M-10: test dotfile handling
d="$FIX/hidden_file"; mkdir -p $d
printf 'charlie\nalpha\nbravo\n' > "$d/.hidden"
write_case hidden_file asc .hidden .hidden_ordered_asc

# 17. -- end-of-options marker (L-03 test)
d="$FIX/dashdash"; mkdir -p $d
printf 'beta\nalpha\n' > "$d/-dashed.txt"
{
  print "order=asc"
  print "input=-dashed.txt"
  print "output=-dashed_ordered_asc.txt"
  print "exit=0"
  print "expect_warn=no"
  print "use_default=no"
  print "use_dashdash=yes"
} > "$d/.meta"
printf 'alpha\nbeta\n' > "$d/-dashed_ordered_asc.txt"
print "  generated: dashdash"

# 18. embedded CR mid-line (M-02: CR not at end of line is preserved as data)
d="$FIX/embedded_cr"; mkdir -p $d
printf 'zeta\rhidden\nalpha\n' > "$d/embedded_cr.txt"
# The expected output: embedded CR is kept verbatim. "zeta\rhidden" sorts
# after "alpha" because 'z' > 'a'.
{
  printf 'alpha\n'
  printf 'zeta\rhidden\n'
} > "$d/embedded_cr_ordered_asc.txt"
{
  print "order=asc"
  print "input=embedded_cr.txt"
  print "output=embedded_cr_ordered_asc.txt"
  print "exit=0"
  print "expect_warn=no"
  print "use_default=no"
} > "$d/.meta"
print "  generated: embedded_cr"

# 19. dotted parent directory (H-01: dot in parent must not confuse extension)
#     This is tested by running the sorter with a path containing a dotted dir.
#     The fixture itself uses a basename without extension inside a dir whose
#     NAME contains a dot - but since run_tests.zsh runs from inside the sandbox
#     with just the basename, we simulate this by testing the extensionless + 
#     hidden file cases (already covered). A separate integration test in 
#     run_tests.zsh exercises the absolute-path scenario directly.

# 20. Bad CLI: unknown option
d="$FIX/bad_cli_unknown_opt"; mkdir -p $d
printf 'alpha\n' > "$d/input.txt"
{
  print "order=asc"
  print "input=input.txt"
  print "output=NONE"
  print "exit=1"
  print "expect_warn=no"
  print "use_default=no"
  print "cli_override=--invalid input.txt"
} > "$d/.meta"
print "  generated: bad_cli_unknown_opt"

# 21. Bad CLI: missing --order value
d="$FIX/bad_cli_missing_order_val"; mkdir -p $d
printf 'alpha\n' > "$d/input.txt"
{
  print "order=asc"
  print "input=input.txt"
  print "output=NONE"
  print "exit=1"
  print "expect_warn=no"
  print "use_default=no"
  print "cli_override=--order"
} > "$d/.meta"
print "  generated: bad_cli_missing_order_val"

# 22. Bad CLI: multiple input files
d="$FIX/bad_cli_multi_files"; mkdir -p $d
printf 'alpha\n' > "$d/file1.txt"
printf 'beta\n' > "$d/file2.txt"
{
  print "order=asc"
  print "input=file1.txt"
  print "output=NONE"
  print "exit=1"
  print "expect_warn=no"
  print "use_default=no"
  print "cli_override=file1.txt file2.txt"
} > "$d/.meta"
print "  generated: bad_cli_multi_files"

# 23. Bad CLI: invalid --order value
d="$FIX/bad_cli_invalid_order"; mkdir -p $d
printf 'alpha\n' > "$d/input.txt"
{
  print "order=asc"
  print "input=input.txt"
  print "output=NONE"
  print "exit=1"
  print "expect_warn=no"
  print "use_default=no"
  print "cli_override=--order random input.txt"
} > "$d/.meta"
print "  generated: bad_cli_invalid_order"

# 24. Missing input file
d="$FIX/missing_input"; mkdir -p $d
# Note: we do NOT create the input file — it should not exist
{
  print "order=asc"
  print "input=nonexistent.txt"
  print "output=NONE"
  print "exit=1"
  print "expect_warn=no"
  print "use_default=no"
  print "cli_override=--order asc nonexistent.txt"
} > "$d/.meta"
print "  generated: missing_input"

# 25. Boundary-length record: exactly 255 bytes (accepted)
d="$FIX/boundary_255"; mkdir -p $d
{
  printf 'apple\n'
  awk 'BEGIN { for (i = 0; i < 255; i++) printf "A" }'
  printf '\ncherry\n'
} > "$d/boundary.txt"
write_case boundary_255 asc boundary.txt boundary_ordered_asc.txt

# 26. Boundary-length record: exactly 256 bytes (accepted, at MAX_LENGTH)
d="$FIX/boundary_256"; mkdir -p $d
{
  printf 'apple\n'
  awk 'BEGIN { for (i = 0; i < 256; i++) printf "B" }'
  printf '\ncherry\n'
} > "$d/boundary.txt"
write_case boundary_256 asc boundary.txt boundary_ordered_asc.txt

# 27. Boundary-length record: exactly 257 bytes (rejected with WARN)
d="$FIX/boundary_257"; mkdir -p $d
{
  printf 'apple\n'
  awk 'BEGIN { for (i = 0; i < 257; i++) printf "C" }'
  printf '\ncherry\n'
} > "$d/boundary.txt"
write_case boundary_257 asc boundary.txt boundary_ordered_asc.txt yes

# 28. Embedded NUL byte mid-line: rejected with WARN
d="$FIX/nul_midline"; mkdir -p $d
{
  printf 'apple\n'
  printf 'he\x00llo\n'
  printf 'cherry\n'
} > "$d/nul_midline.txt"
# Expected: only apple and cherry (nul line rejected)
{
  printf 'apple\n'
  printf 'cherry\n'
} > "$d/nul_midline_ordered_asc.txt"
{
  print "order=asc"
  print "input=nul_midline.txt"
  print "output=nul_midline_ordered_asc.txt"
  print "exit=0"
  print "expect_warn=yes"
  print "use_default=no"
} > "$d/.meta"
print "  generated: nul_midline"

# 29. Embedded NUL byte at EOF (no trailing newline): rejected with WARN
d="$FIX/nul_at_eof"; mkdir -p $d
{
  printf 'apple\n'
  printf 'beta\x00tail'
} > "$d/nul_eof.txt"
# Expected: only apple (beta\0tail rejected, note no trailing newline)
{
  printf 'apple\n'
} > "$d/nul_eof_ordered_asc.txt"
{
  print "order=asc"
  print "input=nul_eof.txt"
  print "output=nul_eof_ordered_asc.txt"
  print "exit=0"
  print "expect_warn=yes"
  print "use_default=no"
} > "$d/.meta"
print "  generated: nul_at_eof"

# 30. Final record without trailing LF (valid, no NUL)
d="$FIX/no_trailing_lf"; mkdir -p $d
{
  printf 'cherry\n'
  printf 'apple\n'
  printf 'banana'
} > "$d/no_lf.txt"
# Expected: all 3 lines sorted, each with trailing newline in output
{
  printf 'apple\n'
  printf 'banana\n'
  printf 'cherry\n'
} > "$d/no_lf_ordered_asc.txt"
{
  print "order=asc"
  print "input=no_lf.txt"
  print "output=no_lf_ordered_asc.txt"
  print "exit=0"
  print "expect_warn=no"
  print "use_default=no"
} > "$d/.meta"
print "  generated: no_trailing_lf"

echo "Done: fixtures generated under $FIX"
