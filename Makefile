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
TESTS   := tests

.PHONY: all build test fixtures clean

all: build

build: $(BINARY)

$(BINARY): $(SRC)
	$(CC) $(CFLAGS) -o $(BINARY) $(SRC) $(LDLIBS)
	@echo "Build OK: $(BINARY)"

# Run the whole automated test suite (builds first if needed),
# then the large-file performance test, then the memory leak check
# with leaks (macOS).
test: build
	@echo "------------------------------"
	@echo "| Running test suite ...     |"
	@echo "------------------------------"
	@zsh $(TESTS)/run_tests.zsh
	@echo "-----------------------------------"
	@echo "| Running performance test ... |"
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
	rm -f $(BINARY)
	rm -rf $(TESTS)/fixtures $(TESTS)/_sandbox $(TESTS)/_perf_sandbox
	@echo "Cleaned."
