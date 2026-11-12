#include "../src/TCLGlassBridge.h"
#include <pthread.h>
#include <stdio.h>

static const uint64_t global0 = UINT64_C(0xd00000000000001f);
static const uint64_t global1 = UINT64_C(0x80000001264378a0);
static const uint64_t fold0 = UINT64_C(0xd00000000000002b);
static const uint64_t fold1 = UINT64_C(0x80000001264378c0);
static unsigned originalCalls;
static void *lastDictionary;
static uint64_t last0, last1;
static bool originalResult;

static bool original(void *dictionary, uint64_t key0, uint64_t key1) {
    ++originalCalls;
    lastDictionary = dictionary;
    last0 = key0;
    last1 = key1;
    return originalResult;
}

static void initialize(TCLGlassBridge *bridge, int mode) {
    assert(TCLGlassBridgeInit(bridge, original, global0, global1, fold0, fold1, mode));
    originalCalls = 0;
    originalResult = false;
}

static void expectForward(TCLGlassBridge *bridge, void *dictionary,
                          uint64_t key0, uint64_t key1, bool result) {
    originalResult = result;
    unsigned before = originalCalls;
    assert(TCLGlassBridgeRead(bridge, dictionary, key0, key1) == result);
    assert(originalCalls == before + 1);
    assert(lastDictionary == dictionary && last0 == key0 && last1 == key1);
}

static void testDefault(void) {
    TCLGlassBridge bridge;
    initialize(&bridge, -1);
    int dictionary;
    expectForward(&bridge, &dictionary, global0, global1, true);
    expectForward(&bridge, &dictionary, fold0, fold1, false);
    expectForward(&bridge, NULL, 0, UINT64_MAX, true);
    assert(atomic_load(&bridge.matchedCalls[0]) == 1);
    assert(atomic_load(&bridge.matchedCalls[1]) == 1);
    assert(atomic_load(&bridge.overrideCalls[0]) == 0);
    assert(atomic_load(&bridge.overrideCalls[1]) == 0);
}

static void testOverrides(int mode) {
    TCLGlassBridge bridge;
    initialize(&bridge, mode);
    int dictionary;
    originalResult = mode == 0; /* Forced result must ignore original. */
    assert(TCLGlassBridgeRead(&bridge, NULL, global0, global1) == (mode == 1));
    assert(TCLGlassBridgeRead(&bridge, &dictionary, fold0, fold1) == (mode == 1));
    assert(originalCalls == 0);
    /* A changed length, pointer/slide, tag, or cross-paired words must not match. */
    expectForward(&bridge, &dictionary, global0 + 1, global1, true);
    expectForward(&bridge, &dictionary, global0, global1 + 1, false);
    expectForward(&bridge, &dictionary, global0, global1 + UINT64_C(0x100000000), true);
    expectForward(&bridge, &dictionary, global0, global1 ^ (UINT64_C(1) << 63), false);
    expectForward(&bridge, &dictionary, fold0, global1, true);
    expectForward(&bridge, &dictionary, global0, fold1, false);
    expectForward(&bridge, NULL, 0, 0, true);
    for (unsigned i = 0; i < 2; ++i) {
        assert(atomic_load(&bridge.matchedCalls[i]) == 1);
        assert(atomic_load(&bridge.overrideCalls[i]) == 1);
    }
}

static void testInvalidMode(void) {
    const int invalidModes[] = {-2, 2, 42};
    for (unsigned i = 0; i < sizeof invalidModes / sizeof invalidModes[0]; ++i) {
        TCLGlassBridge bridge;
        initialize(&bridge, invalidModes[i]);
        assert(bridge.activeMode == -1);
        expectForward(&bridge, NULL, global0, global1, false);
        expectForward(&bridge, NULL, fold0, fold1, true);
        assert(atomic_load(&bridge.overrideCalls[0]) == 0);
        assert(atomic_load(&bridge.overrideCalls[1]) == 0);
    }
}

static void *concurrentRead(void *context) {
    TCLGlassBridge *bridge = context;
    for (unsigned i = 0; i < 10000; ++i) {
        assert(TCLGlassBridgeRead(bridge, NULL, global0, global1));
        assert(TCLGlassBridgeRead(bridge, NULL, fold0, fold1));
    }
    return NULL;
}

static void testConcurrentCounters(void) {
    TCLGlassBridge bridge;
    initialize(&bridge, 1);
    pthread_t threads[4];
    for (unsigned i = 0; i < 4; ++i)
        assert(pthread_create(&threads[i], NULL, concurrentRead, &bridge) == 0);
    for (unsigned i = 0; i < 4; ++i)
        assert(pthread_join(threads[i], NULL) == 0);
    assert(originalCalls == 0);
    for (unsigned i = 0; i < 2; ++i) {
        assert(atomic_load(&bridge.matchedCalls[i]) == 40000);
        assert(atomic_load(&bridge.overrideCalls[i]) == 40000);
    }
}

int main(void) {
    TCLGlassBridge bridge;
    assert(!TCLGlassBridgeInit(NULL, original, global0, global1, fold0, fold1, -1));
    assert(!TCLGlassBridgeInit(&bridge, NULL, global0, global1, fold0, fold1, -1));
    testDefault();
    testOverrides(0);
    testOverrides(1);
    testInvalidMode();
    testConcurrentCounters();
    puts("glass bridge: PASS");
    return 0;
}
