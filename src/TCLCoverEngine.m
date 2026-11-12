#import "TCLCoverSettings.h"
#import <objc/runtime.h>
#import <stdatomic.h>
#import <string.h>
#import <math.h>
#ifndef TCLC_TEST
#import <UIKit/UIKit.h>
#import "TCLCoverNative.h"
#import "TCLCoverChrome.h"
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#endif

// Only 47.7.0 build 477034, MusicallyCore UUID 81156393-0F58-38C4-8723-0B15CF11EC16.
// No server assignments or vendor preferences are modified.
static NSUserDefaults *TCLPrefs;
enum { TCLExperimentCount = 5, TCLExpectedHookCount = 9 };
static atomic_int TCLActive[TCLExperimentCount];
static atomic_uint_fast64_t TCLHits[TCLExperimentCount];
static atomic_int TCLLastOriginal[TCLExperimentCount];
static BOOL TCLCompatible;
static atomic_uint_fast64_t TCLBottomCalls, TCLBottomApplied;
static atomic_long TCLBottomPlacement = -1;
static _Atomic(double) TCLBottomOriginal, TCLBottomEffective;
// 0 not observed, 1 mode inactive, 2 placement unavailable, 3 horizontal,
// 4 vertical safe area retained, 5 safe area unavailable. Snapshots never evaluate layout getters.
static atomic_int TCLBottomState;
static NSString *TCLRecovery = @"None";
static NSMutableArray<NSString *> *TCLHookStatus;
static NSString *const TCLKeys[] = {@"adaptive_layout", @"glass_tabs", @"crop_layout", @"vertical_tabs", @"full_width_chrome"};
static NSString *const TCLLayoutKey = @"TCLCover.layout";
static NSString *TCLActiveLayout = @"Legacy";
// One Settings value atomically selects all three dependent switches.
// Adaptive layout and cropping remain independent advanced preferences.
static NSInteger TCLLayoutSelection(void) {
    id value = [TCLPrefs objectForKey:TCLLayoutKey];
    if (![value isKindOfClass:NSNumber.class]) return -1;
    for (NSInteger i = 0; i < 3; i++) if ([value isEqualToNumber:@(i)]) return i;
    return -1;
}
static NSString *TCLLayoutTitle(NSInteger value) {
    return value >= 0 && value < 3 ? @[@"Classic", @"Native", @"Fullscreen"][value] : @"Legacy";
}
static void TCLMigrateLayout(void) {
    if (TCLLayoutSelection() >= 0) return;
    NSInteger selected = 0;
    if (![TCLPrefs objectForKey:TCLLayoutKey]) {
        if ([[TCLPrefs objectForKey:@"TCLCover.mode.full_width_chrome"] isEqual:@1]) selected = 2;
        else if ([[TCLPrefs objectForKey:@"TCLCover.mode.glass_tabs"] isEqual:@1] &&
                 [[TCLPrefs objectForKey:@"TCLCover.mode.vertical_tabs"] isEqual:@1]) selected = 1;
    }
    [TCLPrefs setInteger:selected forKey:TCLLayoutKey];
    [TCLPrefs synchronize];
}
static NSInteger TCLIndex(NSString *key) {
    if (![key isKindOfClass:NSString.class]) return -1;
    for (NSInteger i=0;i<TCLExperimentCount;i++) if ([key isEqualToString:TCLKeys[i]]) return i;
    return -1;
}
static NSString *TCLPreference(NSInteger i) { return [@"TCLCover.mode." stringByAppendingString:TCLKeys[i]]; }
NSInteger TCLCoverModeValue(NSString *key) {
    NSInteger i=TCLIndex(key); if (i<0) return -1;
    NSInteger layout = TCLLayoutSelection();
    if (layout >= 0) {
        if (i == 1 || i == 3) return layout == 1 ? 1 : 0;
        if (i == 4) return layout == 2 ? 1 : 0;
    }
    id value=[TCLPrefs objectForKey:TCLPreference(i)];
    if (![value isKindOfClass:NSNumber.class]) return -1;
    NSInteger mode=[value integerValue];
    return mode==0 || mode==1 ? mode : -1;
}
void TCLCoverSetModeValue(NSString *key, NSInteger value) {
    NSInteger i=TCLIndex(key); if(i<0 || value < -1 || value > 1) return;
    if(value==-1) [TCLPrefs removeObjectForKey:TCLPreference(i)];
    else [TCLPrefs setInteger:value forKey:TCLPreference(i)];
    [TCLPrefs synchronize];
}
void TCLCoverResetDefaults(void) {
    if ([TCLPrefs objectForKey:TCLLayoutKey]) [TCLPrefs setInteger:0 forKey:TCLLayoutKey];
    for(NSInteger i=0;i<TCLExperimentCount;i++) [TCLPrefs removeObjectForKey:TCLPreference(i)];
    [TCLPrefs synchronize];
}
NSArray<NSDictionary<NSString *, NSString *> *> *TCLCoverExperimentEntries(void) {
    return @[
        @{@"key":TCLKeys[0], @"title":@"Adaptive Fold Layout", @"detail":@"On removes TikTok’s 450-point width requirement for its adaptive fold layout. Off disables that layout. Applies across folded and unfolded windows. Restart after changing."},
        @{@"key":TCLKeys[1], @"title":@"Floating Glass Tabs", @"detail":@"Overrides the tab-bar glass experiment and its fold-screen branch. TikTok’s device and layout eligibility checks still apply. Try with Adaptive Fold Layout on. Restart after changing."},
        @{@"key":TCLKeys[2], @"title":@"Fold Video Crop Experiment", @"detail":@"Overrides TikTok’s foldable fake-landscape crop experiment. It may crop video edges in supported layouts; visible crop behavior is unverified. Restart after changing."},
        @{@"key":TCLKeys[3], @"title":@"Right-side Tab Rail", @"detail":@"Enables TikTok’s vertical-tab experiment. Try with Floating Glass Tabs on. OS and window eligibility still apply. Restart after changing."},
        @{@"key":TCLKeys[4], @"title":@"Full-width Layout", @"detail":@"On requests horizontal system bars and full content width. It takes precedence over the right-side rail across display configurations. Default and Off leave this route unchanged. Restart after changing."}
    ];
}
static void TCLLoadModes(void) {
    TCLActiveLayout = TCLCompatible ? TCLLayoutTitle(TCLLayoutSelection()) : @"Disabled — unsupported binary";
    for(NSInteger i=0;i<TCLExperimentCount;i++) atomic_store(&TCLActive[i], TCLCompatible ? (int)TCLCoverModeValue(TCLKeys[i]) : -1);
}
// An interrupted launch is not evidence of a crash. Preserve explicit choices,
// including settings saved after an early exit, when retiring the old marker.
static void TCLPrepareLaunchPreferences(void) {
    [TCLPrefs synchronize];
    TCLRecovery = @"Saved layout preserved";
    if ([TCLPrefs objectForKey:@"TCLCover.pendingLaunch"]) {
        [TCLPrefs removeObjectForKey:@"TCLCover.pendingLaunch"];
        TCLRecovery = @"Incomplete-launch marker cleared — saved layout preserved";
    }
    if (TCLCompatible) TCLMigrateLayout();
    TCLLoadModes();
    [TCLPrefs synchronize];
}
static BOOL TCLEffective(NSInteger i, BOOL original) {
    atomic_fetch_add(&TCLHits[i],1); atomic_store(&TCLLastOriginal[i],original?1:0);
    int mode=atomic_load(&TCLActive[i]);return mode<0 ? original : mode==1;
}
static BOOL TCLSignature(Method m, char result) {
    if(!m || method_getNumberOfArguments(m)!=2) return NO;
    char *r=method_copyReturnType(m), *a=method_copyArgumentType(m,0), *s=method_copyArgumentType(m,1);
    BOOL good=r && r[0]==result && r[1]==0 && a && a[0]=='@' && s && s[0]==':';
    free(r);free(a);free(s);return good;
}
static void TCLAddHook(NSString *name, NSString *selectorName, BOOL classMethod, NSInteger index, BOOL dictionary) {
    Class cls=NSClassFromString(name);Class target=classMethod?object_getClass(cls):cls;
    SEL sel=NSSelectorFromString(selectorName);Method m=class_getInstanceMethod(target,sel);
    NSString *label=[NSString stringWithFormat:@"%c[%@ %@]",classMethod?'+':'-',name,selectorName];
    if(!TCLSignature(m,dictionary?'@':'B')) { [TCLHookStatus addObject:[label stringByAppendingString:@": unavailable / ABI mismatch"]];return; }
    IMP original=method_getImplementation(m),replacement;
    if(dictionary) {
        id (^block)(id)=^id(id receiver) {
            id value=((id(*)(id,SEL))original)(receiver,sel);
            atomic_fetch_add(&TCLHits[index],1);
            int mode=atomic_load(&TCLActive[index]);
            if(mode<0) return value;
            // Do not coerce unexpected result types into a config dictionary.
            if(![value isKindOfClass:NSDictionary.class]) return value;
            NSMutableDictionary *config=[value mutableCopy];
            config[@"min_width_threshold"]=mode==1?@1.0:@(-1.0);
            config[@"min_aspect_ratio_threshold"]=@(-1.0);
            config[@"threshold_inclusive_enabled"]=@YES;
            return [config copy];
        };
        replacement=imp_implementationWithBlock(block);
    } else {
        BOOL (^block)(id)=^BOOL(id receiver) {
            BOOL value=((BOOL(*)(id,SEL))original)(receiver,sel);
            return TCLEffective(index,value);
        };
        replacement=imp_implementationWithBlock(block);
    }
    if(!class_addMethod(target,sel,replacement,method_getTypeEncoding(m))) method_setImplementation(class_getInstanceMethod(target,sel),replacement);
    [TCLHookStatus addObject:[label stringByAppendingString:@": installed"]];
}
// Proven 47.7.0 path: the offset getter resolves TikTokTabBarModuleService;
// its -tabBarController at 0x1bc219c0 forwards to
// [[TTKTabBarManager sharedInstance] tabBarController]. Placement is q16@0:8.
static id TCLObjectGetter(id receiver, NSString *name) {
    if (!receiver) return nil;
    SEL selector = NSSelectorFromString(name);
    Method method = class_getInstanceMethod(object_getClass(receiver), selector);
    if (!TCLSignature(method, '@')) return nil;
    return ((id (*)(id, SEL))method_getImplementation(method))(receiver, selector);
}
static NSInteger TCLCurrentTabPlacement(id *resolvedController) {
    *resolvedController = nil;
    // The source is UIKit state. Preserve the app result for any unexpected
    // background-thread caller rather than reading its controller off-main.
    if (![NSThread isMainThread]) return -1;
    @try {
        id manager = TCLObjectGetter(NSClassFromString(@"TTKTabBarManager"), @"sharedInstance");
        id controller = TCLObjectGetter(manager, @"tabBarController");
        if (!controller) return -1;
        SEL selector = NSSelectorFromString(@"tabBarPlacement");
        Method method = class_getInstanceMethod(object_getClass(controller), selector);
        if (!TCLSignature(method, 'q')) return -1;
        NSInteger placement = ((NSInteger (*)(id, SEL))method_getImplementation(method))(controller, selector);
        *resolvedController = controller;
        return placement;
    } @catch (__unused NSException *exception) {
        return -1;
    }
}
// Read the loaded tab container's own safe area on every offset calculation.
// Do not substitute a global/key window or manufacture a fixed device inset.
#ifdef TCLC_TEST
extern double TCLCoverTestSafeArea(id controller);
#endif
static BOOL TCLCurrentBottomSafeArea(id controller, double *bottom) {
#ifdef TCLC_TEST
    double value = TCLCoverTestSafeArea(controller);
#else
    if (![controller isKindOfClass:UIViewController.class]) return NO;
    UIView *view = ((UIViewController *)controller).viewIfLoaded;
    if (!view || !view.window || view.hidden || view.window.hidden) return NO;
    double value = view.safeAreaInsets.bottom;
#endif
    if (!isfinite(value) || value < 0) return NO;
    *bottom = value;
    return YES;
}
static void TCLInstallBottomSpacingHook(void) {
    Class target = NSClassFromString(@"AWEFeedModuleService");
    SEL selector = NSSelectorFromString(@"iPhoneDuoHomeInterationAreaOffset");
    Method method = class_getInstanceMethod(target, selector);
    NSString *label = @"-[AWEFeedModuleService iPhoneDuoHomeInterationAreaOffset]";
    if (!TCLSignature(method, 'd')) {
        [TCLHookStatus addObject:[label stringByAppendingString:@": unavailable / ABI mismatch"]];
        return;
    }
    IMP original = method_getImplementation(method);
    double (^block)(id) = ^double(id receiver) {
        // Original semantics and side effects are preserved exactly once.
        double value = ((double (*)(id, SEL))original)(receiver, selector);
        double result = value;
        NSInteger placement = -1;
        int state = 1;
        if (TCLCompatible && atomic_load(&TCLActive[3]) == 1) {
            id controller = nil;
            placement = TCLCurrentTabPlacement(&controller);
            state = placement < 0 ? 2 : 3;
            if (placement == 1 || placement == 2) {
                double bottom;
                if (TCLCurrentBottomSafeArea(controller, &bottom)) {
                    result = bottom;
                    state = 4;
                    atomic_fetch_add(&TCLBottomApplied, 1);
                } else {
                    state = 5;
                }
            }
        }
        atomic_fetch_add(&TCLBottomCalls, 1);
        atomic_store(&TCLBottomPlacement, placement);
        atomic_store(&TCLBottomOriginal, value);
        atomic_store(&TCLBottomEffective, result);
        atomic_store(&TCLBottomState, state);
        return result;
    };
    IMP replacement = imp_implementationWithBlock(block);
    // Keep inherited implementations intact on all other service classes.
    if (!class_addMethod(target, selector, replacement, method_getTypeEncoding(method)))
        method_setImplementation(class_getInstanceMethod(target, selector), replacement);
    [TCLHookStatus addObject:[label stringByAppendingString:@": installed"]];
}
static NSString *TCLBottomStateDescription(void) {
    switch (atomic_load(&TCLBottomState)) {
        case 1: return @"Rail override not On — original kept";
        case 2: return @"Placement unavailable — original kept";
        case 3: return @"Other placement — original kept";
        case 4: return @"Vertical rail — bottom safe area retained";
        case 5: return @"Safe area unavailable — original kept";
        default: return @"Not observed";
    }
}
static void TCLInstallHooks(void) {
    static BOOL installed; if(installed || !TCLCompatible) return;
    // The validated framework is linked before this dylib's constructor.
    if(!NSClassFromString(@"TTKABTest") || !NSClassFromString(@"TTKPadABConfig")) return;
    installed=YES;
    TCLAddHook(@"TTKPadABConfig",@"feedPadUIEnableConfig",YES,0,YES);
    TCLAddHook(@"_TtC13TikTokPadImpl16PadABTestIocImpl",@"feedPadUIEnableConfig",NO,0,YES);
    TCLAddHook(@"TTKTabBarLiquidGlassConfig",@"liquidGlassABEnabled",YES,1,NO);
    TCLAddHook(@"TTKTabBarLiquidGlassConfig",@"foldScreenLiquidGlassEnabled",YES,1,NO);
    TCLAddHook(@"TTKABTest",@"feedFoldableFakeLandscapeCropLayoutEnable",YES,2,NO);
    TCLAddHook(@"ABTestCodeGen",@"feedFoldableFakeLandscapeCropLayoutEnable",NO,2,NO);
    TCLAddHook(@"TTKABTest",@"tabBarVerticalLayoutEnable",YES,3,NO);
    TCLAddHook(@"ABTestCodeGen",@"tabBarVerticalLayoutEnable",NO,3,NO);
    TCLInstallBottomSpacingHook();
}
NSString *TCLCoverDiagnostics(void) {
    NSMutableString *s=[NSMutableString stringWithFormat:@"TikTok Duo 1.0.1\nTarget: TikTok 47.7.0 (477034)\nBinary match: %@\nPreferences: iOS Settings app\nLaunch preferences: %@\n\nModes: -1 Default, 0 Off, 1 On. Saved changes apply next launch.\n",TCLCompatible?@"YES":@"NO — overrides disabled",TCLRecovery];
    for(NSInteger i=0;i<TCLExperimentCount;i++) [s appendFormat:@"\n%@: saved=%ld, active=%d, calls=%llu, last original=%d\n",TCLKeys[i],(long)TCLCoverModeValue(TCLKeys[i]),atomic_load(&TCLActive[i]),(unsigned long long)atomic_load(&TCLHits[i]),atomic_load(&TCLLastOriginal[i])];
    [s appendFormat:@"\nBottom reservation: %@; calls=%llu; removed=%llu; placement=%ld; original=%.3f; effective=%.3f\n", TCLBottomStateDescription(), (unsigned long long)atomic_load(&TCLBottomCalls), (unsigned long long)atomic_load(&TCLBottomApplied), (long)atomic_load(&TCLBottomPlacement), atomic_load(&TCLBottomOriginal), atomic_load(&TCLBottomEffective)];
    [s appendString:@"\nOriginal -1 means not observed / dictionary-valued. Counts record actual method calls only; they do not prove a visible layout.\n\n"];
    [s appendString:[TCLHookStatus componentsJoinedByString:@"\n"]?:@"Hooks not installed."];
    return s;
}
// Settings.bundle displays these passive snapshots without relying on any
// in-app settings controller. Do not call experiment getters while collecting status.
static void TCLSaveSettingsStatus(void) {
    [TCLPrefs setObject:TCLActiveLayout forKey:@"TCLCover.status.layout"];
    NSUInteger installed = 0;
    for (NSString *line in TCLHookStatus) if ([line hasSuffix:@": installed"]) installed++;
    [TCLPrefs setObject:@"1.0.1" forKey:@"TCLCover.status.version"];
    [TCLPrefs setObject:!TCLCompatible ? @"Loaded — unsupported binary" :
        (installed == TCLExpectedHookCount ? @"Loaded — hooks installed" : @"Loaded — check diagnostics")
        forKey:@"TCLCover.status.engine"];
    [TCLPrefs setObject:TCLCompatible ? @"Supported 47.7.0" : @"Unsupported — overrides disabled" forKey:@"TCLCover.status.binary"];
    [TCLPrefs setObject:[NSString stringWithFormat:@"%lu of %u", (unsigned long)installed, TCLExpectedHookCount] forKey:@"TCLCover.status.hooks"];
    [TCLPrefs setObject:TCLRecovery forKey:@"TCLCover.status.recovery"];
    [TCLPrefs setObject:TCLBottomStateDescription() forKey:@"TCLCover.status.bottom.state"];
    [TCLPrefs setObject:[NSString stringWithFormat:@"%llu", (unsigned long long)atomic_load(&TCLBottomCalls)] forKey:@"TCLCover.status.bottom.calls"];
    [TCLPrefs setObject:[NSString stringWithFormat:@"%llu", (unsigned long long)atomic_load(&TCLBottomApplied)] forKey:@"TCLCover.status.bottom.applied"];
    [TCLPrefs setObject:[NSString stringWithFormat:@"%ld", (long)atomic_load(&TCLBottomPlacement)] forKey:@"TCLCover.status.bottom.placement"];
    [TCLPrefs setObject:atomic_load(&TCLBottomCalls) ? [NSString stringWithFormat:@"%.2f pt", atomic_load(&TCLBottomOriginal)] : @"Not observed" forKey:@"TCLCover.status.bottom.original"];
    [TCLPrefs setObject:atomic_load(&TCLBottomCalls) ? [NSString stringWithFormat:@"%.2f pt", atomic_load(&TCLBottomEffective)] : @"Not observed" forKey:@"TCLCover.status.bottom.effective"];
    [TCLPrefs setObject:[NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle] forKey:@"TCLCover.status.updated"];
    for (NSInteger i = 0; i < TCLExperimentCount; i++) {
        int mode = atomic_load(&TCLActive[i]);
        [TCLPrefs setObject:mode < 0 ? @"Default" : (mode ? @"On" : @"Off")
            forKey:[@"TCLCover.status.active." stringByAppendingString:TCLKeys[i]]];
        [TCLPrefs setObject:[NSString stringWithFormat:@"%llu", (unsigned long long)atomic_load(&TCLHits[i])]
            forKey:[@"TCLCover.status.calls." stringByAppendingString:TCLKeys[i]]];
    }
#ifndef TCLC_TEST
    TCLCoverNativeRefresh();
    TCLCoverChromeRefresh();
    [TCLCoverChromeStatus() enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, __unused BOOL *stop) {
        [TCLPrefs setObject:value forKey:[@"TCLCover.status.chrome." stringByAppendingString:key]];
    }];
    [TCLCoverNativeStatus() enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, __unused BOOL *stop) {
        [TCLPrefs setObject:value forKey:[@"TCLCover.status.native." stringByAppendingString:key]];
    }];
    NSString *windowSize=@"No active window";
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.isKeyWindow) continue;
            windowSize=[NSString stringWithFormat:@"%.0f × %.0f pt",window.bounds.size.width,window.bounds.size.height];
        }
    }
    [TCLPrefs setObject:windowSize forKey:@"TCLCover.status.windowSize"];
#endif
    [TCLPrefs synchronize];
}
#ifdef TCLC_TEST
void TCLCoverTestInitialize(NSUserDefaults *prefs, BOOL compatible) {
    TCLPrefs=prefs;TCLCompatible=compatible;TCLHookStatus=[NSMutableArray new];
    atomic_store(&TCLBottomCalls,0);atomic_store(&TCLBottomApplied,0);atomic_store(&TCLBottomPlacement,-1);
    atomic_store(&TCLBottomOriginal,0);atomic_store(&TCLBottomEffective,0);atomic_store(&TCLBottomState,0);
    for(int i=0;i<TCLExperimentCount;i++){atomic_store(&TCLHits[i],0);atomic_store(&TCLLastOriginal[i],-1);}
    TCLLoadModes();TCLInstallHooks();
}
void TCLCoverTestSimulateRestart(void) { TCLLoadModes(); }
#else
static const struct mach_header_64 *TCLCoreHeader;
static intptr_t TCLCoreSlide;
static BOOL TCLMatchesCore(void) {
    static const unsigned char uuid[16]={0x81,0x15,0x63,0x93,0x0f,0x58,0x38,0xc4,0x87,0x23,0x0b,0x15,0xcf,0x11,0xec,0x16};
    if(![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"47.7.0"] || ![[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"477034"]) return NO;
    for(uint32_t i=0;i<_dyld_image_count();i++) {
        const char *path=_dyld_get_image_name(i);if(!path || !strstr(path,"/MusicallyCore.framework/MusicallyCore"))continue;
        const struct mach_header_64 *h=(const void *)_dyld_get_image_header(i);if(h->magic!=MH_MAGIC_64)return NO;
        const uint8_t *p=(const void *)(h+1),*end=p+h->sizeofcmds;
        for(uint32_t j=0;j<h->ncmds && p+sizeof(struct load_command)<=end;j++) {
            const struct load_command *c=(const void *)p;
            if(c->cmdsize<sizeof(*c) || p+c->cmdsize>end)return NO;
            if(c->cmd==LC_UUID && c->cmdsize>=sizeof(struct uuid_command)) {
                BOOL match=!memcmp(((const struct uuid_command*)c)->uuid,uuid,16);
                if(match){TCLCoreHeader=h;TCLCoreSlide=_dyld_get_image_vmaddr_slide(i);}
                return match;
            }
            p+=c->cmdsize;
        }
    }
    return NO;
}
__attribute__((constructor)) static void TCLStart(void) {
    @autoreleasepool {
        TCLPrefs=NSUserDefaults.standardUserDefaults;TCLHookStatus=[NSMutableArray new];TCLCompatible=TCLMatchesCore();
        for(int i=0;i<TCLExperimentCount;i++)atomic_store(&TCLLastOriginal[i],-1);
        TCLPrepareLaunchPreferences();TCLInstallHooks();
        if(TCLCompatible) {
            TCLCoverNativeStart(TCLCoreHeader,TCLCoreSlide,atomic_load(&TCLActive[0]),atomic_load(&TCLActive[1]),atomic_load(&TCLActive[3]));
            TCLCoverChromeStart(atomic_load(&TCLActive[4]) == 1);
        }
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){
            TCLInstallHooks();TCLSaveSettingsStatus();
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){ TCLSaveSettingsStatus(); }];
        dispatch_async(dispatch_get_main_queue(),^{TCLInstallHooks();TCLSaveSettingsStatus();});
    }
}
#endif
