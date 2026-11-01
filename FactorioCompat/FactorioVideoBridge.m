#import "FactorioVideoBridge.h"
#import <dlfcn.h>
#include <string.h>

@implementation FactorioAppearance
- (NSString *)name
{
    return @"NSAppearanceNameDarkAqua";
}
@end

typedef struct {
    const char *name;
    const char *description;
    void *(*create)(void);
} FPVideoBootstrap;

static void *(*FPCreateCocoaDevice)(void);

static void *FPCreateCocoaDeviceOnMainThread(void)
{
    if (NSThread.isMainThread) return FPCreateCocoaDevice();
    __block void *device;
    dispatch_sync(dispatch_get_main_queue(), ^{ device = FPCreateCocoaDevice(); });
    return device;
}

BOOL FactorioVideoBridgeSetGuestHandle(void *handle)
{
    if (!handle || !dlsym(handle, "SDL_GetPrimaryDisplay")) return YES;
    FPVideoBootstrap *bootstrap = dlsym(handle, "COCOA_bootstrap");
    if (!bootstrap || !bootstrap->name || strcmp(bootstrap->name, "cocoa") || !bootstrap->create) return NO;
    if (bootstrap->create == FPCreateCocoaDeviceOnMainThread) return YES;
    FPCreateCocoaDevice = bootstrap->create;
    bootstrap->create = FPCreateCocoaDeviceOnMainThread;
    return YES;
}
