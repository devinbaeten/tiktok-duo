#ifndef TCL_GLASS_BRIDGE_H
#define TCL_GLASS_BRIDGE_H

#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdatomic.h>

/* The analyzed reader borrows all three arguments and returns bool in x0.
 * No Swift object or String ownership operation belongs in this dispatcher. */
typedef bool (*TCLGlassReader)(void *dictionary, uint64_t key0, uint64_t key1);

typedef struct {
    TCLGlassReader original;
    uint64_t keyWords[2][2]; /* Global glass, then fold-screen glass. */
    int activeMode;         /* -1: Default, 0: Off, 1: On. */
    atomic_uint_fast64_t matchedCalls[2];
    atomic_uint_fast64_t overrideCalls[2];
} TCLGlassBridge;

/* Initialize once before publishing the hook. The original reader, key words,
 * and mode remain immutable while calls can occur; only counters are atomic. */
static inline bool TCLGlassBridgeInit(TCLGlassBridge *bridge,
                                    TCLGlassReader original,
                                    uint64_t global0, uint64_t global1,
                                    uint64_t fold0, uint64_t fold1,
                                    int activeMode) {
    if (!bridge || !original) return false;
    bridge->original = original;
    bridge->keyWords[0][0] = global0;
    bridge->keyWords[0][1] = global1;
    bridge->keyWords[1][0] = fold0;
    bridge->keyWords[1][1] = fold1;
    bridge->activeMode = (activeMode == 0 || activeMode == 1) ? activeMode : -1;
    for (unsigned i = 0; i < 2; ++i) {
        atomic_init(&bridge->matchedCalls[i], 0);
        atomic_init(&bridge->overrideCalls[i], 0);
    }
    return true;
}

/* Requires successful initialization. Default and unrelated keys call the
 * original exactly once with the original arguments. Explicit overrides do
 * not evaluate the original or dereference borrowed arguments. */
static inline bool TCLGlassBridgeRead(TCLGlassBridge *bridge, void *dictionary,
                                    uint64_t key0, uint64_t key1) {
    assert(bridge && bridge->original);
    for (unsigned i = 0; i < 2; ++i) {
        if (key0 != bridge->keyWords[i][0] || key1 != bridge->keyWords[i][1])
            continue;
        atomic_fetch_add_explicit(&bridge->matchedCalls[i], 1, memory_order_relaxed);
        if (bridge->activeMode == 0 || bridge->activeMode == 1) {
            atomic_fetch_add_explicit(&bridge->overrideCalls[i], 1, memory_order_relaxed);
            return bridge->activeMode == 1;
        }
        break;
    }
    return bridge->original(dictionary, key0, key1);
}

#endif
