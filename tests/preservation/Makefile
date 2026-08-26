# Makefile for preservation property tests (fault-injection only)
#
# Only test_2e_sequential_fallback is kept here — it uses compile-time
# malloc interposition to fail MSortJob-sized allocations, exercising
# the sequential OOM fallback path.  This cannot be replicated by
# the fixture-based test suite.
#
# Tests 2a-2d were removed — their coverage is provided by:
#   2a (sort correctness)    -> fixtures + perf test (29 cases + 2643-line file)
#   2b (full pipeline)       -> fixtures (29 cases x asc/desc)
#   2c (CRLF handling)       -> crlf + embedded_cr fixtures
#   2d (permissions)         -> integration test I-3 (M-01)

CC      ?= cc
CFLAGS  := -Wall -Wextra -O0 -g
LDLIBS  := -lpthread

TESTS := test_2e_sequential_fallback

.PHONY: all clean run

all: $(TESTS)

test_2e_sequential_fallback: test_2e_sequential_fallback.c
	$(CC) $(CFLAGS) -Wno-unused-function -o $@ $< $(LDLIBS)

run: all
	@echo "============================================"
	@echo "  Preservation tests (fault-injection)"
	@echo "============================================"
	@pass=0; fail=0; \
	for t in $(TESTS); do \
		echo "  --- $$t ---"; \
		./$$t 2>/dev/null; \
		rc=$$?; \
		if [ $$rc -eq 0 ]; then \
			pass=$$((pass + 1)); \
			echo "      PASS"; \
		else \
			fail=$$((fail + 1)); \
			echo "      FAIL (exit $$rc)"; \
		fi; \
	done; \
	echo "  Preservation: $$pass passed, $$fail failed"; \
	[ $$fail -eq 0 ]

clean:
	rm -f $(TESTS)
	rm -rf *.dSYM
