#!/usr/bin/env zsh
#
# generate_fixtures.zsh - Generate all test fixtures for the sorter.
#
# For every case it creates tests/fixtures/<case>/ containing:
#   - the input file (with edge cases baked in),
#   - the expected output file (unless the case must produce none),
#   - a .meta file describing the case for run_tests.zsh:
#       order=asc|desc
#       input=<input file name>
#       output=<expected output file name | NONE>
#       exit=<expected exit code>
#       expect_warn=yes|no
#       use_default=yes|no   (run without --order, tests the default)
#
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
FIX="${SCRIPT_DIR}/fixtures"

rm -rf "$FIX"
mkdir -p "$FIX"

# write_case <name> <order> <input> <output|NONE> [warn] [use_default]
# (The input file must already exist in $FIX/<name>/.)
write_case() {
  local name="$1" order="$2" input="$3" output="$4"
  local warn="${5:-no}" use_default="${6:-no}"
  local dir="$FIX/$name" flag=()

  mkdir -p "$dir"

  if [[ $output != NONE ]]; then
    [[ $order == desc ]] && flag+=(-r)
    # Expected content = the lines the sorter must keep (non-empty and
    # <= MAX_LENGTH=256, CR stripped), sorted in byte order (strcmp).
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
  printf 'cherry\n'
} > "$d/overlong.txt"
write_case overlong asc overlong.txt overlong_ordered_asc.txt yes

# 5. line longer than the 4096-byte read buffer -> WARN + the whole
#    physical line must be consumed, not partially re-parsed
d="$FIX/ultralong"; mkdir -p $d
{
  printf 'apple\n'
  awk 'BEGIN { for (i = 0; i < 5000; i++) printf "x" }'
  printf 'banana\ncherry\n'
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

# 8. empty input file -> no output file is written at all
#    (the sorter intentionally LOG_WARNs when it has nothing to sort)
d="$FIX/empty_file"; mkdir -p $d
: > "$d/empty.txt"
write_case empty_file asc empty.txt NONE yes

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

echo "Done: fixtures generated under $FIX"