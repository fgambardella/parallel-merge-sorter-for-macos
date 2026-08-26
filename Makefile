# Makefile - Linked-List String Sorter (File I/O)
#
# Targets:
#   make / make build  - compile the sorter
#   make test          - build, generate fixtures, run the test suite
#   make fixtures      - (re)generate test fixtures only
#   make clean         - remove the binary and generated test artifacts

CC      ?= cc
CFLAGS  ?= -Wall -Wextra -O2
LDLIBS  := -pthread

BINARY  := sorter
SRC     := main.c logging.c list.c io.c mergesort.c
HDR     := io.h list.h logging.h mergesort.h
OBJ     := $(SRC:.c=.o)
DEP     := $(SRC:.c=.d)
TESTS   := tests

.PHONY: all build test fixtures clean

all: build

build: $(BINARY)

# M-07 fix: depend on headers via generated .d files, rebuild objects
# individually so a header change triggers recompilation.
%.o: %.c
	$(CC) $(CFLAGS) -MMD -MP -c -o $@ $<

$(BINARY): $(OBJ)
	$(CC) $(CFLAGS) -o $(BINARY) $(OBJ) $(LDLIBS)
	@echo "Build OK: $(BINARY)"

-include $(DEP)

# M-07 fix: always regenerate fixtures before tests.
# Run the whole automated test suite (builds first if needed),
# then the fault-injection tests, then the large-file performance
# test, then the memory leak check.
test: build fixtures
	@printf '\n\033[1m Fixture tests\033[0m\n'
	@zsh $(TESTS)/run_tests.zsh
	@printf '\n\033[1m Fault injection :: exploration\033[0m\n'
	@$(MAKE) --no-print-directory -C $(TESTS)/exploration run
	@printf '\n\033[1m Fault injection :: preservation\033[0m\n'
	@$(MAKE) --no-print-directory -C $(TESTS)/preservation run
	@printf '\n\033[1m Performance\033[0m\n'
	@zsh $(TESTS)/run_perf_test.zsh
	@printf '\n\033[1m Sanitizers + leak check\033[0m\n'
	@zsh $(TESTS)/check_leaks.zsh
	@printf '\n\033[32;1m All test suites passed.\033[0m\n\n'

# (Re)generate all test fixtures and their expected outputs.
fixtures:
	@zsh $(TESTS)/generate_fixtures.zsh > /dev/null

clean:
	rm -f $(BINARY) $(OBJ) $(DEP)
	rm -rf $(TESTS)/fixtures $(TESTS)/_sandbox $(TESTS)/_perf_sandbox $(TESTS)/_leak_sandbox
	@$(MAKE) -C $(TESTS)/exploration clean
	@$(MAKE) -C $(TESTS)/preservation clean
	@echo "Cleaned."
