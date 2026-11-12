#import <Foundation/Foundation.h>
#import <sys/mman.h>
#import "../src/TCLCoverNative.m"

static int failures;
static unsigned verticalOriginalCalls;
static bool verticalOriginalValue;
static bool mockVerticalOriginal(void) { verticalOriginalCalls++; return verticalOriginalValue; }
#define CHECK(c) do { if (!(c)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c); failures++; } } while(0)
static void addSegment(struct mach_header_64 *header, const char *name, int prot,
                       const char **names, const uint64_t *addresses, const uint64_t *sizes, unsigned count) {
    struct segment_command_64 *seg=(void *)((uint8_t *)(header+1)+header->sizeofcmds);
    seg->cmd=LC_SEGMENT_64;seg->cmdsize=sizeof(*seg)+count*sizeof(struct section_64);
    strncpy(seg->segname,name,16);seg->initprot=prot;seg->nsects=count;
    struct section_64 *sections=(void *)(seg+1);
    for(unsigned i=0;i<count;i++) {
        strncpy(sections[i].sectname,names[i],16);strncpy(sections[i].segname,name,16);
        sections[i].addr=addresses[i];sections[i].size=sizes[i];
    }
    header->ncmds++;header->sizeofcmds+=seg->cmdsize;
}
int main(int argc,const char **argv) { @autoreleasepool {
    NSString *scenario=argc>1 ? @(argv[1]) : @"on";
    size_t length=0x35000000;
    uint8_t *base=mmap(NULL,length,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    if(base==MAP_FAILED)return 2;
    struct mach_header_64 *header=(void *)base;header->magic=MH_MAGIC_64;
    const char *textNames[]={"__text","__cstring"};
    uint64_t textAddresses[]={0xe000000,0x26430000},textSizes[]={0xdbc0000,0x1e0000};
    addSegment(header,"__TEXT",1,textNames,textAddresses,textSizes,2);
    const char *dataNames[]={"__data","__objc_clsrefs","__bss"};
    uint64_t dataAddresses[]={0x32ff4000,0x343e1000,0x344ccf40},dataSizes[]={0xe30005,0x3000,0x9c4598};
    addSegment(header,"__DATA",[scenario isEqual:@"readonly"]?1:3,dataNames,dataAddresses,dataSizes,3);
    static const uint8_t prefix[]={0xff,0x83,0x01,0xd1,0xf6,0x57,0x03,0xa9,0xf4,0x4f,0x04,0xa9,0xfd,0x7b,0x05,0xa9,0xfd,0x43,0x01,0x91,0x08,0x08,0x40,0xf9,0x68,0x03,0x00,0xb4,0xf3,0x03,0x02,0xaa};
    static const uint32_t thunk[]={0xb00c41f1,0xf9465631,0xd61f0220};
    memcpy(base+0x1bba63cc,prefix,sizeof(prefix));memcpy(base+0x1bba6498,thunk,sizeof(thunk));
    strcpy((char *)base+0x264378c0,"ttk_tabbar_liquid_glass_enabled");
    strcpy((char *)base+0x264378e0,"ttk_tabbar_fold_screen_liquid_glass_enabled");
    static const uint8_t verticalPrefix[]={0x41,0xb6,0x12,0x90,0x21,0xe0,0x36,0x91,0x40,0xb6,0x12,0x90,0x00,0xc0,0x36,0x91,0x63,0x00,0x00,0x10,0x1f,0x20,0x03,0xd5,0xef,0x51,0x63,0x14,0x48,0xb6,0x12,0x90};
    static const uint32_t verticalThunk[]={0xb01319b1,0xf9413a31,0xd61f0220};
    memcpy(base+0xe0ad7cc,verticalPrefix,sizeof(verticalPrefix));
    memcpy(base+0xe0adc04,verticalThunk,sizeof(verticalThunk));
    strcpy((char *)base+0x2660d5a0,"tt_tab_bar_vertical_layout_enable");
    uintptr_t *verticalSlot=(void *)(base+0x343e2270);*verticalSlot=(uintptr_t)base+0xe0ad7cc;
    if([scenario isEqual:@"vertical-changed-slot"])*verticalSlot+=4;
    if([scenario isEqual:@"vertical-bad-prefix"])base[0xe0ad7cc]^=1;
    uintptr_t originalVerticalSlot=*verticalSlot;
    uintptr_t *slot=(void *)(base+0x343e3ca8);*slot=(uintptr_t)base+0x1bba63cc;
    uint64_t *adaptiveToken=(void *)(base+0x34e74b18),*glassToken=(void *)(base+0x33776ba8);
    double *width=(void *)(base+0x33d9b838),*aspect=(void *)(base+0x33d9b840);
    uint8_t *inclusive=base+0x33d9b848,*support=base+0x33776bb8;
    NSLock *lock=[NSLock new];*(uintptr_t *)(base+0x33776bb0)=(uintptr_t)(__bridge void *)lock;
    *adaptiveToken=*glassToken=UINT64_MAX;*width=450;*aspect=1.5;*inclusive=0;*support=0;
    BOOL pending=[scenario isEqual:@"pending"],busy=[scenario isEqual:@"busy"];
    if(pending)*adaptiveToken=*glassToken=0;
    if(busy)[lock lock];
    if([scenario isEqual:@"changed-slot"])*slot+=4;
    if([scenario isEqual:@"bad-prefix"])base[0x1bba63cc]^=1;
    int mode=[scenario isEqual:@"default"]?-1:([scenario isEqual:@"off"]?0:1);
    uintptr_t originalSlot=*slot;
    TCLCoverNativeStart(header,(intptr_t)base,mode,mode,mode);
    if(mode<0 || [scenario isEqual:@"readonly"]) {
        CHECK(*slot==originalSlot);CHECK(*width==450 && *aspect==1.5 && *inclusive==0);CHECK(*support==0);
    } else {
        if(pending) { CHECK(*width==450 && *support==0);*adaptiveToken=*glassToken=UINT64_MAX;TCLCoverNativeRefresh(); }
        CHECK(*width==(mode?1:-1));CHECK(*aspect==-1 && *inclusive==1);
        if([scenario isEqual:@"changed-slot"] || [scenario isEqual:@"bad-prefix"]) {
            CHECK(!TCLNReaderInstalled);CHECK(*slot==originalSlot);CHECK(*support==0);
        } else {
            CHECK(TCLNReaderInstalled && *slot!=(uintptr_t)base+0x1bba63cc);
            if(busy) { CHECK(*support==0);[lock unlock];TCLCoverNativeRefresh(); }
            CHECK(*support==2);
            TCLGlassReader reader=(TCLGlassReader)*slot;
            CHECK(reader(NULL,UINT64_C(0xd00000000000001f),UINT64_C(0x8000000000000000)|((uintptr_t)base+0x264378a0))==(bool)mode);
            CHECK(reader(NULL,UINT64_C(0xd00000000000002b),UINT64_C(0x8000000000000000)|((uintptr_t)base+0x264378c0))==(bool)mode);
            NSDictionary *status=TCLCoverNativeStatus();
            CHECK([status[@"glassGlobalCalls"] isEqual:@"1"] && [status[@"glassFoldCalls"] isEqual:@"1"]);
            *support=0;TCLCoverNativeRefresh();CHECK(*support==0); // invalidates once, never forces eligibility true
        }
    }
    if(mode<0 || [scenario isEqual:@"readonly"] || [scenario isEqual:@"vertical-changed-slot"] || [scenario isEqual:@"vertical-bad-prefix"]) {
        CHECK(*verticalSlot==originalVerticalSlot);
        CHECK(atomic_load(&TCLNVerticalCalls)==0 && atomic_load(&TCLNVerticalLastOriginal)==-1);
    } else {
        CHECK(*verticalSlot==(uintptr_t)TCLNReadVertical);
        // Replace only the fixture's original target: retained ARM64 bytes are
        // never executed. Verify actual installed wrapper calls the original
        // exactly once while recording its value and applying the launch mode.
        TCLNVerticalOriginal=mockVerticalOriginal;
        bool (*reader)(void)=(void *)*verticalSlot;
        verticalOriginalValue=false;CHECK(reader()==(bool)mode);
        verticalOriginalValue=true;CHECK(reader()==(bool)mode);
        CHECK(verticalOriginalCalls==2 && atomic_load(&TCLNVerticalCalls)==2);
        CHECK(atomic_load(&TCLNVerticalLastOriginal)==1);
        CHECK([TCLCoverNativeStatus()[@"verticalOriginal"] isEqual:@"On"]);
        CHECK([TCLCoverNativeStatus()[@"verticalNativeCalls"] isEqual:@"2"]);
    }
    CHECK(*adaptiveToken==UINT64_MAX && *glassToken==UINT64_MAX);
    CHECK(TCLCoverNativeStatus()!=nil);
    munmap(base,length);
    printf("native %s: %s (%d failures)\n",scenario.UTF8String,failures?"FAIL":"PASS",failures);
    return failures?1:0;
} }
