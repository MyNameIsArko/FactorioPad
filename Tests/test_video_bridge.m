#include "../FactorioCompat/FactorioVideoBridge.m"
#import <CoreFoundation/CoreFoundation.h>

static int device;
static int creations;
static BOOL finished;

static void *createDevice(void)
{
    NSCAssert(NSThread.isMainThread, @"SDL 3 must create its Cocoa video driver on the main thread");
    creations++;
    return &device;
}

// Export the same symbols as the SDL 3 guest, using the real dlsym boundary.
void SDL_GetPrimaryDisplay(void) {}
FPVideoBootstrap COCOA_bootstrap = {"cocoa", "SDL Cocoa video driver", createDevice};

int main(void)
{
    @autoreleasepool {
        NSCAssert([[[FactorioAppearance new] name] containsString:@"Dark"],
            @"SDL's theme query must match FactorioPad's dark interface");
        NSCAssert(FactorioVideoBridgeSetGuestHandle(NULL), @"older guests must remain supported");
        void *guest = dlopen(NULL, RTLD_NOW);
        COCOA_bootstrap.name = "unexpected";
        NSCAssert(!FactorioVideoBridgeSetGuestHandle(guest) && COCOA_bootstrap.create == createDevice,
            @"unexpected bootstrap layouts must not be modified");
        COCOA_bootstrap.name = "cocoa";
        NSCAssert(FactorioVideoBridgeSetGuestHandle(guest), @"SDL 3 bootstrap must resolve");
        NSCAssert(FactorioVideoBridgeSetGuestHandle(guest), @"repeated setup must not wrap the adapter again");
        NSCAssert(COCOA_bootstrap.create() == &device, @"main-thread creation must not dispatch synchronously to itself");
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSCAssert(!NSThread.isMainThread, @"exercise the game worker thread");
            NSCAssert(COCOA_bootstrap.create() == &device, @"the worker must receive the real video device");
            dispatch_async(dispatch_get_main_queue(), ^{ finished = YES; });
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!finished && deadline.timeIntervalSinceNow > 0) {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
        }
        NSCAssert(finished && creations == 2, @"video creation must finish without a deadlock or duplicate calls");
        puts("Factorio video bridge tests passed.");
    }
    return 0;
}
