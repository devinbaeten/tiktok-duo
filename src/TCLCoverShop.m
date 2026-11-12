#import "TCLCoverShop.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdatomic.h>

@interface TCLCoverShopState : NSObject
@end
@implementation TCLCoverShopState
@end

static BOOL TCLShopStarted;
static BOOL TCLShopEnabled;
static BOOL TCLShopInstalled;
static NSString *TCLShopState = @"Not started";
static id (*TCLShopOriginal)(id, SEL);
static Class TCLShopModelClass;
static _Atomic unsigned long TCLShopCalls;
static _Atomic unsigned long TCLShopRemoved;

static BOOL TCLShopObjectGetter(Method method) {
    if (!method || method_getNumberOfArguments(method) != 2) return NO;
    char type[32] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != '@' || type[1] != '\0') return NO;
    method_getArgumentType(method, 0, type, sizeof(type));
    if (type[0] != '@') return NO;
    method_getArgumentType(method, 1, type, sizeof(type));
    return type[0] == ':';
}

static id TCLShopTopTabList(id receiver, SEL selector) {
    // Preserve vendor behavior/side effects once, then filter a new collection.
    id original = TCLShopOriginal(receiver, selector);
    atomic_fetch_add_explicit(&TCLShopCalls, 1, memory_order_relaxed);
    if (![original isKindOfClass:[NSArray class]] || [original count] > 512) return original;
    NSMutableArray *filtered = nil;
    NSUInteger index = 0;
    for (id item in original) {
        BOOL remove = NO;
        if ([item isKindOfClass:TCLShopModelClass]) {
            SEL keySelector = NSSelectorFromString(@"topTabKey");
            Method getter = class_getInstanceMethod(object_getClass(item), keySelector);
            if (TCLShopObjectGetter(getter)) {
                id key = ((id (*)(id, SEL))objc_msgSend)(item, keySelector);
                remove = [key isKindOfClass:[NSString class]] && [key isEqualToString:@"mall"];
            }
        }
        if (remove) {
            if (!filtered) filtered = [[original subarrayWithRange:NSMakeRange(0, index)] mutableCopy];
            atomic_fetch_add_explicit(&TCLShopRemoved, 1, memory_order_relaxed);
        } else if (filtered) {
            [filtered addObject:item];
        }
        index++;
    }
    return filtered ? [filtered copy] : original;
}

void TCLCoverShopRefresh(void) {
    @synchronized ([TCLCoverShopState class]) {
        if (!TCLShopEnabled || TCLShopInstalled) return;
        Class config = NSClassFromString(@"TTKFeedTopTabControlConfig");
        Class model = NSClassFromString(@"TTKFeedTopTabItemInfo");
        if (!config || !model) {
            TCLShopState = @"Waiting for top-tab models";
            return;
        }
        SEL selector = NSSelectorFromString(@"topTabList");
        Method ownMethod = NULL;
        unsigned int count = 0;
        Method *methods = class_copyMethodList(config, &count);
        for (unsigned int i = 0; i < count; i++) {
            if (method_getName(methods[i]) == selector) { ownMethod = methods[i]; break; }
        }
        free(methods);
        if (!TCLShopObjectGetter(ownMethod) ||
            !TCLShopObjectGetter(class_getInstanceMethod(model, NSSelectorFromString(@"topTabKey")))) {
            TCLShopState = @"Skipped — top-tab model ABI mismatch";
            return;
        }
        TCLShopModelClass = model;
        TCLShopOriginal = (id (*)(id, SEL))method_getImplementation(ownMethod);
        method_setImplementation(ownMethod, (IMP)TCLShopTopTabList);
        TCLShopInstalled = YES;
        TCLShopState = @"Installed — exact Shop model filter";
    }
}

void TCLCoverShopStart(BOOL enabled) {
    @synchronized ([TCLCoverShopState class]) {
        if (TCLShopStarted) return;
        TCLShopStarted = YES;
        TCLShopEnabled = enabled;
        TCLShopState = enabled ? @"Waiting for top-tab models" : @"Off — unchanged";
    }
    TCLCoverShopRefresh();
}

NSDictionary<NSString *, NSString *> *TCLCoverShopStatus(void) {
    @synchronized ([TCLCoverShopState class]) {
        return @{
            @"shopState": TCLShopState,
            @"shopCalls": [NSString stringWithFormat:@"%lu", atomic_load_explicit(&TCLShopCalls, memory_order_relaxed)],
            @"shopRemoved": [NSString stringWithFormat:@"%lu", atomic_load_explicit(&TCLShopRemoved, memory_order_relaxed)]
        };
    }
}
