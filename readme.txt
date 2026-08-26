                   ██████╗  █████╗ ██████╗  █████╗ ██╗     ██╗     ███████╗██╗
                   ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██║     ██║     ██╔════╝██║
                   ██████╔╝███████║██████╔╝███████║██║     ██║     █████╗  ██║
                   ██╔═══╝ ██╔══██║██╔══██╗██╔══██║██║     ██║     ██╔══╝  ██║
                   ██║     ██║  ██║██║  ██║██║  ██║███████╗███████╗███████╗███████╗
                   ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝╚══════╝
███╗   ███╗███████╗██████╗  ██████╗ ███████╗    ███████╗ ██████╗ ██████╗ ████████╗███████╗██████╗
████╗ ████║██╔════╝██╔══██╗██╔════╝ ██╔════╝    ██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝██╔════╝██╔══██╗
██╔████╔██║█████╗  ██████╔╝██║  ███╗█████╗      ███████╗██║   ██║██████╔╝   ██║   █████╗  ██████╔╝
██║╚██╔╝██║██╔══╝  ██╔══██╗██║   ██║██╔══╝      ╚════██║██║   ██║██╔══██╗   ██║   ██╔══╝  ██╔══██╗
██║ ╚═╝ ██║███████╗██║  ██║╚██████╔╝███████╗    ███████║╚██████╔╝██║  ██║   ██║   ███████╗██║  ██║
╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝    ╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝
            ███████╗ ██████╗ ██████╗     ███╗   ███╗ █████╗  ██████╗ ██████╗ ███████╗
            ██╔════╝██╔═══██╗██╔══██╗    ████╗ ████║██╔══██╗██╔════╝██╔═══██╗██╔════╝
            █████╗  ██║   ██║██████╔╝    ██╔████╔██║███████║██║     ██║   ██║███████╗
            ██╔══╝  ██║   ██║██╔══██╗    ██║╚██╔╝██║██╔══██║██║     ██║   ██║╚════██║
            ██║     ╚██████╔╝██║  ██║    ██║ ╚═╝ ██║██║  ██║╚██████╗╚██████╔╝███████║
            ╚═╝      ╚═════╝ ╚═╝  ╚═╝    ╚═╝     ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝

====================================================================
 TARGET PLATFORM: MACOS ONLY
====================================================================

This repository has exactly ONE target platform: macOS (Darwin),
on both Apple silicon and Intel Macs. The build system (cc/clang
from the Xcode Command Line Tools), the test scripts (zsh, which
ships with macOS) and the memory-leak verification (leaks,
codesign) rely on macOS-specific tooling. Linux and Windows are
NOT supported and are not supported-by-accident: check_leaks.zsh
refuses to run on any other OS, and no CI or testing matrix exists
for other platforms.

--------------------------------------------------------------------
 WHAT IT IS
--------------------------------------------------------------------

Parallel Merge Sorter is a C program that:

  1. reads the lines of an input file into a heap-allocated singly
     linked list (each node owns a copy of its string),
  2. sorts the strings lexicographically (ascending or descending)
     with a multi-threaded merge sort (POSIX threads),
  3. writes the sorted lines to a NEW file next to the input: the
     input name with "_ordered_asc" or "_ordered_desc" inserted
     right before the last extension.

     data.txt      ->  data_ordered_asc.txt   (or data_ordered_desc.txt)
     data.tar.gz   ->  data.tar_ordered_asc.gz
     data          ->  data_ordered_asc
     .secret       ->  .secret_ordered_asc   (dotfile: no real extension)

The input file is never modified. Sorting only rearranges the char*
pointers; the pointed-to strings are never changed, and the linked
structure itself is left untouched.

Key parameters:

  - MAX_LENGTH   = 256   max accepted length of a data line (main.c)
  - BUF_SIZE     = 4096  line read buffer (io.c; must be > MAX_LENGTH)
  - MSORT_BASE_CASE = 1024  ranges of <= this size are sorted
                     sequentially with a direction-aware insertion sort
  - MSORT_MAX_DEPTH   = 4   max parallel fork levels: the total number
                     of worker threads is bounded to <= 2^4 = 16

How the parallel merge sort works (mergesort.c):

  - ranges larger than MSORT_BASE_CASE are split in half: the left
    half is sorted by a child pthread (per-thread job struct, then
    pthread_join), the right half by the calling thread;
  - fork depth is capped at MSORT_MAX_DEPTH, bounding the thread
    count to at most 16;
  - sorted halves are merged into a caller-supplied O(n) scratch
    buffer and copied back (stable merge);
  - if malloc or pthread_create ever fails, the algorithm degrades
    gracefully to a fully sequential sort (DEBUG log);
  - no global state: everything travels through parameters or
    per-thread job structs, so the code is thread-safe.

  Time: O(n log n)    Space: O(n)

Line-reading policy (io.c, load_strings):

  - a trailing "\r\n" or "\n" is stripped (CRLF input is fine);
  - empty lines are skipped (DEBUG log);
  - lines longer than MAX_LENGTH (256) are skipped with a WARN log;
  - a line that does not fit in the 4096-byte read buffer is
    consumed in full (its tail is never re-parsed as new lines)
    and skipped with a WARN log;
  - ordering is pure byte/strcmp order, so "10" < "2"
    (lexicographic, not numeric).

Features:

  - custom leveled logging (DEBUG < INFO < WARN < ERROR) on stderr,
    with "YYYY-MM-DD HH:MM:SS [LEVEL] file:line message" format;
    runtime override via the LOG_LEVEL environment variable;
  - non-interactive: sort direction is a CLI option, never a prompt;
  - if the input yields no valid lines, a WARN is emitted, NO output
    file is written, and the program still exits 0;
  - the program measures its own wall-clock elapsed time
    (CLOCK_MONOTONIC, nanosecond precision) and emits it as a final
    INFO log line: "Elapsed time: <s>.<ns> s".

--------------------------------------------------------------------
 REPOSITORY LAYOUT
--------------------------------------------------------------------

  .
  ├── main.c              CLI parsing, orchestration, timing
  ├── io.c / io.h         input parsing, output path building, writing
  ├── list.c / list.h     singly linked list of owned strings
  ├── mergesort.c / .h    multi-threaded merge sort (pthread)
  ├── logging.c / .h      leveled logging facility
  ├── Makefile            build + test targets (cc, -pthread)
  ├── sorter              (compiled binary, produced by make)
  └── tests/
      ├── generate_fixtures.zsh   generates all fixture cases
      ├── run_tests.zsh           automated correctness suite
      ├── run_perf_test.zsh       large-file performance test
      ├── check_leaks.zsh         memory leak check (macOS only)
      ├── data/random-words.txt   2643-word performance input
      └── fixtures/               (generated) per-case inputs,
                                  expected outputs and .meta files

--------------------------------------------------------------------
 ARCHITECTURE
--------------------------------------------------------------------

```mermaid
flowchart TD
    subgraph CLI["main.c - orchestration"]
        PA["parse_args()<br/>(--order asc|desc, input file)"]
        SL["sort_list()<br/>collect char* into O(n) arrays"]
        TIM["timing (CLOCK_MONOTONIC)"]
    end

    subgraph IO["io.c / io.h"]
        LO["load_strings()<br/>filter lines, build list"]
        BP["build_output_path()<br/>insert _ordered_asc|desc"]
        WO["write_output()<br/>one string per line"]
    end

    subgraph LIST["list.c / list.h"]
        AP["list_append()"]
        NN["list_new_node()<br/>(owned string copy)"]
        FL["free_list()"]
    end

    subgraph MS["mergesort.c / mergesort.h"]
        PMS["parallel_mergesort()"]
        M["msort() recursive<br/>split + stable merge"]
        W["msort_worker()<br/>(pthread entry)"]
    end

    LOG["logging.c / logging.h<br/>LOG_DEBUG / INFO / WARN / ERROR<br/>- stderr, timestamp + file:line<br/>- LOG_LEVEL env override"]

    IN[("input file")] --> LO
    LO -->|one Node per valid line| AP
    AP --> NN
    SL -->|items + tmp scratch| PMS
    PMS --> M
    M -->|depth < MSORT_MAX_DEPTH:<br/>pthread_create + pthread_join| W
    W --> M
    M -->|sorted pointers| SL
    SL --> WO
    BP --> WO
    WO --> OUT[("*_ordered_asc|desc.* file")]
    SL --> FL
    CLI -.-> LOG
    IO -.-> LOG
    LIST -.-> LOG
    MS -.-> LOG
```

--------------------------------------------------------------------
 TESTING FACILITIES
--------------------------------------------------------------------

```mermaid
flowchart TD
    MT["make test"] --> B["make build<br/>cc -Wall -Wextra -O2<br/>main.c logging.c list.c io.c mergesort.c -pthread"]
    MT --> T1

    subgraph T1["1. tests/run_tests.zsh - correctness suite"]
        F["generate_fixtures.zsh<br/>15 fixture cases, each with:<br/>input + expected output + .meta<br/>(expected = awk filter | LC_ALL=C sort [-r])"]
        SB["per-case isolated sandbox<br/>(tests/_sandbox/<case>/)"]
        CK["checks per case:<br/>- exit code<br/>- generated output file name<br/>- byte-exact content (diff)<br/>- WARN log expectation"]
        F --> SB --> CK
    end

    MT --> T2

    subgraph T2["2. tests/run_perf_test.zsh - performance"]
        PI["tests/data/random-words.txt<br/>(2643 lines)<br/>override: PERF_INPUT=/path/big.txt"]
        EX["expected output built independently:<br/>awk (sorter filter rules) | LC_ALL=C sort [-r]"]
        R1["asc run + desc run, each checked:<br/>- exit code 0<br/>- output file name<br/>- byte-exact diff<br/>- absence of WARN logs"]
        RC["recap: elapsed time parsed from the<br/>sorter's 'Elapsed time:' INFO log"]
        PI --> R1
        EX --> R1
        R1 --> RC
    end

    MT --> T3

    subgraph T3["3. tests/check_leaks.zsh - memory leaks (macOS only)"]
        LB["disposable binary 'sort_test_leaks'<br/>built with -O0 -g -pthread"]
        CS["ad-hoc codesign with<br/>com.apple.security.get-task-allow<br/>(entitlement required by 'leaks')"]
        LK["leaks -quiet -groupByType -conservative -atExit<br/>MallocStackLogging=1 MallocScribble=1"]
        LB --> CS --> LK
    end
```

--------------------------------------------------------------------
 STEP-BY-STEP INSTRUCTIONS
--------------------------------------------------------------------

Prerequisites (macOS):

  1. Xcode Command Line Tools installed:
         xcode-select -- install
     (provides cc/clang, make, leaks, codesign)
  2. zsh in PATH (ships with macOS; used by the test scripts).

====================================================================
 1. COMPILE
====================================================================

Step 1 - Option A: Makefile (recommended).

         make

   or equivalently:

         make build

   This runs:

         cc -Wall -Wextra -O2 -o sorter \
             main.c logging.c list.c io.c mergesort.c -pthread

   and prints "Build OK: sorter". The binary is created as ./sorter.

   Note: -pthread is REQUIRED at link time; the Makefile already
   adds it (LDLIBS := -pthread).

Step 1 - Option B: use gcc explicitly.

   On macOS, cc is Apple's Clang. If you installed a GNU compiler
   (e.g. Homebrew), it is usually in PATH as gcc-N or, after a
   symlink, as gcc. Two ways to use it:

         make CC=gcc            # let the Makefile drive it

   or compile manually:

         gcc -Wall -Wextra -O2 -o sorter \
             main.c logging.c list.c io.c mergesort.c -pthread

Step 2 - smoke test. Running the binary with no arguments prints
the usage line on stderr and exits 1, which proves the binary is
well-formed:

         ./sorter
         # -> Usage: ./sorter [--order asc|desc] <input_file>

====================================================================
 2. RUN
====================================================================

Step 1 - invoke the program:

         ./sorter [--order asc|desc] <input_file>

   Arguments:
     <input_file>   required, exactly one positional argument.
     --order asc    sort ascending (this is the default; the option
                    can be omitted).
     --order desc   sort descending.

   Error handling: unknown options, a missing value after --order,
   an invalid --order value, or more than one input file are fatal:
   an ERROR log + usage line on stderr, exit code 1.

Step 2 - examples:

         ./sorter notes.txt                  # ascending (default)
         ./sorter --order asc notes.txt      # ascending, explicit
         ./sorter --order desc notes.txt     # descending

Step 3 - read the result. The sorted copy is written next to the
input file; the input itself is untouched:

         ./sorter --order desc data.txt
         cat data_ordered_desc.txt

Step 4 - interpret the logs (all on stderr, default level INFO):

     2026-08-26 12:39:53 [INFO ] main.c:182 === Linked-List String Sorter (File I/O) ===
     2026-08-26 12:39:53 [INFO ] io.c:81    Reading strings from "data.txt".
     2026-08-26 12:39:53 [INFO ] io.c:123   Loaded 3 string(s) from "data.txt".
     2026-08-26 12:39:53 [INFO ] main.c:201 Sorted list (ascending):
     2026-08-26 12:39:53 [INFO ] io.c:155   Wrote 3 string(s) to "data_ordered_asc.txt".
     2026-08-26 12:39:53 [INFO ] main.c:215 Elapsed time: 0.000137000 s

   Exit codes: 0 = success (including "nothing to sort"),
   1 = failure (bad arguments, unreadable input, write error).

====================================================================
 3. DEBUG
====================================================================

Step 1 - turn on verbose logging (cheapest first step):

         LOG_LEVEL=DEBUG ./sorter notes.txt

   Levels, lowest to highest severity: DEBUG, INFO, WARN, ERROR
   (default: INFO). Each line carries the timestamp, level, and the
   file:line of the call site, so you can jump straight to the
   responsible code:

     2026-08-26 12:41:02 [DEBUG] io.c:105 Line 2 is empty; skipped.

   Useful: the merge sort also emits DEBUG lines when it degrades
   to sequential sorting (OOM or pthread_create failure), which
   helps diagnosing thread-creation problems.

Step 2 - rebuild with debug symbols and no optimization:

         cc -Wall -Wextra -O0 -g -o sorter_dbg \
             main.c logging.c list.c io.c mergesort.c -pthread

Step 3 - run under lldb (ships with the Command Line Tools):

         lldb ./sorter_dbg
         (lldb) b main
         (lldb) r --order desc notes.txt
         (lldb) n                # step over
         (lldb) s                # step into
         (lldb) p ascending
         (lldb) bt               # backtrace
         (lldb) thread list      # inspect the sort worker threads
         (lldb) b msort          # break inside the parallel sort
         (lldb) c                # continue

   Non-interactive one-shot backtrace on crash:

         lldb -b -o run -o bt ./sorter_dbg -- --order desc notes.txt

Step 4 - heap debugging environment variables (very useful on
macOS, which has no valgrind):

         MallocStackLogging=1 MallocScribble=1 ./sorter_dbg notes.txt

   MallocStackLogging gives you allocation/stack backtraces in
   crashes and in leaks reports; MallocScribble poisons freed
   memory so use-after-free bugs fail loudly.

Step 5 - check for memory leaks with the same tool the test suite
uses (see section 4, step 5):

         zsh tests/check_leaks.zsh

Step 6 - keep test sandboxes for post-mortem inspection:

         zsh tests/run_tests.zsh -k
         ls tests/_sandbox/       # per-case input, output and run.log

====================================================================
 4. RUN THE AUTOMATED TESTS AND THE MEMORY-LEAK VERIFICATION
====================================================================

Step 1 - the one-command way:

         make test

   This runs, in order:
     a. make build
     b. zsh tests/run_tests.zsh       (correctness suite)
     c. zsh tests/run_perf_test.zsh   (performance test)
     d. zsh tests/check_leaks.zsh     (memory leak check, macOS)

   make test exits non-zero as soon as any phase fails.

Step 2 - what the correctness suite (tests/run_tests.zsh) checks.

   For every fixture case under tests/fixtures/<case>/ (regenerated
   by generate_fixtures.zsh; each case has an input file, an
   expected output file and a .meta description) it:
     - copies the input into an isolated sandbox
       (tests/_sandbox/<case>/),
     - runs the sorter inside the sandbox,
     - verifies the exit code,
     - verifies the generated output file name (extension
       handling, dotfiles, extension-less files),
     - compares the output byte-for-byte against the expected file
       (diff),
     - verifies whether a WARN log was (not) expected.

   The 15 cases cover: basic asc, basic desc, default order
   (--order omitted), 300-char line (WARN+skip), 5000-char line
   (over the read buffer), empty lines, single element, empty file
   (no output at all), duplicates, extension-less input,
   multi-dot extension (data.tar.gz), CRLF endings, special
   characters (spaces, quotes, tabs), numeric strings (lexicographic
   order), and 50 seeded random strings.

Step 3 - what the performance test (tests/run_perf_test.zsh) checks.

   - sorts tests/data/random-words.txt (2643 real words) in an
     isolated sandbox, in both directions (asc and desc);
   - builds the expected output independently with plain text tools
     (awk implementing the sorter's filter rules | LC_ALL=C sort,
     -r for desc) and compares byte-for-byte;
   - checks the exit code, the output file name, and the absence of
     WARN logs for each run;
   - prints a recap with the elapsed time of both runs (parsed from
     the sorter's own "Elapsed time:" INFO log line).
   - on failure the sandbox is kept at tests/_perf_sandbox.
   - to stress it with a bigger file:
         PERF_INPUT=/path/to/bigger/file zsh tests/run_perf_test.zsh

Step 4 - run the individual pieces on demand.

         make fixtures              # (re)generate fixtures only
         zsh tests/generate_fixtures.zsh
         zsh tests/run_tests.zsh    # correctness suite
         zsh tests/run_tests.zsh -k # ... and keep sandboxes
         zsh tests/run_perf_test.zsh
         make clean                 # remove binary + generated artifacts

   All scripts are self-sufficient: if the ./sorter binary is
   missing they build it (same flags as the Makefile), and
   run_tests.zsh generates the fixtures if they are missing.

Step 5 - memory leak verification (macOS only).

         zsh tests/check_leaks.zsh

   What the script does:
     1. refuses to run on any OS other than macOS (Darwin);
     2. builds a disposable test binary (sort_test_leaks) in an
        isolated sandbox with -O0 -g -pthread - on this platform,
        leaks only reliably detects leaks in unoptimized builds;
     3. ad-hoc re-signs the binary with codesign using the
        com.apple.security.get-task-allow entitlement, which is
        required for leaks to attach to it;
     4. runs:
              leaks -quiet -groupByType -conservative -atExit -- \
                  ./sort_test_leaks --order asc basic.txt
        with MallocStackLogging=1 and MallocScribble=1;
        -atExit launches the process, reports leaks at exit, and
        makes leaks exit non-zero when leaks are found;
     5. removes all temporary artifacts on exit.

   Result: exit code 0 = "no leaks detected" (the script prints a
   "Memory leak check passed" banner); non-zero = leaks detected
   (the leaks report, with allocation backtraces, is printed first).

   Requirements: macOS + Xcode Command Line Tools (leaks and
   codesign in PATH) and existing fixtures (run make fixtures if
   they are missing).
