#ifndef TCL_ADAPTIVE_CACHE_H
#define TCL_ADAPTIVE_CACHE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    volatile uint64_t *token;
    volatile double *width;
    volatile double *aspect;
    volatile uint8_t *inclusive;
} TCLAdaptiveCachePointers;

typedef struct {
    bool available;
    bool initialized;
    bool applied;
    uint64_t token;
    double width;
    double aspect;
    uint8_t inclusive;
} TCLAdaptiveCacheSnapshot;

// The caller validates binary identity, mapped writable sections, sizes, and
// natural alignment before passing validated=true. Modes are a fixed startup
// snapshot: -1/default, 0/off, 1/on. Serialize calls on the main thread.
// Never force initialization or alter TikTok's dispatch_once token.
static inline TCLAdaptiveCacheSnapshot TCLAdaptiveCacheReadApply(
    TCLAdaptiveCachePointers pointers, int mode, bool validated)
{
    TCLAdaptiveCacheSnapshot result = {0};
    if (!validated || !pointers.token || !pointers.width || !pointers.aspect ||
        !pointers.inclusive) return result;

    result.available = true;
    result.token = __atomic_load_n(pointers.token, __ATOMIC_ACQUIRE);
    if (result.token != UINT64_MAX) return result;
    result.initialized = true;

    // The completed-once acquire must precede every cache-field access.
    // The cache's initializer will never write again after completion.
    if (mode == 0 || mode == 1) {
        double width = mode == 1 ? 1.0 : -1.0;
        double aspect = -1.0;
        __atomic_store(pointers.aspect, &aspect, __ATOMIC_RELAXED);
        __atomic_store(pointers.width, &width, __ATOMIC_RELAXED);
        __atomic_store_n(pointers.inclusive, (uint8_t)1, __ATOMIC_RELAXED);
        result.applied = true;
    }

    __atomic_load(pointers.width, &result.width, __ATOMIC_RELAXED);
    __atomic_load(pointers.aspect, &result.aspect, __ATOMIC_RELAXED);
    result.inclusive = __atomic_load_n(pointers.inclusive, __ATOMIC_RELAXED);
    return result;
}

#endif
