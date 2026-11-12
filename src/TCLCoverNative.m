#import "TCLCoverNative.h"
#import "TCLAdaptiveCache.h"
#import "TCLGlassBridge.h"
#import <string.h>

static const struct mach_header_64 *TCLNHeader;
static intptr_t TCLNSlide;
static int TCLNAdaptive = -1, TCLNGlass = -1, TCLNVertical = -1;
static bool (*TCLNVerticalOriginal)(void);
static atomic_uint_fast64_t TCLNVerticalCalls;
static atomic_int TCLNVerticalLastOriginal = -1;
static NSString *TCLNVerticalStatus = @"Unavailable";
static TCLAdaptiveCachePointers TCLNCache;
static TCLAdaptiveCacheSnapshot TCLNSnapshot;
static TCLGlassBridge TCLNBridge;
static BOOL TCLNCacheValid, TCLNReaderInstalled, TCLNResetDone;
static uint64_t *TCLNGlassToken;
static uintptr_t *TCLNGlassLock;
static uint8_t *TCLNGlassSupport;
static NSString *TCLNReaderStatus = @"Unavailable";
static NSString *TCLNResetStatus = @"Not requested";
static NSString *TCLNBefore = @"Not observed";

// Resolve only exact sections in the verified loaded image. Never make code
// writable or change page protections; all writes are to existing __DATA.
static void *TCLNAddress(uint64_t address, size_t size, const char *segmentName,
                        const char *sectionName, BOOL writable) {
    if (!TCLNHeader || TCLNHeader->magic != MH_MAGIC_64 || !size) return NULL;
    const uint8_t *p = (const void *)(TCLNHeader + 1);
    const uint8_t *end = p + TCLNHeader->sizeofcmds;
    for (uint32_t i = 0; i < TCLNHeader->ncmds && p + sizeof(struct load_command) <= end; i++) {
        const struct load_command *cmd = (const void *)p;
        if (cmd->cmdsize < sizeof(*cmd) || cmd->cmdsize > (size_t)(end-p)) return NULL;
        if (cmd->cmd == LC_SEGMENT_64 && cmd->cmdsize >= sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg = (const void *)p;
            if (!strncmp(seg->segname, segmentName, 16) && (!writable || (seg->initprot & 2))) {
                if (seg->nsects > (cmd->cmdsize - sizeof(*seg))/sizeof(struct section_64)) return NULL;
                const struct section_64 *sections = (const void *)(seg+1);
                for (uint32_t j=0;j<seg->nsects;j++) {
                    const struct section_64 *s=&sections[j];
                    if (strncmp(s->sectname, sectionName, 16)) continue;
                    if (address >= s->addr && size <= s->size && address-s->addr <= s->size-size)
                        return (void *)((uintptr_t)TCLNSlide + address);
                }
            }
        }
        p += cmd->cmdsize;
    }
    return NULL;
}
static bool TCLNReadGlass(void *dictionary, uint64_t first, uint64_t second) {
    return TCLGlassBridgeRead(&TCLNBridge, dictionary, first, second);
}
static BOOL TCLNBytes(uint64_t address, const void *expected, size_t length, const char *section) {
    void *p=TCLNAddress(address,length,"__TEXT",section,NO);
    return p && !memcmp(p,expected,length);
}
// The verified native accessor consumes no incoming arguments/context and
// returns a bool. Preserve its normal lazy initialization and record only real
// calls. Default never replaces the function pointer.
static bool TCLNReadVertical(void) {
    bool original=TCLNVerticalOriginal();
    atomic_fetch_add_explicit(&TCLNVerticalCalls,1,memory_order_relaxed);
    atomic_store_explicit(&TCLNVerticalLastOriginal,original?1:0,memory_order_relaxed);
    return TCLNVertical==1;
}
static void TCLNInstallVertical(void) {
    if (TCLNVertical!=0 && TCLNVertical!=1) { TCLNVerticalStatus=@"Default — untouched";return; }
    static const uint8_t prefix[32]={0x41,0xb6,0x12,0x90,0x21,0xe0,0x36,0x91,0x40,0xb6,0x12,0x90,0x00,0xc0,0x36,0x91,0x63,0x00,0x00,0x10,0x1f,0x20,0x03,0xd5,0xef,0x51,0x63,0x14,0x48,0xb6,0x12,0x90};
    static const uint32_t thunk[3]={0xb01319b1,0xf9413a31,0xd61f0220};
    static const char key[]="tt_tab_bar_vertical_layout_enable";
    uintptr_t *slot=TCLNAddress(0x343e2270,8,"__DATA","__objc_clsrefs",YES);
    if (!slot || !TCLNBytes(0xe0ad7cc,prefix,sizeof(prefix),"__text") ||
        !TCLNBytes(0xe0adc04,thunk,sizeof(thunk),"__text") ||
        !TCLNBytes(0x2660d5a0,key,sizeof(key),"__cstring")) {
        TCLNVerticalStatus=@"Skipped — identity mismatch";return;
    }
    uintptr_t expected=(uintptr_t)TCLNSlide+0xe0ad7cc;
    TCLNVerticalOriginal=(bool (*)(void))expected;
    if (!__atomic_compare_exchange_n(slot,&expected,(uintptr_t)TCLNReadVertical,false,__ATOMIC_RELEASE,__ATOMIC_RELAXED)) {
        TCLNVerticalStatus=@"Skipped — reader already changed";return;
    }
    TCLNVerticalStatus=@"Installed — vertical layout flag";
}
static void TCLNInstallGlass(void) {
    if (TCLNGlass < 0) { TCLNReaderStatus=@"Default — untouched"; return; }
    static const uint8_t readerPrefix[32]={0xff,0x83,0x01,0xd1,0xf6,0x57,0x03,0xa9,0xf4,0x4f,0x04,0xa9,0xfd,0x7b,0x05,0xa9,0xfd,0x43,0x01,0x91,0x08,0x08,0x40,0xf9,0x68,0x03,0x00,0xb4,0xf3,0x03,0x02,0xaa};
    static const uint32_t thunk[3]={0xb00c41f1,0xf9465631,0xd61f0220};
    static const char globalKey[]="ttk_tabbar_liquid_glass_enabled";
    static const char foldKey[]="ttk_tabbar_fold_screen_liquid_glass_enabled";
    uintptr_t *slot=TCLNAddress(0x343e3ca8,8,"__DATA","__objc_clsrefs",YES);
    if (!slot || !TCLNBytes(0x1bba63cc,readerPrefix,sizeof(readerPrefix),"__text") ||
        !TCLNBytes(0x1bba6498,thunk,sizeof(thunk),"__text") ||
        !TCLNBytes(0x264378c0,globalKey,sizeof(globalKey),"__cstring") ||
        !TCLNBytes(0x264378e0,foldKey,sizeof(foldKey),"__cstring")) {
        TCLNReaderStatus=@"Skipped — identity mismatch"; return;
    }
    uintptr_t expected=(uintptr_t)TCLNSlide+0x1bba63cc;
    TCLGlassBridgeInit(&TCLNBridge,(TCLGlassReader)expected,
        UINT64_C(0xd00000000000001f),UINT64_C(0x8000000000000000)|((uintptr_t)TCLNSlide+0x264378a0),
        UINT64_C(0xd00000000000002b),UINT64_C(0x8000000000000000)|((uintptr_t)TCLNSlide+0x264378c0),TCLNGlass);
    // Compare before replacing. Leave another tweak's interposition untouched.
    if (!__atomic_compare_exchange_n(slot,&expected,(uintptr_t)TCLNReadGlass,false,__ATOMIC_RELEASE,__ATOMIC_RELAXED)) {
        TCLNReaderStatus=@"Skipped — reader already changed"; return;
    }
    TCLNReaderInstalled=YES;
    TCLNReaderStatus=@"Installed — two exact keys";
    TCLNResetStatus=@"Waiting for support cache";
}
void TCLCoverNativeRefresh(void) {
    if (!TCLNHeader) return;
    TCLAdaptiveCacheSnapshot before=TCLAdaptiveCacheReadApply(TCLNCache,-1,TCLNCacheValid);
    if (before.initialized && [TCLNBefore isEqualToString:@"Not observed"])
        TCLNBefore=[NSString stringWithFormat:@"width %.3g; aspect %.3g",before.width,before.aspect];
    TCLNSnapshot=TCLAdaptiveCacheReadApply(TCLNCache,TCLNAdaptive,TCLNCacheValid);
    if (!TCLNReaderInstalled || TCLNResetDone) return;
    if (!TCLNGlassToken || !TCLNGlassLock || !TCLNGlassSupport) { TCLNResetStatus=@"Skipped — cache mapping mismatch"; return; }
    if (__atomic_load_n(TCLNGlassToken,__ATOMIC_ACQUIRE) != UINT64_MAX) return;
    NSLock *lock=(__bridge NSLock *)(void *)__atomic_load_n(TCLNGlassLock,__ATOMIC_ACQUIRE);
    if (![lock isKindOfClass:NSLock.class]) { TCLNResetStatus=@"Skipped — lock mismatch"; return; }
    if (![lock tryLock]) { TCLNResetStatus=@"Waiting for cache lock"; return; }
    uint8_t value=*TCLNGlassSupport;
    if (value <= 2) {
        // 2 means not yet evaluated. Recompute using TikTok's original OS/device
        // checks with only the two experiment key results overridden.
        *TCLNGlassSupport=2;
        TCLNResetDone=YES;
        TCLNResetStatus=value==2 ? @"Not yet evaluated" : @"Invalidated — eligibility preserved";
    } else TCLNResetStatus=@"Skipped — unexpected cache value";
    [lock unlock];
}
void TCLCoverNativeStart(const struct mach_header_64 *header, intptr_t slide, int adaptiveMode, int glassMode, int verticalMode) {
    if (TCLNHeader || !header) return;
    TCLNHeader=header;TCLNSlide=slide;TCLNAdaptive=adaptiveMode;TCLNGlass=glassMode;TCLNVertical=verticalMode;
    TCLNCache=(TCLAdaptiveCachePointers){
        TCLNAddress(0x34e74b18,8,"__DATA","__bss",YES),
        TCLNAddress(0x33d9b838,8,"__DATA","__data",YES),
        TCLNAddress(0x33d9b840,8,"__DATA","__data",YES),
        TCLNAddress(0x33d9b848,1,"__DATA","__data",YES)};
    TCLNCacheValid=TCLNCache.token && TCLNCache.width && TCLNCache.aspect && TCLNCache.inclusive;
    TCLNGlassToken=TCLNAddress(0x33776ba8,8,"__DATA","__data",YES);
    TCLNGlassLock=TCLNAddress(0x33776bb0,8,"__DATA","__data",YES);
    TCLNGlassSupport=TCLNAddress(0x33776bb8,1,"__DATA","__data",YES);
    TCLNInstallGlass();TCLNInstallVertical();TCLCoverNativeRefresh();
}
NSDictionary<NSString *, NSString *> *TCLCoverNativeStatus(void) {
    NSString *cache=!TCLNSnapshot.available ? @"Unavailable" : (!TCLNSnapshot.initialized ? @"Not initialized" :
        (TCLNSnapshot.applied ? @"Override applied" : @"Default — unchanged"));
    NSString *effective=TCLNSnapshot.initialized ? [NSString stringWithFormat:@"width %.3g; aspect %.3g; inclusive %u",TCLNSnapshot.width,TCLNSnapshot.aspect,TCLNSnapshot.inclusive] : @"Not observed";
    NSString *support=@"Not initialized";
    if (TCLNGlassToken && TCLNGlassLock && TCLNGlassSupport && __atomic_load_n(TCLNGlassToken,__ATOMIC_ACQUIRE)==UINT64_MAX) {
        NSLock *lock=(__bridge NSLock *)(void *)__atomic_load_n(TCLNGlassLock,__ATOMIC_ACQUIRE);
        if ([lock isKindOfClass:NSLock.class] && [lock tryLock]) {
            uint8_t value=*TCLNGlassSupport;
            support=value==2 ? @"Not yet evaluated" : (value==1 ? @"Allowed by eligibility checks" : (value==0 ? @"Rejected by eligibility checks" : @"Unexpected cache value"));
            [lock unlock];
        }
    }
    int verticalOriginal=atomic_load(&TCLNVerticalLastOriginal);
    NSString *lastVertical=verticalOriginal<0 ? @"Not observed" : (verticalOriginal ? @"On" : @"Off");
    return @{@"verticalReader":TCLNVerticalStatus,
        @"verticalNativeCalls":[NSString stringWithFormat:@"%llu",(unsigned long long)atomic_load(&TCLNVerticalCalls)],
        @"verticalOriginal":lastVertical,
        @"adaptiveCache":cache,@"thresholds":effective,@"thresholdsBefore":TCLNBefore,
        @"glassReader":TCLNReaderStatus,@"glassReset":TCLNResetStatus,@"glassSupport":support,
        @"glassGlobalCalls":[NSString stringWithFormat:@"%llu",(unsigned long long)atomic_load(&TCLNBridge.matchedCalls[0])],
        @"glassFoldCalls":[NSString stringWithFormat:@"%llu",(unsigned long long)atomic_load(&TCLNBridge.matchedCalls[1])]};
}
