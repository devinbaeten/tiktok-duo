#import <Foundation/Foundation.h>

// Caller verifies the supported app binary before starting. Fixed for this launch.
void TCLCoverShopStart(BOOL enabled);
void TCLCoverShopRefresh(void);
NSDictionary<NSString *, NSString *> *TCLCoverShopStatus(void);
