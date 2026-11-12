#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Engine contract: -1 follows TikTok, 0 forces off, and 1 forces on.
FOUNDATION_EXPORT NSInteger TCLCoverModeValue(NSString *key);
FOUNDATION_EXPORT void TCLCoverSetModeValue(NSString *key, NSInteger value);
FOUNDATION_EXPORT NSString *TCLCoverDiagnostics(void);
FOUNDATION_EXPORT void TCLCoverResetDefaults(void);
// Each entry contains NSString values for key, title, and detail.
FOUNDATION_EXPORT NSArray<NSDictionary<NSString *, NSString *> *> *TCLCoverExperimentEntries(void);

NS_ASSUME_NONNULL_END
