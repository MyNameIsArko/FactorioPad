#import <Foundation/Foundation.h>
#include <stdio.h>

@interface NSWorkspace : NSObject
+ (instancetype)sharedWorkspace;
- (void)activateFileViewerSelectingURLs:(NSArray<NSURL *> *)urls;
@end

@implementation NSWorkspace
+ (instancetype)sharedWorkspace
{
    static NSWorkspace *workspace;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ workspace = [NSWorkspace new]; });
    return workspace;
}

- (void)activateFileViewerSelectingURLs:(NSArray<NSURL *> *)urls
{
    (void)urls;
    // Factorio opens Finder after a crash. iOS uses the app's Share log action.
    fprintf(stderr, "[FactorioPad] macOS file viewer unavailable. Use Share log in FactorioPad.\n");
}
@end
