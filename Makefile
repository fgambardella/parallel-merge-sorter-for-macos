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
# then the large-file performance test, then the memory leak check.
test: build fixtures
	@echo "------------------------------"
	@echo "| Running test suite ...     |"
	@echo "------------------------------"
	@zsh $(TESTS)/run_tests.zsh
	@echo "-----------------------------------"
	@echo "| Running performance test ...    |"
	@echo "-----------------------------------"
	@zsh $(TESTS)/run_perf_test.zsh
	@echo "---------------------------------"
	@echo "| Running memory leak check ... |"
	@echo "---------------------------------"
	@zsh $(TESTS)/check_leaks.zsh

# (Re)generate all test fixtures and their expected outputs.
fixtures:
	zsh $(TESTS)/generate_fixtures.zsh

clean:
	rm -f $(BINARY) $(OBJ) $(DEP)
	rm -rf $(TESTS)/fixtures $(TESTS)/_sandbox $(TESTS)/_perf_sandbox $(TESTS)/_leak_sandbox
	@echo "Cleaned."
