// Foundation-only runtime tests. Including the engine permits exercising its
// private idempotent installation routine without adding a production API.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../src/TCLCoverSettings.h"
#define TCLC_TEST 1
#import "../src/TCLCoverEngine.m"

@interface TCLMemoryDefaults : NSUserDefaults
@property(nonatomic, strong) NSMutableDictionary *values;
@end
@implementation TCLMemoryDefaults
- (instancetype)init { self = [super init]; if (self) _values = [NSMutableDictionary new]; return self; }
- (id)objectForKey:(NSString *)key { return self.values[key]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { self.values[key] = @(value); }
- (void)setObject:(id)value forKey:(NSString *)key { self.values[key] = value; }
- (void)removeObjectForKey:(NSString *)key { [self.values removeObjectForKey:key]; }
- (BOOL)synchronize { return YES; }
@end

static NSUInteger failures;
static NSMutableDictionary<NSString *, NSNumber *> *calls;
static NSMutableDictionary<NSString *, NSNumber *> *booleanDefaults;
static id dictionaryValue;
static NSString *mismatchKey;
static BOOL wrongBottomABI, wrongPlacementABI;
static id mockTabManager, mockTabController;
static NSInteger mockTabPlacement;
static double mockBottomOffset = 44.0;
static double mockSafeArea = 21.5;
static NSUInteger safeAreaReads;
double TCLCoverTestSafeArea(id controller) {
    (void)controller; safeAreaReads++; return mockSafeArea;
}
static NSUInteger bottomOriginalCalls, placementReads;
static NSString *const BottomSelector = @"iPhoneDuoHomeInterationAreaOffset";
static NSString *const VerticalSelector = @"tabBarVerticalLayoutEnable";
static NSString *const CropSelector = @"feedFoldableFakeLandscapeCropLayoutEnable";
static NSString *const ConfigSelector = @"feedPadUIEnableConfig";
static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); failures++; }
}
static NSString *InvocationKey(id receiver, SEL selector) {
    return [NSString stringWithFormat:@"%c[%@ %@]", object_isClass(receiver) ? '+' : '-',
            NSStringFromClass(object_isClass(receiver) ? receiver : [receiver class]), NSStringFromSelector(selector)];
}
static void Count(id receiver, SEL selector) {
    NSString *key = InvocationKey(receiver, selector);
    calls[key] = @([calls[key] unsignedIntegerValue] + 1);
}
static BOOL OriginalBoolean(id receiver, SEL selector) {
    Count(receiver, selector);
    return [booleanDefaults[NSStringFromSelector(selector)] boolValue];
}
static id OriginalDictionary(id receiver, SEL selector) { Count(receiver, selector); return dictionaryValue; }
static NSInteger WrongInteger(id receiver, SEL selector) { Count(receiver, selector); return 42; }
static NSUInteger TotalCalls(void) {
    NSUInteger count = 0;
    for (NSNumber *value in calls.allValues) count += value.unsignedIntegerValue;
    return count;
}
static BOOL InvokeBool(id receiver, NSString *name) {
    SEL sel = NSSelectorFromString(name);
    return ((BOOL (*)(id, SEL))[receiver methodForSelector:sel])(receiver, sel);
}
static id InvokeConfig(id receiver) {
    SEL sel = NSSelectorFromString(ConfigSelector);
    return ((id (*)(id, SEL))[receiver methodForSelector:sel])(receiver, sel);
}
static double OriginalBottom(id receiver, SEL selector) {
    Count(receiver, selector); bottomOriginalCalls++; return mockBottomOffset;
}
static NSInteger WrongBottom(id receiver, SEL selector) {
    Count(receiver, selector); bottomOriginalCalls++; return 42;
}
static id MockSharedManager(id receiver, SEL selector) { Count(receiver, selector); return mockTabManager; }
static id MockCurrentController(id receiver, SEL selector) { Count(receiver, selector); return mockTabController; }
static NSInteger MockPlacement(id receiver, SEL selector) { Count(receiver, selector); placementReads++; return mockTabPlacement; }
static double WrongPlacement(id receiver, SEL selector) { Count(receiver, selector); placementReads++; return 1.0; }
static double InvokeBottom(id receiver) {
    SEL selector = NSSelectorFromString(BottomSelector);
    return ((double (*)(id, SEL))[receiver methodForSelector:selector])(receiver, selector);
}
static Class Register(NSString *name, Class parent) {
    Class cls = objc_allocateClassPair(parent, name.UTF8String, 0);
    Check(cls != Nil, [@"Could not allocate " stringByAppendingString:name]);
    if (cls) objc_registerClassPair(cls);
    return cls;
}
static void Add(Class target, NSString *name, IMP imp, const char *types) {
    Check(class_addMethod(target, NSSelectorFromString(name), imp, types), [@"Could not add mock " stringByAppendingString:name]);
}
static void ConfigureMocks(BOOL wrongABI) {
    calls = [NSMutableDictionary new];
    booleanDefaults = [@{CropSelector:@YES, VerticalSelector:@YES, @"liquidGlassABEnabled":@NO, @"foldScreenLiquidGlassEnabled":@YES} mutableCopy];
    dictionaryValue = @{@"min_width_threshold":@450.0, @"min_aspect_ratio_threshold":@1.5,
                        @"threshold_inclusive_enabled":@NO, @"unrelated":@{@"preserve":@YES}};
    // Every tested method is inherited. A hook that mutates a superclass
    // rather than adding a target-class override will be caught below.
    Class abBase = Register(@"TCLMockABBase", NSObject.class);
    Class proxyBase = Register(@"TCLMockProxyBase", NSObject.class);
    Register(@"TTKABTest", abBase);
    Register(@"ABTestCodeGen", proxyBase);
    BOOL badCrop = wrongABI && [mismatchKey isEqual:@"crop_layout"];
    BOOL badVertical = wrongABI && [mismatchKey isEqual:@"vertical_tabs"];
    Add(object_getClass(abBase), CropSelector, badCrop ? (IMP)WrongInteger : (IMP)OriginalBoolean, badCrop ? "q@:" : "B@:");
    Add(proxyBase, CropSelector, badCrop ? (IMP)WrongInteger : (IMP)OriginalBoolean, badCrop ? "q@:" : "B@:");
    Add(object_getClass(abBase), VerticalSelector, badVertical ? (IMP)WrongInteger : (IMP)OriginalBoolean, badVertical ? "q@:" : "B@:");
    Add(proxyBase, VerticalSelector, badVertical ? (IMP)WrongInteger : (IMP)OriginalBoolean, badVertical ? "q@:" : "B@:");
    Class glassBase = Register(@"TCLMockGlassBase", NSObject.class);
    Register(@"TTKTabBarLiquidGlassConfig", glassBase);
    Add(object_getClass(glassBase), @"liquidGlassABEnabled", (IMP)OriginalBoolean, "B@:");
    Add(object_getClass(glassBase), @"foldScreenLiquidGlassEnabled", (IMP)OriginalBoolean, "B@:");
    Class configBase = Register(@"TCLMockConfigBase", NSObject.class);
    Class configProxyBase = Register(@"TCLMockConfigProxyBase", NSObject.class);
    Register(@"TTKPadABConfig", configBase);
    Register(@"_TtC13TikTokPadImpl16PadABTestIocImpl", configProxyBase);
    Add(object_getClass(configBase), ConfigSelector, (IMP)OriginalDictionary, "@@:");
    Add(configProxyBase, ConfigSelector, (IMP)OriginalDictionary, "@@:");
    Class bottomBase = Register(@"TCLMockBottomBase", NSObject.class);
    Register(@"AWEFeedModuleService", bottomBase);
    Add(bottomBase, BottomSelector, wrongBottomABI ? (IMP)WrongBottom : (IMP)OriginalBottom, wrongBottomABI ? "q@:" : "d@:");
    Class manager = Register(@"TTKTabBarManager", NSObject.class);
    Add(object_getClass(manager), @"sharedInstance", (IMP)MockSharedManager, "@@:");
    Add(manager, @"tabBarController", (IMP)MockCurrentController, "@@:");
    Class controller = Register(@"TCLMockTabController", NSObject.class);
    Add(controller, @"tabBarPlacement", wrongPlacementABI ? (IMP)WrongPlacement : (IMP)MockPlacement, wrongPlacementABI ? "d@:" : "q@:");
    mockTabManager = [manager new]; mockTabController = [controller new];
}
static NSArray<NSDictionary *> *BoolReceivers(void) {
    return @[
        @{@"key":@"vertical_tabs", @"selector":VerticalSelector, @"receiver":NSClassFromString(@"TTKABTest")},
        @{@"key":@"vertical_tabs", @"selector":VerticalSelector, @"receiver":[NSClassFromString(@"ABTestCodeGen") new]},
        @{@"key":@"crop_layout", @"selector":CropSelector, @"receiver":NSClassFromString(@"TTKABTest")},
        @{@"key":@"crop_layout", @"selector":CropSelector, @"receiver":[NSClassFromString(@"ABTestCodeGen") new]},
        @{@"key":@"glass_tabs", @"selector":@"liquidGlassABEnabled", @"receiver":NSClassFromString(@"TTKTabBarLiquidGlassConfig")},
        @{@"key":@"glass_tabs", @"selector":@"foldScreenLiquidGlassEnabled", @"receiver":NSClassFromString(@"TTKTabBarLiquidGlassConfig")}
    ];
}
static void AssertBools(NSArray *receivers, NSInteger mode, BOOL skipMismatch) {
    for (NSDictionary *record in receivers) {
        if (skipMismatch && [record[@"key"] isEqual:mismatchKey]) continue;
        NSUInteger before = TotalCalls();
        BOOL result = InvokeBool(record[@"receiver"], record[@"selector"]);
        BOOL expected = mode < 0 ? [booleanDefaults[record[@"selector"]] boolValue] : mode == 1;
        Check(result == expected, [NSString stringWithFormat:@"Wrong mode %ld result for %@", (long)mode, record[@"selector"]]);
        Check(TotalCalls() == before + 1, @"Boolean getter did not preserve exactly one original call");
    }
}
static void AssertConfigs(NSArray *receivers, NSInteger mode) {
    NSDictionary *original = dictionaryValue;
    for (id receiver in receivers) {
        NSUInteger before = TotalCalls();
        id result = InvokeConfig(receiver);
        Check(TotalCalls() == before + 1, @"Config getter did not preserve exactly one original call");
        if (mode < 0) {
            Check(result == original, @"Default config did not preserve original object identity");
        } else {
            Check([result isKindOfClass:NSDictionary.class], @"Override config changed dictionary type");
            Check([result[@"unrelated"] isEqual:original[@"unrelated"]], @"Override removed unrelated config content");
            Check([result count] == original.count, @"Override removed or added unexpected config keys");
            Check([result[@"min_width_threshold"] doubleValue] == (mode ? 1.0 : -1.0), @"Width override differs from intended contract");
            Check([result[@"min_aspect_ratio_threshold"] doubleValue] == -1.0, @"Aspect override differs from intended contract");
            Check([result[@"threshold_inclusive_enabled"] boolValue] == YES, @"Inclusive threshold was not set");
            Check([original[@"min_width_threshold"] doubleValue] == 450.0, @"Override mutated original dictionary");
        }
    }
}
static void AssertNoDiagnosticCalls(void) {
    NSUInteger before = TotalCalls();
    NSString *text = TCLCoverDiagnostics();
    Check(text.length > 0, @"Empty diagnostics");
    Check(TotalCalls() == before, @"Diagnostics proactively evaluated a gate");
}
static void TestLayoutPresets(TCLMemoryDefaults *prefs, BOOL incompatible) {
    // Exercise migration from all layout flag combinations and conflicts.
    for (NSInteger oldMode = 0; oldMode < 4; oldMode++) {
        [prefs removeObjectForKey:TCLLayoutKey];
        [prefs setInteger:oldMode == 1 || oldMode == 3 forKey:@"TCLCover.mode.glass_tabs"];
        [prefs setInteger:oldMode == 1 || oldMode == 3 forKey:@"TCLCover.mode.vertical_tabs"];
        [prefs setInteger:oldMode >= 2 forKey:@"TCLCover.mode.full_width_chrome"];
        [prefs setInteger:1 forKey:@"TCLCover.mode.adaptive_layout"];
        [prefs setInteger:0 forKey:@"TCLCover.mode.crop_layout"];
        TCLMigrateLayout();
        Check(TCLLayoutSelection() == (oldMode >= 2 ? 2 : oldMode), @"Migration lost an existing look or full-width precedence");
        Check(TCLCoverModeValue(@"adaptive_layout") == 1 && TCLCoverModeValue(@"crop_layout") == 0,
              @"Migration changed independent advanced experiments");
        [prefs setInteger:0 forKey:TCLLayoutKey]; TCLMigrateLayout();
        Check(TCLLayoutSelection() == 0, @"Migration overwrote an explicit user selection");
    }
    // Every transition is one selection; legacy flags cannot override it.
    for (NSInteger from = 0; from < 3; from++) {
        for (NSInteger to = 0; to < 3; to++) {
            [prefs setInteger:from forKey:TCLLayoutKey]; TCLLoadModes();
            [prefs setInteger:to forKey:TCLLayoutKey];
            Check(atomic_load(&TCLActive[1]) == (incompatible ? -1 : (from == 1)), @"Saved selection changed current launch");
            TCLLoadModes();
            Check(atomic_load(&TCLActive[1]) == (incompatible ? -1 : (to == 1)), @"Preset glass mapping incorrect");
            Check(atomic_load(&TCLActive[3]) == (incompatible ? -1 : (to == 1)), @"Preset rail mapping incorrect");
            Check(atomic_load(&TCLActive[4]) == (incompatible ? -1 : (to == 2)), @"Preset full-width mapping incorrect");
            Check(atomic_load(&TCLActive[0]) == (incompatible ? -1 : 1) && atomic_load(&TCLActive[2]) == (incompatible ? -1 : 0), @"Preset changed advanced experiments");
            TCLSaveSettingsStatus();
            Check([prefs.values[@"TCLCover.status.layout"] isEqual:incompatible ? @"Disabled — unsupported binary" : TCLLayoutTitle(to)], @"Active layout snapshot incorrect");
        }
    }
    [prefs setInteger:2 forKey:TCLLayoutKey];
    [prefs setObject:@YES forKey:@"TCLCover.hideShop"];
    TCLCoverResetDefaults(); TCLLoadModes();
    Check(![prefs.values[@"TCLCover.hideShop"] boolValue], @"Recovery retained optional interface features");
    Check(TCLLayoutSelection() == 0, @"Startup recovery failed to restore Classic");
    Check(TCLCoverModeValue(@"adaptive_layout") == -1 && TCLCoverModeValue(@"crop_layout") == -1, @"Recovery retained advanced overrides");
    for (id bad in @[@"Native", @99, @(-1), @1.5, NSNull.null]) {
        [prefs setObject:bad forKey:TCLLayoutKey]; TCLMigrateLayout();
        Check(TCLLayoutSelection() == 0, @"Invalid preset did not recover to Classic");
    }
    [prefs removeObjectForKey:TCLLayoutKey]; TCLMigrateLayout();
    Check(TCLLayoutSelection() == 0, @"Fresh installation did not select Classic");
}
static void TestBottomReservation(TCLMemoryDefaults *prefs, BOOL incompatible) {
    id service = [NSClassFromString(@"AWEFeedModuleService") new];
    if (wrongBottomABI) {
        TCLCoverSetModeValue(@"vertical_tabs", 1); TCLCoverTestSimulateRestart();
        SEL selector = NSSelectorFromString(BottomSelector);
        Check(((NSInteger (*)(id, SEL))[service methodForSelector:selector])(service, selector) == 42,
              @"Bottom offset hook replaced an incompatible return ABI");
        Check([TCLCoverDiagnostics() containsString:@"iPhoneDuoHomeInterationAreaOffset]: unavailable / ABI mismatch"], @"Bottom ABI rejection missing diagnostics");
        TCLCoverResetDefaults(); TCLCoverTestSimulateRestart();
        return;
    }
    for (NSNumber *mode in @[@(-1), @0, @1]) {
        TCLCoverSetModeValue(@"vertical_tabs", mode.integerValue); TCLCoverTestSimulateRestart();
        for (NSNumber *placement in @[@0, @1, @2, @3, @99, @(-1)]) {
            mockTabPlacement = placement.integerValue;
            NSUInteger before = bottomOriginalCalls;
            NSUInteger beforeSafeReads = safeAreaReads;
            BOOL applies = !incompatible && !wrongPlacementABI && mode.integerValue == 1 && (mockTabPlacement == 1 || mockTabPlacement == 2);
            Check(InvokeBottom(service) == (applies ? mockSafeArea : mockBottomOffset), @"Bottom spacing changed outside explicit On + actual vertical placement, or failed inside it");
            Check(bottomOriginalCalls == before + 1, @"Bottom offset original was not called exactly once");
            Check(safeAreaReads == beforeSafeReads + (applies ? 1 : 0), @"Safe area queried outside supported vertical mode");
        }
    }
    if (wrongPlacementABI) Check(placementReads == 0, @"Placement getter invoked with incompatible ABI");
    TCLCoverResetDefaults(); TCLCoverTestSimulateRestart();
    TCLCoverSetModeValue(@"vertical_tabs", 1); mockTabPlacement = 1;
    Check(InvokeBottom(service) == mockBottomOffset, @"Saved On changed bottom spacing before restart");
    TCLCoverTestSimulateRestart();
    double onResult = !incompatible && !wrongPlacementABI ? mockSafeArea : mockBottomOffset;
    Check(InvokeBottom(service) == onResult, @"Restart did not apply bottom spacing mode");
    TCLCoverSetModeValue(@"vertical_tabs", 0);
    Check(InvokeBottom(service) == onResult, @"Saved Off changed active bottom spacing before restart");
    TCLCoverTestSimulateRestart();
    Check(InvokeBottom(service) == mockBottomOffset, @"Off failed to restore original bottom spacing");
    TCLCoverSetModeValue(@"vertical_tabs", 1); TCLCoverTestSimulateRestart();
    id savedManager = mockTabManager, savedController = mockTabController;
    mockTabManager = nil;
    Check(InvokeBottom(service) == mockBottomOffset, @"Missing manager did not preserve original bottom offset");
    mockTabManager = savedManager; mockTabController = nil;
    Check(InvokeBottom(service) == mockBottomOffset, @"Missing controller did not preserve original bottom offset");
    mockTabController = savedController;
    Check(InvokeBottom([NSClassFromString(@"TCLMockBottomBase") new]) == mockBottomOffset, @"Bottom hook mutated superclass");
    mockBottomOffset = 83.25; mockTabPlacement = 0;
    Check(InvokeBottom(service) == 83.25, @"Horizontal placement lost nonstandard original offset");
    mockTabPlacement = 2;
    Check(InvokeBottom(service) == (!incompatible && !wrongPlacementABI ? mockSafeArea : 83.25), @"Second vertical placement failed scoped offset adjustment");
    NSUInteger before = TotalCalls();
    TCLSaveSettingsStatus(); (void)TCLCoverDiagnostics();
    Check(TotalCalls() == before, @"Bottom diagnostics evaluated live getters");
    if (!incompatible) {
        Check([prefs.values[@"TCLCover.status.bottom.original"] isEqual:@"83.25 pt"], @"Bottom original snapshot lost exact double value");
        Check([prefs.values[@"TCLCover.status.bottom.effective"] isEqual:wrongPlacementABI ? @"83.25 pt" : @"21.50 pt"], @"Bottom effective snapshot incorrect");
        Check([prefs.values[@"TCLCover.status.bottom.placement"] isEqual:wrongPlacementABI ? @"-1" : @"2"], @"Bottom actual placement snapshot incorrect");
        Check([prefs.values[@"TCLCover.status.bottom.calls"] longLongValue] > 0, @"Bottom actual calls were not counted");
    }
    // Geometry is live, including a legitimate zero inset after a layout change.
    for (NSNumber *inset in @[@0.0, @34.0, @12.75]) {
        mockSafeArea = inset.doubleValue;
        Check(InvokeBottom(service) == (!incompatible && !wrongPlacementABI ? mockSafeArea : 83.25), @"Safe area was cached, rounded or replaced with a fixed inset");
    }
    // Unloaded/detached views use the unavailable sentinel in this UIKit seam.
    for (NSNumber *invalid in @[@(NAN), @(INFINITY), @(-1.0)]) {
        mockSafeArea = invalid.doubleValue;
        Check(InvokeBottom(service) == 83.25, @"Unavailable or invalid safe area did not preserve original");
    }
    mockSafeArea = 21.5;
    NSUInteger readsBeforeStatus = safeAreaReads;
    TCLSaveSettingsStatus(); (void)TCLCoverDiagnostics();
    Check(safeAreaReads == readsBeforeStatus, @"Diagnostics evaluated safe area proactively");
    // An unexpected background caller must retain the original rather than
    // querying UIKit controller state off-main.
    __block double backgroundResult = 0;
    dispatch_semaphore_t complete = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        @autoreleasepool { backgroundResult = InvokeBottom(service); }
        dispatch_semaphore_signal(complete);
    });
    dispatch_semaphore_wait(complete, DISPATCH_TIME_FOREVER);
    Check(backgroundResult == 83.25, @"Background caller did not retain original offset");
    TCLCoverResetDefaults(); TCLCoverTestSimulateRestart();
    mockBottomOffset = 44.0;
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        wrongBottomABI = argc > 1 && strcmp(argv[1], "wrong-bottom-abi") == 0;
        wrongPlacementABI = argc > 1 && strcmp(argv[1], "wrong-placement-abi") == 0;
        BOOL wrongVerticalABI = argc > 1 && strcmp(argv[1], "wrong-vertical-abi") == 0;
        BOOL wrongABI = wrongVerticalABI || (argc > 1 && strcmp(argv[1], "wrong-abi") == 0);
        mismatchKey = wrongVerticalABI ? @"vertical_tabs" : @"crop_layout";
        BOOL incompatible = argc > 1 && strcmp(argv[1], "incompatible") == 0;
        BOOL late = argc > 1 && strcmp(argv[1], "late-classes") == 0;
        if (!late) ConfigureMocks(wrongABI);
        TCLMemoryDefaults *prefs = [TCLMemoryDefaults new];
        TCLCoverTestInitialize(prefs, !incompatible);
        if (late) { ConfigureMocks(wrongABI); TCLInstallHooks(); }
        NSArray *entries = TCLCoverExperimentEntries();
        NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:@"resources/Settings.bundle/Root.plist"];
        NSUInteger controls = 0;
        for (NSDictionary *specifier in root[@"PreferenceSpecifiers"]) {
            if (![specifier[@"Type"] isEqual:@"PSMultiValueSpecifier"]) continue;
            Check([specifier[@"Key"] isEqual:TCLLayoutKey], @"Root exposes conflicting experiment controls");
            Check([specifier[@"Titles"] isEqual:@[@"Classic", @"Native", @"Fullscreen"]], @"Layout titles differ from requested modes");
            Check([specifier[@"Values"] isEqual:@[@0, @1, @2]], @"Layout values incorrect");
            Check([specifier[@"DefaultValue"] isEqual:@0], @"Fresh layout default is not Classic");
            for (NSNumber *mode in specifier[@"Values"]) {
                [prefs setObject:mode forKey:specifier[@"Key"]];
                Check(TCLLayoutSelection() == mode.integerValue, @"Settings selection not accepted");
            }
            controls++;
        }
        Check(controls == 1, @"Root must have exactly one layout picker");
        NSMutableSet *switches=[NSMutableSet new];
        for(NSDictionary *specifier in root[@"PreferenceSpecifiers"]){
            if(![specifier[@"Type"] isEqual:@"PSToggleSwitchSpecifier"])continue;
            Check([specifier[@"DefaultValue"] isEqual:@NO], @"Optional interface feature must default off");
            [switches addObject:specifier[@"Key"]];
        }
        Check([switches isEqual:[NSSet setWithArray:@[@"TCLCover.hideShop"]]], @"Feed interface preferences missing or unexpected");
        [prefs removeObjectForKey:TCLLayoutKey];
        NSDictionary *advanced = [NSDictionary dictionaryWithContentsOfFile:@"resources/Settings.bundle/Advanced.plist"];
        controls = 0;
        for (NSDictionary *specifier in advanced[@"PreferenceSpecifiers"]) {
            if (![specifier[@"Type"] isEqual:@"PSMultiValueSpecifier"]) continue;
            NSString *key = specifier[@"Key"];
            Check([@[@"TCLCover.mode.adaptive_layout", @"TCLCover.mode.crop_layout"] containsObject:key], @"Advanced page exposes a conflicting layout switch");
            NSString *experiment = [key substringFromIndex:@"TCLCover.mode.".length];
            Check([specifier[@"Values"] isEqual:@[@(-1), @0, @1]], @"Advanced modes incorrect");
            for (NSNumber *mode in specifier[@"Values"]) {
                [prefs setObject:mode forKey:key];
                Check(TCLCoverModeValue(experiment) == mode.integerValue, @"Advanced setting not accepted");
            }
            controls++;
        }
        Check(controls == 2, @"Advanced page must retain two independent experiments");
        TCLCoverResetDefaults();
        TCLSaveSettingsStatus();
        Check([prefs.values[@"TCLCover.status.version"] isEqual:@"1.0.0"], @"Settings engine load status missing");
        Check([prefs.values[@"TCLCover.status.hooks"] isEqual:incompatible ? @"0 of 9" : (wrongABI ? @"7 of 9" : (wrongBottomABI ? @"8 of 9" : @"9 of 9"))], @"Settings hook count incorrect");
        Check(TotalCalls() == 0, @"Status gathering proactively evaluated a gate");
        NSArray *boolReceivers = BoolReceivers();
        NSArray *configReceivers = @[NSClassFromString(@"TTKPadABConfig"), [NSClassFromString(@"_TtC13TikTokPadImpl16PadABTestIocImpl") new]];
        Check(entries.count == 5, @"Unexpected experiment control count");
        Check(TotalCalls() == 0, @"Initialization proactively evaluated a gate");
        AssertNoDiagnosticCalls();
        if (!incompatible) Check([TCLCoverDiagnostics() containsString:@"calls=0"], @"Diagnostics did not start with zero observed calls");
        for (NSDictionary *entry in entries) Check(TCLCoverModeValue(entry[@"key"]) == -1, @"Fresh preferences did not follow Default");
        AssertBools(boolReceivers, -1, wrongABI);
        AssertConfigs(configReceivers, -1);
        AssertNoDiagnosticCalls();
        if (!incompatible) {
            NSString *diag = TCLCoverDiagnostics();
            Check([diag containsString:@"adaptive_layout: saved=-1, active=-1, calls=2"], @"Dictionary hit diagnostics did not reflect two actual calls");
            Check([diag containsString:@"glass_tabs: saved=-1, active=-1, calls=2"], @"Boolean hit diagnostics did not reflect two actual calls");
            if (!wrongVerticalABI) Check([diag containsString:@"vertical_tabs: saved=-1, active=-1, calls=2"], @"Vertical diagnostics did not reflect two actual calls");
        }
        // Exercise the new control alone so accidental cross-indexing cannot
        // pass merely because all controls share an Off/On setting below.
        TCLCoverSetModeValue(@"vertical_tabs", 0);
        TCLCoverTestSimulateRestart();
        for (NSDictionary *record in boolReceivers) {
            if (wrongABI && [record[@"key"] isEqual:mismatchKey]) continue;
            BOOL expected = !incompatible && [record[@"key"] isEqual:@"vertical_tabs"] ? NO : [booleanDefaults[record[@"selector"]] boolValue];
            Check(InvokeBool(record[@"receiver"], record[@"selector"]) == expected, @"Vertical override changed another experiment or failed independently");
        }
        AssertConfigs(configReceivers, -1);
        for (NSDictionary *entry in entries) if (![entry[@"key"] isEqual:@"vertical_tabs"]) Check(TCLCoverModeValue(entry[@"key"]) == -1, @"Vertical override changed another saved preference");
        NSUInteger beforeStatus = TotalCalls();
        TCLSaveSettingsStatus();
        Check(TotalCalls() == beforeStatus, @"Vertical status snapshot proactively called a getter");
        Check([prefs.values[@"TCLCover.status.active.vertical_tabs"] isEqual:incompatible ? @"Default" : @"Off"], @"Vertical active Off snapshot incorrect");
        unsigned long long verticalCalls = incompatible || wrongVerticalABI ? 0 : 4;
        Check([prefs.values[@"TCLCover.status.calls.vertical_tabs"] longLongValue] == (long long)verticalCalls, @"Vertical calls snapshot incorrect");
        TCLCoverResetDefaults(); TCLCoverTestSimulateRestart();
        for (NSDictionary *entry in entries) TCLCoverSetModeValue(entry[@"key"], 0);
        AssertBools(boolReceivers, -1, wrongABI);
        AssertConfigs(configReceivers, -1);
        TCLCoverTestSimulateRestart();
        AssertBools(boolReceivers, incompatible ? -1 : 0, wrongABI);
        AssertConfigs(configReceivers, incompatible ? -1 : 0);
        if (wrongABI) {
            for (NSDictionary *record in boolReceivers) if ([record[@"key"] isEqual:mismatchKey]) {
                id receiver = record[@"receiver"]; SEL sel = NSSelectorFromString(record[@"selector"]);
                Check(((NSInteger (*)(id, SEL))[receiver methodForSelector:sel])(receiver, sel) == 42, @"Hook replaced incompatible integer ABI");
            }
            Check([TCLCoverDiagnostics() containsString:@"ABI mismatch"], @"Skipped incompatible methods are absent from diagnostics");
        }
        if (!wrongABI || wrongVerticalABI) {
            Check(InvokeBool(NSClassFromString(@"TCLMockABBase"), CropSelector) == YES, @"Class hook mutated superclass");
            Check(InvokeBool([NSClassFromString(@"TCLMockProxyBase") new], CropSelector) == YES, @"Instance hook mutated superclass");
        }
        if (!wrongVerticalABI) {
            Check(InvokeBool(NSClassFromString(@"TCLMockABBase"), VerticalSelector) == YES, @"Vertical class hook mutated superclass");
            Check(InvokeBool([NSClassFromString(@"TCLMockProxyBase") new], VerticalSelector) == YES, @"Vertical instance hook mutated superclass");
        }
        Check(InvokeBool(NSClassFromString(@"TCLMockGlassBase"), @"foldScreenLiquidGlassEnabled") == YES, @"Glass hook mutated superclass");
        Check(InvokeConfig(NSClassFromString(@"TCLMockConfigBase")) == dictionaryValue, @"Config class hook mutated superclass");
        Check(InvokeConfig([NSClassFromString(@"TCLMockConfigProxyBase") new]) == dictionaryValue, @"Config instance hook mutated superclass");
        for (NSDictionary *entry in entries) TCLCoverSetModeValue(entry[@"key"], 1);
        TCLCoverTestSimulateRestart();
        TCLSaveSettingsStatus();
        Check([prefs.values[@"TCLCover.status.active.crop_layout"] isEqual:incompatible ? @"Default" : @"On"], @"Settings active mode incorrect");
        AssertBools(boolReceivers, incompatible ? -1 : 1, wrongABI);
        AssertConfigs(configReceivers, incompatible ? -1 : 1);
        Check([prefs.values[@"TCLCover.status.active.vertical_tabs"] isEqual:incompatible ? @"Default" : @"On"], @"Vertical active mode snapshot incorrect");
        id validDictionary = dictionaryValue;
        for (id atypical in @[@"unexpected scalar", @42, NSNull.null]) {
            dictionaryValue = atypical;
            for (id receiver in configReceivers) Check(InvokeConfig(receiver) == atypical, @"Config hook coerced unexpected type");
        }
        dictionaryValue = nil;
        for (id receiver in configReceivers) Check(InvokeConfig(receiver) == nil, @"Config hook coerced nil");
        dictionaryValue = validDictionary;
        for (NSDictionary *entry in entries) {
            NSInteger prior = TCLCoverModeValue(entry[@"key"]);
            TCLCoverSetModeValue(entry[@"key"], 99);
            Check(TCLCoverModeValue(entry[@"key"]) == prior, @"Invalid mode altered preference");
            TCLCoverSetModeValue(entry[@"key"], -2);
            Check(TCLCoverModeValue(entry[@"key"]) == prior, @"Negative invalid mode altered preference");
        }
        NSUInteger keyCount = prefs.values.count;
        TCLCoverSetModeValue(@"unrelated_test_key", 1);
        Check(TCLCoverModeValue(@"unrelated_test_key") == -1 && prefs.values.count == keyCount, @"Unknown key was accepted");
        [prefs setObject:@"malformed" forKey:@"TCLCover.mode.crop_layout"];
        Check(TCLCoverModeValue(@"crop_layout") == -1, @"Malformed stored value was accepted");
        TCLCoverResetDefaults();
        for (NSDictionary *entry in entries) Check(TCLCoverModeValue(entry[@"key"]) == -1, @"Reset left saved override");
        TCLCoverTestSimulateRestart();
        AssertBools(boolReceivers, -1, wrongABI);
        AssertConfigs(configReceivers, -1);
        NSString *diagBefore = TCLCoverDiagnostics();
        TCLInstallHooks(); TCLInstallHooks();
        Check([TCLCoverDiagnostics() isEqual:diagBefore], @"Repeated hook installation changed diagnostics");
        AssertBools(boolReceivers, -1, wrongABI);
        AssertNoDiagnosticCalls();
        if (incompatible) {
            Check([TCLCoverDiagnostics() containsString:@"NO — overrides disabled"], @"Incompatible version missing disabled diagnostic");
            Check(![TCLCoverDiagnostics() containsString:@": installed"], @"Incompatible version installed hooks");
        }
        TestBottomReservation(prefs, incompatible);
        TestLayoutPresets(prefs, incompatible);
        fprintf(stdout, "%s: %s (%lu failures)\n", argc > 1 ? argv[1] : "normal", failures ? "FAIL" : "PASS", (unsigned long)failures);
    }
    return failures ? 1 : 0;
}
