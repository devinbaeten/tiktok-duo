#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../src/TCLCoverShop.m"

static NSUInteger originalCalls;
static id sourceList;
static id OriginalList(id self, SEL cmd) { (void)self; (void)cmd; originalCalls++; return sourceList; }
static id ReadKey(id self, SEL cmd) { (void)cmd; return objc_getAssociatedObject(self, @selector(description)); }
static NSInteger InvalidKey(id self, SEL cmd) { (void)self; (void)cmd; return 7; }
static id Model(Class cls, id key) {
    id item = [cls new];
    objc_setAssociatedObject(item, @selector(description), key, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return item;
}
static void Check(BOOL result) { if (!result) abort(); }

int main(int argc, const char **argv) {
    @autoreleasepool {
        BOOL disabled = argc > 1 && !strcmp(argv[1], "disabled");
        BOOL badABI = argc > 1 && !strcmp(argv[1], "bad-abi");
        TCLCoverShopStart(!disabled);
        Check([TCLCoverShopStatus()[@"shopState"] isEqual:disabled ? @"Off — unchanged" : @"Waiting for top-tab models"]);
        Class model = objc_allocateClassPair([NSObject class], "TTKFeedTopTabItemInfo", 0);
        class_addMethod(model, @selector(topTabKey), (IMP)ReadKey, "@16@0:8");
        objc_registerClassPair(model);
        Class config = objc_allocateClassPair([NSObject class], "TTKFeedTopTabControlConfig", 0);
        class_addMethod(config, @selector(topTabList), (IMP)OriginalList, badABI ? "q16@0:8" : "@16@0:8");
        objc_registerClassPair(config);
        TCLCoverShopRefresh();
        Method getter = class_getInstanceMethod(config, @selector(topTabList));
        if (disabled || badABI) {
            Check(method_getImplementation(getter) == (IMP)OriginalList);
            Check([TCLCoverShopStatus()[@"shopCalls"] isEqual:@"0"]);
            puts(disabled ? "shop disabled: PASS" : "shop ABI guard: PASS");
            return 0;
        }
        IMP installed = method_getImplementation(getter);
        TCLCoverShopRefresh();
        Check(method_getImplementation(getter) == installed);
        id obj = [config new];
        id (*read)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
        SEL get = @selector(topTabList);
        id following = Model(model, @"following"), mall = Model(model, @"mall"), hot = Model(model, @"hot");
        Class unrelated = objc_allocateClassPair([NSObject class], "TCLUnrelatedShopInfo", 0);
        class_addMethod(unrelated, @selector(topTabKey), (IMP)ReadKey, "@16@0:8");
        objc_registerClassPair(unrelated);
        id unknown = Model(unrelated, @"mall");
        id uppercase = Model(model, @"Mall");
        id malformed = Model(model, @7);
        Class wrong = objc_allocateClassPair(model, "TCLWrongShopKeyABI", 0);
        class_addMethod(wrong, @selector(topTabKey), (IMP)InvalidKey, "q16@0:8");
        objc_registerClassPair(wrong);
        id wrongItem = Model(wrong, @"mall");
        NSMutableArray *input = [@[following,mall,hot,unknown,uppercase,malformed,wrongItem,mall] mutableCopy];
        sourceList = input;
        NSArray *actual = read(obj,get);
        Check([actual isEqual:@[following,hot,unknown,uppercase,malformed,wrongItem]]);
        Check(input.count == 8 && originalCalls == 1);
        Check([TCLCoverShopStatus()[@"shopRemoved"] isEqual:@"2"]);
        sourceList = @[following,hot];
        Check(read(obj,get) == sourceList && originalCalls == 2);
        sourceList = nil; Check(read(obj,get) == nil && originalCalls == 3);
        sourceList = @"not an array"; Check(read(obj,get) == sourceList && originalCalls == 4);
        sourceList = @[]; Check(read(obj,get) == sourceList && originalCalls == 5);
        sourceList = @[mall]; Check([read(obj,get) count] == 0 && originalCalls == 6);
        NSMutableArray *huge = [NSMutableArray new];
        for (NSUInteger i=0; i<513; i++) [huge addObject:mall];
        sourceList = huge; Check(read(obj,get) == sourceList && originalCalls == 7);
        Check([TCLCoverShopStatus()[@"shopCalls"] isEqual:@"7"]);
        // Bottom-tab settings and arbitrary collection classes are never hooked.
        Check(class_getInstanceMethod([NSObject class], get) == NULL);
        puts("shop model filtering: PASS");
    }
    return 0;
}
