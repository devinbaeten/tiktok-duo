#include "../src/TCLAdaptiveCache.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned failures;
#define CHECK(condition) do { \
    if (!(condition)) { \
        fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #condition); \
        failures++; \
    } \
} while (0)

int main(void)
{
    uint64_t token = UINT64_MAX;
    double width = 450.0, aspect = 1.4;
    uint8_t inclusive = 0;
    TCLAdaptiveCachePointers pointers = {&token, &width, &aspect, &inclusive};

    TCLAdaptiveCacheSnapshot result = TCLAdaptiveCacheReadApply(pointers, -1, true);
    CHECK(result.available && result.initialized && !result.applied);
    CHECK(result.token == UINT64_MAX);
    CHECK(result.width == 450.0 && result.aspect == 1.4 && result.inclusive == 0);
    CHECK(width == 450.0 && aspect == 1.4 && inclusive == 0);

    // Invalid modes behave as a read-only snapshot, not a force-on request.
    const int invalid_modes[] = {-2, 2, 100};
    for (size_t i = 0; i < sizeof(invalid_modes) / sizeof(invalid_modes[0]); i++) {
        result = TCLAdaptiveCacheReadApply(pointers, invalid_modes[i], true);
        CHECK(result.initialized && !result.applied);
        CHECK(width == 450.0 && aspect == 1.4 && inclusive == 0);
    }

    for (int mode = 0; mode <= 1; mode++) {
        width = 450.0; aspect = 1.4; inclusive = 0;
        for (unsigned repeat = 0; repeat < 2; repeat++) {
            result = TCLAdaptiveCacheReadApply(pointers, mode, true);
            CHECK(result.available && result.initialized && result.applied);
            CHECK(result.width == (mode ? 1.0 : -1.0));
            CHECK(result.aspect == -1.0 && result.inclusive == 1);
            CHECK(width == result.width && aspect == result.aspect && inclusive == 1);
            CHECK(token == UINT64_MAX);
        }
    }

    // No reads/writes of cache fields are permitted before once completes.
    // Deliberately inaccessible field addresses prove that early return.
    TCLAdaptiveCachePointers unreadable = {
        &token, (double *)(uintptr_t)1, (double *)(uintptr_t)1,
        (uint8_t *)(uintptr_t)1
    };
    const uint64_t pending_tokens[] = {0, 1, 4, UINT64_MAX - 1};
    for (size_t i = 0; i < sizeof(pending_tokens) / sizeof(pending_tokens[0]); i++) {
        token = pending_tokens[i];
        width = 450.0; aspect = 1.4; inclusive = 0;
        result = TCLAdaptiveCacheReadApply(pointers, 1, true);
        CHECK(result.available && !result.initialized && !result.applied);
        CHECK(result.token == pending_tokens[i] && token == pending_tokens[i]);
        CHECK(width == 450.0 && aspect == 1.4 && inclusive == 0);
        result = TCLAdaptiveCacheReadApply(unreadable, 0, true);
        CHECK(result.available && !result.initialized && !result.applied);
    }

    // A later call observes completed initialization and applies the mode.
    __atomic_store_n(&token, UINT64_MAX, __ATOMIC_RELEASE);
    result = TCLAdaptiveCacheReadApply(pointers, 1, true);
    CHECK(result.initialized && result.applied && width == 1.0);

    TCLAdaptiveCachePointers unavailable = {
        (uint64_t *)(uintptr_t)1, (double *)(uintptr_t)1,
        (double *)(uintptr_t)1, (uint8_t *)(uintptr_t)1
    };
    result = TCLAdaptiveCacheReadApply(unavailable, 1, false);
    CHECK(!result.available && !result.initialized && !result.applied);

    for (unsigned missing = 0; missing < 4; missing++) {
        TCLAdaptiveCachePointers partial = pointers;
        if (missing == 0) partial.token = NULL;
        if (missing == 1) partial.width = NULL;
        if (missing == 2) partial.aspect = NULL;
        if (missing == 3) partial.inclusive = NULL;
        result = TCLAdaptiveCacheReadApply(partial, 0, true);
        CHECK(!result.available && !result.initialized && !result.applied);
        CHECK(token == UINT64_MAX && width == 1.0 && aspect == -1.0 && inclusive == 1);
    }

    printf("adaptive-cache: %s (%u failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? EXIT_FAILURE : EXIT_SUCCESS;
}
