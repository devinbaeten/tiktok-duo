#import <Foundation/Foundation.h>
#import <mach-o/loader.h>

// Caller has verified the exact TikTok version/build and MusicallyCore UUID.
void TCLCoverNativeStart(const struct mach_header_64 *header, intptr_t slide, int adaptiveMode, int glassMode, int verticalMode);
void TCLCoverNativeRefresh(void);
NSDictionary<NSString *, NSString *> *TCLCoverNativeStatus(void);
