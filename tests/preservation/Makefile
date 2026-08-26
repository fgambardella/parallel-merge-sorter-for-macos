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
	@$(CC) $(CFLAGS) -Wno-unused-function -o $@ $< $(LDLIBS)

run: all
	@pass=0; fail=0; \
	./test_2e_sequential_fallback >/dev/null 2>/dev/null; \
	rc=$$?; \
	if [ $$rc -eq 0 ]; then \
		pass=$$((pass + 1)); \
		printf '  \033[32mPASS\033[0m  %s\n' "sequential fallback (OOM)"; \
	else \
		fail=$$((fail + 1)); \
		printf '  \033[31mFAIL\033[0m  %s (exit %d)\n' "sequential fallback (OOM)" "$$rc"; \
	fi; \
	echo ""; \
	total=$$((pass + fail)); \
	if [ $$fail -eq 0 ]; then \
		printf '  \033[32m%d passed\033[0m\033[2m, %d assertions\033[0m\n' "$$pass" "$$total"; \
	else \
		printf '  \033[32m%d passed\033[0m, \033[31m%d failed\033[0m\033[2m, %d assertions\033[0m\n' "$$pass" "$$fail" "$$total"; \
	fi; \
	[ $$fail -eq 0 ]

clean:
	rm -f $(TESTS)
	rm -rf *.dSYM
