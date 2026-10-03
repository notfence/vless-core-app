#ifndef VC_TEST_CHECK_H
#define VC_TEST_CHECK_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static unsigned vc_test_checks;
#define CHECK(name, ...) do { \
    const char *vc_forced = getenv("VC_TEST_FAIL_SCENARIO"); \
    if (!(__VA_ARGS__) || (vc_forced && strcmp(vc_forced, name) == 0)) { \
        fprintf(stderr, "FAIL %s (%s:%d)\n", name, __FILE__, __LINE__); exit(1); \
    } \
    vc_test_checks++; \
} while (0)
#define FINISH(group) printf("PASS %s: %u checks\n", group, vc_test_checks)
#endif
