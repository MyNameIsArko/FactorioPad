#include "../FactorioCompat/WorkspaceShims.m"

int main(void)
{
    @autoreleasepool {
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSCAssert(workspace && workspace == [NSWorkspace sharedWorkspace], @"the guest must receive a shared workspace");
        [workspace activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:@"/tmp/factorio-current.log"]]];
        [workspace activateFileViewerSelectingURLs:@[]];
        puts("Factorio crash file viewer tests passed.");
    }
    return 0;
}
