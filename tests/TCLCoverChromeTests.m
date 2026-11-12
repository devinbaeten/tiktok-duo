#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>

typedef struct { double top,left,bottom,right; } UIEdgeInsets;
typedef NS_ENUM(NSInteger,UISceneActivationState) {
    UISceneActivationStateForegroundActive,
    UISceneActivationStateForegroundInactive,
    UISceneActivationStateBackground
};
@interface UITraitCollection : NSObject
@property NSInteger verticalBarEdge;
@end
@implementation UITraitCollection
@end
@interface UIViewController : NSObject
@property NSArray<UIViewController *> *childViewControllers;
@property UIViewController *forwardedChild;
@property NSUInteger originalBehaviorCalls,originalChildCalls,notifications;
- (NSInteger)preferredVerticalBarBehavior;
- (UIViewController *)childViewControllerForPreferredVerticalBarBehavior;
- (void)setNeedsUpdateOfVerticalBarConfiguration;
@end
@implementation UIViewController
- (instancetype)init { if ((self=[super init])) _childViewControllers=@[];return self; }
- (NSInteger)preferredVerticalBarBehavior { self.originalBehaviorCalls++;return 0; }
- (UIViewController *)childViewControllerForPreferredVerticalBarBehavior { self.originalChildCalls++;return self.forwardedChild; }
- (void)setNeedsUpdateOfVerticalBarConfiguration { self.notifications++; }
@end
@interface UINavigationController : UIViewController @end
@implementation UINavigationController @end
@interface UITabBarController : UIViewController @end
@implementation UITabBarController @end
@interface TTKTabBarController : UITabBarController @end
@implementation TTKTabBarController @end
@interface TCLChromeTestRoot : UIViewController @end
@implementation TCLChromeTestRoot @end
@interface TCLChromeTestOtherRoot : UIViewController @end
@implementation TCLChromeTestOtherRoot @end
@interface TCLChromeTestSubclassRoot : TCLChromeTestRoot @end
@implementation TCLChromeTestSubclassRoot @end
@interface TCLChromeTestOwnRoot : UIViewController @end
@implementation TCLChromeTestOwnRoot
- (NSInteger)preferredVerticalBarBehavior { self.originalBehaviorCalls++;return 7; }
- (UIViewController *)childViewControllerForPreferredVerticalBarBehavior { self.originalChildCalls++;return self.forwardedChild; }
@end
@interface TCLChromeBadRoot : UIViewController @end
@implementation TCLChromeBadRoot @end
@interface UIWindow : NSObject
@property BOOL isKeyWindow,hidden;
@property UIViewController *rootViewController;
@property UIEdgeInsets safeAreaInsets;
@property UITraitCollection *traitCollection;
@end
@implementation UIWindow @end
@interface UIScene : NSObject
@property UISceneActivationState activationState;
@end
@implementation UIScene @end
@interface UIWindowScene : UIScene
@property NSArray<UIWindow *> *windows;
@end
@implementation UIWindowScene @end
@interface UIApplication : NSObject
@property NSSet<UIScene *> *connectedScenes;
+ (instancetype)sharedApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *app; if (!app) app=[UIApplication new];return app; }
@end

#define TCLCHROME_TEST 1
#import "../src/TCLCoverChrome.m"

static UIWindow *window;
static UIWindowScene *scene;
static UIViewController *installRoot(Class cls, BOOL withTab) {
    UIViewController *root=[cls new];
    root.forwardedChild=[UIViewController new];
    if (withTab) root.childViewControllers=@[[TTKTabBarController new]];
    window.rootViewController=root;
    return root;
}
static void setup(void) {
    window=[UIWindow new];window.isKeyWindow=YES;
    window.safeAreaInsets=(UIEdgeInsets){12,0,20,80};
    window.traitCollection=[UITraitCollection new];window.traitCollection.verticalBarEdge=2;
    scene=[UIWindowScene new];scene.activationState=UISceneActivationStateForegroundActive;
    scene.windows=@[window];UIApplication.sharedApplication.connectedScenes=[NSSet setWithObject:scene];
}
static void disabledTest(void) {
    UIViewController *root=installRoot(TCLChromeTestRoot.class,YES);
    IMP before=class_getMethodImplementation(TCLChromeTestRoot.class,@selector(preferredVerticalBarBehavior));
    TCLCoverChromeStart(NO);TCLCoverChromeRefresh();
    assert(before==class_getMethodImplementation(TCLChromeTestRoot.class,@selector(preferredVerticalBarBehavior)));
    assert(root.notifications==0);
    assert(root.preferredVerticalBarBehavior==0);
    assert([root childViewControllerForPreferredVerticalBarBehavior]==root.forwardedChild);
    assert([TCLCoverChromeStatus()[@"chromeBehaviorCalls"] isEqual:@"0"]);
}
static void enabledTests(void) {
    TCLCoverChromeStart(YES);
    UIViewController *root=installRoot(TCLChromeTestRoot.class,NO);
    TCLCoverChromeRefresh();assert(root.notifications==0);
    // Cyclic containment must terminate without attaching.
    root.childViewControllers=@[root];TCLCoverChromeRefresh();assert(root.notifications==0);
    root.childViewControllers=@[[TTKTabBarController new]];
    window.hidden=YES;TCLCoverChromeRefresh();assert(root.notifications==0);window.hidden=NO;
    scene.activationState=UISceneActivationStateBackground;TCLCoverChromeRefresh();assert(root.notifications==0);
    scene.activationState=UISceneActivationStateForegroundActive;
    UIViewController *sameClassOther=[TCLChromeTestRoot new];sameClassOther.forwardedChild=[UIViewController new];
    IMP baseBefore=class_getMethodImplementation(UIViewController.class,@selector(preferredVerticalBarBehavior));
    TCLCoverChromeRefresh();assert(root.notifications==1);
    assert(baseBefore==class_getMethodImplementation(UIViewController.class,@selector(preferredVerticalBarBehavior)));
    // Snapshot/refresh must not execute either intercepted preference getter.
    NSDictionary *status=TCLCoverChromeStatus();TCLCoverChromeRefresh();
    assert(root.notifications==1 && root.originalBehaviorCalls==0 && root.originalChildCalls==0);
    assert([status[@"chromeBehaviorCalls"] isEqual:@"0"]);
    assert([status[@"chromeTraitEdge"] isEqual:@"2"]);
    assert([status[@"chromeWindowInsets"] containsString:@"right 80.0"]);
    assert(root.preferredVerticalBarBehavior==1);
    assert([root childViewControllerForPreferredVerticalBarBehavior]==nil);
    assert(root.originalBehaviorCalls==1 && root.originalChildCalls==1);
    assert(sameClassOther.preferredVerticalBarBehavior==0);
    assert([sameClassOther childViewControllerForPreferredVerticalBarBehavior]==sameClassOther.forwardedChild);
    status=TCLCoverChromeStatus();
    assert([status[@"chromeOriginalBehavior"] isEqual:@"0"]);
    assert([status[@"chromeOriginalChild"] isEqual:@"UIViewController"]);
    assert([status[@"chromeBehaviorCalls"] isEqual:@"1"] && [status[@"chromeChildCalls"] isEqual:@"1"]);
    // Replacement root inherits a previously hooked class: no double counting.
    UIViewController *sub=installRoot(TCLChromeTestSubclassRoot.class,YES);
    assert(root.preferredVerticalBarBehavior==0); // Stale root stops before refresh.
    TCLCoverChromeRefresh();assert(sub.notifications==1 && sub.preferredVerticalBarBehavior==1);
    assert(sub.originalBehaviorCalls==1);
    assert([TCLCoverChromeStatus()[@"chromeBehaviorCalls"] isEqual:@"2"]);
    assert(root.preferredVerticalBarBehavior==0); // Old receiver no longer affected.
    // Existing own implementations must remain the source of original behavior.
    UIViewController *own=installRoot(TCLChromeTestOwnRoot.class,YES);
    TCLCoverChromeRefresh();assert(own.preferredVerticalBarBehavior==1);
    assert(own.originalBehaviorCalls==1);
    assert([TCLCoverChromeStatus()[@"chromeOriginalBehavior"] isEqual:@"7"]);
    // Direct UIKit base roots are deliberately not patched.
    UIViewController *systemRoot=installRoot(UIViewController.class,YES);
    TCLCoverChromeRefresh();assert(systemRoot.notifications==0 && systemRoot.preferredVerticalBarBehavior==0);
    assert([TCLCoverChromeStatus()[@"chromeRoute"] containsString:@"system root"]);
    assert(own.preferredVerticalBarBehavior==7);
    // Reproduce an app root with no image attribution and a runtime subclass
    // whose -class hides its actual class, as KVO-style wrappers can do.
    Class anchor=objc_allocateClassPair(UINavigationController.class,"AWERootNavigationController",0);
    assert(anchor);objc_registerClassPair(anchor);
    Class runtime=objc_allocateClassPair(anchor,"TCLRuntimeRootWrapper",0);
    assert(runtime);
    IMP reportedClass=imp_implementationWithBlock(^Class(__unused id receiver) { return anchor; });
    assert(class_addMethod(runtime,@selector(class),reportedClass,"#@:"));
    objc_registerClassPair(runtime);
    assert(class_getImageName(runtime)==NULL);
    UIViewController *runtimeRoot=installRoot(runtime,YES);
    TCLCoverChromeRefresh();assert(runtimeRoot.notifications==1);
    assert(runtimeRoot.preferredVerticalBarBehavior==1);
    assert([runtimeRoot childViewControllerForPreferredVerticalBarBehavior]==nil);
    assert(runtimeRoot.originalBehaviorCalls==1 && runtimeRoot.originalChildCalls==1);
    NSDictionary *runtimeStatus=TCLCoverChromeStatus();
    assert([runtimeStatus[@"chromeRoot"] isEqual:@"AWERootNavigationController"]);
    assert([runtimeStatus[@"chromeRuntimeRoot"] isEqual:@"TCLRuntimeRootWrapper"]);
    assert([runtimeStatus[@"chromeOwnership"] isEqual:@"Verified TikTok root ancestry"]);
    UIViewController *sibling=[runtime new];
    assert(sibling.preferredVerticalBarBehavior==0);
    assert(class_getMethodImplementation(UINavigationController.class,@selector(preferredVerticalBarBehavior))==baseBefore);
    UIViewController *directRoot=installRoot(anchor,YES);
    TCLCoverChromeRefresh();assert(directRoot.notifications==1);
    assert(directRoot.preferredVerticalBarBehavior==1);
    assert([directRoot childViewControllerForPreferredVerticalBarBehavior]==nil);
    assert(directRoot.originalBehaviorCalls==1 && directRoot.originalChildCalls==1);
    // A similar name without the exact TikTok ancestor must stay unmodified.
    Class unknown=objc_allocateClassPair(UINavigationController.class,"AWERootNavigationControllerLookalike",0);
    assert(unknown);objc_registerClassPair(unknown);
    UIViewController *unknownRoot=installRoot(unknown,YES);
    TCLCoverChromeRefresh();assert(unknownRoot.notifications==0);
    assert(unknownRoot.preferredVerticalBarBehavior==0);
    assert([TCLCoverChromeStatus()[@"chromeRoute"] containsString:@"unverified root"]);
    assert(runtimeRoot.preferredVerticalBarBehavior==0);
    // Validate both ABIs before mutating the first method.
    Class bad=TCLChromeBadRoot.class;
    IMP wrong=imp_implementationWithBlock(^NSInteger(__unused id receiver) { return 5; });
    assert(class_addMethod(bad,@selector(childViewControllerForPreferredVerticalBarBehavior),wrong,"q16@0:8"));
    IMP badBefore=class_getMethodImplementation(bad,@selector(preferredVerticalBarBehavior));
    UIViewController *badRoot=installRoot(bad,YES);TCLCoverChromeRefresh();
    assert(badRoot.notifications==0 && class_getMethodImplementation(bad,@selector(preferredVerticalBarBehavior))==badBefore);
    assert([TCLCoverChromeStatus()[@"chromeRoute"] containsString:@"ABI mismatch"]);
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        setup();
        if (argc>1 && !strcmp(argv[1],"disabled")) disabledTest();else enabledTests();
        puts("root chrome: PASS");
    }
    return 0;
}
