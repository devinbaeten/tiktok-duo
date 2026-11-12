#import <Foundation/Foundation.h>

// Caller validates the supported app build. The enabled choice is fixed at launch.
void TCLCoverChromeStart(BOOL enabled);
void TCLCoverChromeRefresh(void);
NSDictionary<NSString *, NSString *> *TCLCoverChromeStatus(void);
