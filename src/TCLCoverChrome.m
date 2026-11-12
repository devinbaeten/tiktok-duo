#import "TCLCoverChrome.h"
#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>
#import <stdlib.h>
#ifndef TCLCHROME_TEST
#import <UIKit/UIKit.h>
#if __IPHONE_OS_VERSION_MAX_ALLOWED < 270100
// Allow builds with older SDK headers; calls remain gated on iOS 27.1.
@interface UIViewController (TCLVerticalBarSDK)
- (void)setNeedsUpdateOfVerticalBarConfiguration;
@end
@interface UITraitCollection (TCLVerticalBarSDK)
- (NSInteger)verticalBarEdge;
@end
#endif
#endif

static BOOL TCLChromeStarted, TCLChromeEnabled;
static NSLock *TCLChromeLock;
static __weak UIViewController *TCLChromeTarget;
static __weak UIWindow *TCLChromeWindow;
static NSMutableSet<NSValue *> *TCLChromeInstalledClasses;
static NSString *TCLChromeRoute = @"Not started";
static NSString *TCLChromeRoot = @"Not observed";
static NSString *TCLChromeRuntimeRoot = @"Not observed";
static NSString *TCLChromeRootImage = @"Not observed";
static NSString *TCLChromeOwnership = @"Not observed";
static NSString *TCLChromeOriginalBehavior = @"Not observed";
static NSString *TCLChromeOriginalChild = @"Not observed";
static atomic_uint_fast64_t TCLChromeBehaviorCalls, TCLChromeChildCalls;

static BOOL TCLChromeAvailable(void) {
#ifdef TCLCHROME_TEST
    return YES;
#else
    if (@available(iOS 27.1, *)) return YES;
    return NO;
#endif
}

// Only the foreground app window containing TikTok's actual tab controller is
// eligible. Containment is bounded and excludes independently presented screens.
static BOOL TCLChromeContainsTab(UIViewController *root) {
    Class tabClass=NSClassFromString(@"TTKTabBarController");
    if (!tabClass || !root) return NO;
    NSMutableArray<UIViewController *> *pending=[NSMutableArray arrayWithObject:root];
    NSHashTable *visited=[NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (NSUInteger index=0; index<pending.count && index<128; index++) {
        UIViewController *controller=pending[index];
        if ([visited containsObject:controller]) continue;
        [visited addObject:controller];
        if ([controller isKindOfClass:tabClass]) return YES;
        for (UIViewController *child in controller.childViewControllers) {
            if (pending.count>=128) break;
            if ([child isKindOfClass:UIViewController.class] && ![visited containsObject:child])
                [pending addObject:child];
        }
    }
    return NO;
}

static BOOL TCLChromeOwnsClass(Class cls) {
    const char *image=class_getImageName(cls);
    TCLChromeRootImage=image ? [NSString stringWithUTF8String:image] : @"No runtime image attribution";
    // Never modify UIKit's actual base classes. An app/runtime subclass is
    // distinct even when it inherits all of its implementations from UIKit.
    if (cls==UIViewController.class || cls==UINavigationController.class || cls==UITabBarController.class) {
        TCLChromeOwnership=@"System base class";
        return NO;
    }
    // Engine startup already verified TikTok's exact Core UUID/build. This
    // specific root is identified by its verified ancestry in that binary.
    // Runtime-created subclasses need not have class_getImageName attribution;
    // verify ancestry by Class identity, never a class-name prefix.
    Class knownRoot=NSClassFromString(@"AWERootNavigationController");
    for (Class cursor=cls; knownRoot && cursor; cursor=class_getSuperclass(cursor)) {
        if (cursor==knownRoot) {
            TCLChromeOwnership=@"Verified TikTok root ancestry";
            return YES;
        }
    }
    if (!image) { TCLChromeOwnership=@"Unknown runtime class";return NO; }
    NSString *path=[[NSString stringWithUTF8String:image] stringByResolvingSymlinksInPath];
    NSString *bundlePath=[NSBundle.mainBundle.bundlePath stringByResolvingSymlinksInPath];
    BOOL owned=[path isEqualToString:[NSBundle.mainBundle.executablePath stringByResolvingSymlinksInPath]] ||
        (bundlePath.length && [path hasPrefix:[bundlePath stringByAppendingString:@"/"]]);
    TCLChromeOwnership=owned ? @"App image" : @"Image outside app bundle";
    return owned;
}

static BOOL TCLChromeSignature(Method method, const char *result) {
    if (!method || method_getNumberOfArguments(method)!=2) return NO;
    char *r=method_copyReturnType(method), *a=method_copyArgumentType(method,0), *s=method_copyArgumentType(method,1);
    BOOL valid=r && a && s && !strcmp(r,result) && !strcmp(a,"@") && !strcmp(s,":");
    free(r);free(a);free(s);
    return valid;
}

static BOOL TCLChromeIsTarget(id receiver) {
    if (!NSThread.isMainThread) return NO;
    [TCLChromeLock lock];
    UIViewController *target=TCLChromeTarget;
    UIWindow *window=TCLChromeWindow;
    BOOL matches=TCLChromeEnabled && target==receiver;
    [TCLChromeLock unlock];
    return matches && window && window.rootViewController==target;
}

static Method TCLChromeOwnMethod(Class cls, SEL selector) {
    unsigned count=0;
    Method *methods=class_copyMethodList(cls,&count), result=NULL;
    for (unsigned i=0;i<count;i++) if (method_getName(methods[i])==selector) { result=methods[i];break; }
    free(methods);
    return result;
}

static BOOL TCLChromeReplace(Class cls, SEL selector, IMP expected, IMP replacement, const char *types) {
    // Adding an own method preserves an inherited implementation on its owner.
    if (class_addMethod(cls,selector,replacement,types)) return YES;
    Method own=TCLChromeOwnMethod(cls,selector);
    if (!own || method_getImplementation(own)!=expected) return NO;
    method_setImplementation(own,replacement);
    return YES;
}

static BOOL TCLChromeInstall(Class cls) {
    NSValue *key=[NSValue valueWithPointer:(__bridge const void *)cls];
    if (!TCLChromeOwnsClass(cls)) {
        TCLChromeRoute=[TCLChromeOwnership isEqualToString:@"System base class"] ?
            @"Skipped — system root class" : @"Skipped — unverified root ownership";
        return NO;
    }
    if ([TCLChromeInstalledClasses containsObject:key]) return YES;
    SEL behavior=NSSelectorFromString(@"preferredVerticalBarBehavior");
    SEL child=NSSelectorFromString(@"childViewControllerForPreferredVerticalBarBehavior");
    Method behaviorMethod=class_getInstanceMethod(cls,behavior), childMethod=class_getInstanceMethod(cls,child);
    // Validate both before altering either method.
    if (!TCLChromeSignature(behaviorMethod,"q") || !TCLChromeSignature(childMethod,"@")) {
        TCLChromeRoute=@"Skipped — root method ABI mismatch";return NO;
    }
    IMP originalBehavior=method_getImplementation(behaviorMethod), originalChild=method_getImplementation(childMethod);
    IMP behaviorHook=imp_implementationWithBlock(^NSInteger(id receiver) {
        NSInteger original=((NSInteger(*)(id,SEL))originalBehavior)(receiver,behavior);
        if (object_getClass(receiver)!=cls || !TCLChromeIsTarget(receiver)) return original;
        atomic_fetch_add_explicit(&TCLChromeBehaviorCalls,1,memory_order_relaxed);
        [TCLChromeLock lock];
        TCLChromeOriginalBehavior=[NSString stringWithFormat:@"%ld",(long)original];
        [TCLChromeLock unlock];
        return (NSInteger)1; // UIVerticalBarBehaviorDisabled.
    });
    IMP childHook=imp_implementationWithBlock(^id(id receiver) {
        id original=((id(*)(id,SEL))originalChild)(receiver,child);
        if (object_getClass(receiver)!=cls || !TCLChromeIsTarget(receiver)) return original;
        atomic_fetch_add_explicit(&TCLChromeChildCalls,1,memory_order_relaxed);
        [TCLChromeLock lock];
        TCLChromeOriginalChild=original ? NSStringFromClass([original class]) : @"nil";
        [TCLChromeLock unlock];
        return (id)nil; // Use this root's own preference, not a child's.
    });
    if (!behaviorHook || !childHook) {
        if (behaviorHook) imp_removeBlock(behaviorHook);
        if (childHook) imp_removeBlock(childHook);
        TCLChromeRoute=@"Skipped — hook allocation failed";return NO;
    }
    if (!TCLChromeReplace(cls,behavior,originalBehavior,behaviorHook,method_getTypeEncoding(behaviorMethod))) {
        imp_removeBlock(behaviorHook);imp_removeBlock(childHook);
        TCLChromeRoute=@"Skipped — root method changed";return NO;
    }
    if (!TCLChromeReplace(cls,child,originalChild,childHook,method_getTypeEncoding(childMethod))) {
        Method installed=TCLChromeOwnMethod(cls,behavior);
        if (installed && method_getImplementation(installed)==behaviorHook)
            method_setImplementation(installed,originalBehavior);
        // Keep the behavior block alive in case a concurrent call entered it.
        imp_removeBlock(childHook);
        TCLChromeRoute=@"Skipped — root forwarding changed";return NO;
    }
    [TCLChromeInstalledClasses addObject:key];
    return YES;
}

void TCLCoverChromeStart(BOOL enabled) {
    if (TCLChromeStarted) return;
    TCLChromeStarted=YES;TCLChromeEnabled=enabled;
    TCLChromeLock=[NSLock new];TCLChromeInstalledClasses=[NSMutableSet new];
    TCLChromeRoute=enabled ? @"Waiting for TikTok window" : @"Default / Off — untouched";
}

void TCLCoverChromeRefresh(void) {
    if (!TCLChromeStarted || !TCLChromeEnabled || !NSThread.isMainThread) return;
    if (!TCLChromeAvailable()) { TCLChromeRoute=@"Unavailable — requires iOS 27.1";return; }
    UIWindow *candidate=nil;
    // Prefer active scenes, then allow the same window during resignation.
    for (unsigned pass=0;pass<2 && !candidate;pass++) {
        UISceneActivationState state=pass==0 ? UISceneActivationStateForegroundActive : UISceneActivationStateForegroundInactive;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=state) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window.isKeyWindow || window.hidden || !TCLChromeContainsTab(window.rootViewController)) continue;
                candidate=window;break;
            }
            if (candidate) break;
        }
    }
    if (!candidate) return; // Retry an incomplete launch graph on next refresh.
    UIViewController *root=candidate.rootViewController;
    TCLChromeRoot=NSStringFromClass([root class]);
    TCLChromeRuntimeRoot=NSStringFromClass(object_getClass(root));
    if (!TCLChromeInstall(object_getClass(root))) {
        [TCLChromeLock lock];TCLChromeTarget=nil;TCLChromeWindow=candidate;[TCLChromeLock unlock];
        return;
    }
    [TCLChromeLock lock];
    BOOL newlyAttached=TCLChromeTarget!=root;
    TCLChromeTarget=root;TCLChromeWindow=candidate;
    [TCLChromeLock unlock];
    TCLChromeRoute=@"Attached — requesting horizontal bars";
    if (newlyAttached) {
#ifdef TCLCHROME_TEST
        [root setNeedsUpdateOfVerticalBarConfiguration];
#else
        if (@available(iOS 27.1, *)) [root setNeedsUpdateOfVerticalBarConfiguration];
#endif
    }
}

NSDictionary<NSString *, NSString *> *TCLCoverChromeStatus(void) {
    // Never invoke either preference getter here: counts reflect UIKit requests.
    [TCLChromeLock lock];
    UIWindow *window=TCLChromeWindow;
    NSString *behavior=TCLChromeOriginalBehavior, *child=TCLChromeOriginalChild;
    [TCLChromeLock unlock];
    NSString *insets=@"Not observed", *edge=@"Not observed";
    if (window && NSThread.isMainThread) {
        UIEdgeInsets area=window.safeAreaInsets;
        insets=[NSString stringWithFormat:@"top %.1f; left %.1f; bottom %.1f; right %.1f",area.top,area.left,area.bottom,area.right];
#ifdef TCLCHROME_TEST
        edge=[NSString stringWithFormat:@"%ld",(long)window.traitCollection.verticalBarEdge];
#else
        if (@available(iOS 27.1, *)) edge=[NSString stringWithFormat:@"%ld",(long)window.traitCollection.verticalBarEdge];
#endif
    }
    return @{@"chromeRoute":TCLChromeRoute,@"chromeRoot":TCLChromeRoot,
        @"chromeRuntimeRoot":TCLChromeRuntimeRoot,@"chromeRootImage":TCLChromeRootImage,
        @"chromeOwnership":TCLChromeOwnership,
        @"chromeOriginalBehavior":behavior,@"chromeOriginalChild":child,
        @"chromeBehaviorCalls":[NSString stringWithFormat:@"%llu",(unsigned long long)atomic_load(&TCLChromeBehaviorCalls)],
        @"chromeChildCalls":[NSString stringWithFormat:@"%llu",(unsigned long long)atomic_load(&TCLChromeChildCalls)],
        @"chromeWindowInsets":insets,@"chromeTraitEdge":edge};
}
