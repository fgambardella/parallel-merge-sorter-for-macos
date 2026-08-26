# Makefile for bug condition exploration tests (fault-injection only)
#
# Each test includes production .c files directly (with fault injection
# macros) so we compile each test as a standalone binary.
#
# Tests 1a, 1b, 1d, 1e use compile-time macro interposition to inject
# failures into pthread_create, pthread_join, fflush/fclose, and malloc
# respectively.  These cannot be replicated by the fixture-based test
# suite and are kept here for that reason.
#
# Test 1c (NUL at EOF) was removed — the nul_at_eof fixture in
# tests/fixtures covers the same scenario end-to-end.

CC      ?= cc
CFLAGS  := -Wall -Wextra -O0 -g
LDLIBS  := -lpthread

TESTS := test_1a_pthread_create_fail \
         test_1b_pthread_join_fail \
         test_1d_fflush_fclose \
         test_1e_oom_list

.PHONY: all clean run

all: $(TESTS)

# -O0 to prevent optimizations that might interfere with fault injection
# -Wno-unused-function to suppress warnings from included-but-unused functions
test_1a_pthread_create_fail: test_1a_pthread_create_fail.c
	@$(CC) $(CFLAGS) -Wno-unused-function -o $@ $< $(LDLIBS)

test_1b_pthread_join_fail: test_1b_pthread_join_fail.c
	@$(CC) $(CFLAGS) -Wno-unused-function -o $@ $< $(LDLIBS)

test_1d_fflush_fclose: test_1d_fflush_fclose.c
	@$(CC) $(CFLAGS) -Wno-unused-function -o $@ $< $(LDLIBS)

test_1e_oom_list: test_1e_oom_list.c
	@$(CC) $(CFLAGS) -Wno-unused-function -o $@ $< $(LDLIBS)

run: all
	@pass=0; fail=0; \
	run_one() { \
		./$$1 >/dev/null 2>/dev/null; \
		rc=$$?; \
		if [ $$rc -eq 0 ]; then \
			pass=$$((pass + 1)); \
			printf '  \033[32mPASS\033[0m  %s\n' "$$2"; \
		else \
			fail=$$((fail + 1)); \
			printf '  \033[31mFAIL\033[0m  %s (exit %d)\n' "$$2" "$$rc"; \
		fi; \
	}; \
	run_one test_1a_pthread_create_fail "pthread_create failure"; \
	run_one test_1b_pthread_join_fail   "pthread_join failure"; \
	run_one test_1d_fflush_fclose       "fflush/fclose handling"; \
	run_one test_1e_oom_list            "malloc failure (list)"; \
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
