//
//  CoreGraphicsShims.m
//  FactorioCompat
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <stdint.h>
#include <stddef.h>


#ifndef EXPORT
#define EXPORT __attribute__((visibility("default")))
#endif


/*
 * Do not use macOS-only typedefs from Quartz Display Services,
 * because the iPhoneOS SDK does not declare all of them.
 *
 * These types match the arm64 ABI.
 */

typedef uint32_t FPDisplayID;
typedef const void *FPDisplayModeRef;

typedef int32_t  FPCGError;
typedef uint32_t FPBoolean;

typedef float    FPGammaValue;

typedef uint32_t FPFadeReservationToken;
typedef uint32_t FPOpenGLDisplayMask;
typedef int32_t  FPWindowLevel;


/*
 * kCGErrorSuccess
 */
static const FPCGError FP_CG_SUCCESS = 0;


/*
 * One virtual display.
 */
static const FPDisplayID FactorioDisplayID = 1;


/*
 * SDL filters display modes by these flags.
 *
 * kDisplayModeValidFlag = 0x1
 * kDisplayModeSafeFlag  = 0x2
 */
static const uint32_t FactorioDisplayModeFlags =
    0x00000001u |
    0x00000002u;


/*
 * Factorio imports this symbol as a variable from CoreGraphics.
 */
EXPORT
const CFStringRef
kCGDisplayShowDuplicateLowResolutionModes =
    CFSTR("kCGDisplayShowDuplicateLowResolutionModes");



#pragma mark - Screen metrics


typedef struct
{
    CGSize logical;
    CGSize pixels;

    CGFloat scale;

    NSInteger maximumFPS;

} FactorioScreenMetrics;

static UIScreen *
FactorioFindScreenOnMainThread(void)
{
    NSCAssert(
        NSThread.isMainThread,
        @"FactorioFindScreenOnMainThread must run on main thread"
    );

    UIWindowScene *fallbackScene = nil;

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {

        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }

        UIWindowScene *windowScene =
            (UIWindowScene *)scene;

        if (!fallbackScene) {
            fallbackScene = windowScene;
        }

        if (windowScene.activationState ==
            UISceneActivationStateForegroundActive) {

            return windowScene.screen;
        }
    }

    return fallbackScene.screen;
}

static FactorioScreenMetrics
FactorioReadScreenMetricsOnMainThread(void)
{
    UIScreen *screen =
        FactorioFindScreenOnMainThread();

    NSCAssert(
        screen != nil,
        @"No UIWindowScene screen available"
    );

    CGSize logical =
        screen.bounds.size;

    CGSize pixels =
        screen.nativeBounds.size;


    /*
     * This initial port treats the display as landscape,
     * regardless of the current SwiftUI orientation.
     */

    CGFloat logicalWidth =
        MAX(
            logical.width,
            logical.height
        );

    CGFloat logicalHeight =
        MIN(
            logical.width,
            logical.height
        );


    CGFloat pixelWidth =
        MAX(
            pixels.width,
            pixels.height
        );

    CGFloat pixelHeight =
        MIN(
            pixels.width,
            pixels.height
        );


    NSInteger fps =
        screen.maximumFramesPerSecond;

    if (fps <= 0) {
        fps = 60;
    }


    FactorioScreenMetrics result;

    result.logical =
        CGSizeMake(
            logicalWidth,
            logicalHeight
        );

    result.pixels =
        CGSizeMake(
            pixelWidth,
            pixelHeight
        );

    result.scale =
        screen.scale;

    result.maximumFPS =
        fps;


    return result;
}


static FactorioScreenMetrics
FactorioScreenMetricsGet(void)
{
    __block FactorioScreenMetrics result;


    if (NSThread.isMainThread) {

        result =
            FactorioReadScreenMetricsOnMainThread();

    } else {

        /*
         * Factorio main currently runs on a worker thread,
         * but UIScreen is a UIKit API.
         */

        dispatch_sync(
            dispatch_get_main_queue(),
            ^{

                result =
                    FactorioReadScreenMetricsOnMainThread();

            }
        );
    }


    return result;
}



#pragma mark - Fake CGDisplayMode


static CFTypeRef
FactorioFakeDisplayModeObject(void)
{
    static CFTypeRef mode = NULL;

    static dispatch_once_t onceToken;


    dispatch_once(
        &onceToken,
        ^{

            NSDictionary *dictionary = @{

                @"FactorioDisplayMode": @YES,
                @"DisplayID": @(FactorioDisplayID)

            };


            /*
             * Keep one permanent retain.
             */
            mode =
                CFBridgingRetain(
                    dictionary
                );
        }
    );


    return mode;
}



#pragma mark - Display enumeration


EXPORT
FPDisplayID
CGMainDisplayID(void)
{
    return FactorioDisplayID;
}


EXPORT
FPCGError
CGGetOnlineDisplayList(
    uint32_t maxDisplays,
    FPDisplayID *onlineDisplays,
    uint32_t *displayCount
)
{
    if (displayCount) {

        *displayCount = 1;

    }


    if (
        maxDisplays > 0 &&
        onlineDisplays
    ) {

        onlineDisplays[0] =
            FactorioDisplayID;

    }


    return FP_CG_SUCCESS;
}


EXPORT
FPBoolean
CGDisplayIsMain(
    FPDisplayID display
)
{
    return
        display == FactorioDisplayID
        ? 1
        : 0;
}


EXPORT
FPDisplayID
CGDisplayMirrorsDisplay(
    FPDisplayID display
)
{
    (void)display;

    /*
     * kCGNullDirectDisplay
     */
    return 0;
}



#pragma mark - Display geometry


EXPORT
CGRect
CGDisplayBounds(
    FPDisplayID display
)
{
    (void)display;


    FactorioScreenMetrics metrics =
        FactorioScreenMetricsGet();


    return CGRectMake(
        0,
        0,
        metrics.logical.width,
        metrics.logical.height
    );
}


EXPORT
size_t
CGDisplayPixelsWide(
    FPDisplayID display
)
{
    (void)display;

    FactorioScreenMetrics metrics =
        FactorioScreenMetricsGet();

    return
        (size_t)metrics.pixels.width;
}


EXPORT
size_t
CGDisplayPixelsHigh(
    FPDisplayID display
)
{
    (void)display;

    FactorioScreenMetrics metrics =
        FactorioScreenMetricsGet();

    return
        (size_t)metrics.pixels.height;
}


EXPORT
CGSize
CGDisplayScreenSize(
    FPDisplayID display
)
{
    (void)display;


    /*
     * Approximate physical size of an iPad mini in millimeters.
     *
     * SDL needs a reasonable value at this stage,
     * not exact panel calibration.
     */

    return CGSizeMake(
        195.0,
        135.0
    );
}



#pragma mark - Current display mode


EXPORT
FPDisplayModeRef
CGDisplayCopyDisplayMode(
    FPDisplayID display
)
{
    (void)display;


    CFTypeRef mode =
        FactorioFakeDisplayModeObject();


    CFRetain(mode);

    return
        (FPDisplayModeRef)mode;
}


EXPORT
CFArrayRef
CGDisplayCopyAllDisplayModes(
    FPDisplayID display,
    CFDictionaryRef options
)
{
    (void)display;
    (void)options;


    const void *mode =
        FactorioFakeDisplayModeObject();


    CFArrayRef modes =
        CFArrayCreate(
            kCFAllocatorDefault,
            &mode,
            1,
            &kCFTypeArrayCallBacks
        );


    return modes;
}



#pragma mark - Display mode properties


EXPORT
size_t
CGDisplayModeGetWidth(
    FPDisplayModeRef mode
)
{
    (void)mode;


    FactorioScreenMetrics metrics =
        FactorioScreenMetricsGet();


    return
        (size_t)metrics.logical.width;
}


EXPORT
size_t
CGDisplayModeGetHeight(
    FPDisplayModeRef mode
)
{
    (void)mode;


    FactorioScreenMetrics metrics =
        FactorioScreenMetricsGet();


    return
        (size_t)metrics.logical.height;
}


EXPORT
size_t
CGDisplayModeGetPixelWidth(
    FPDisplayModeRef mode
)
{
    (void)mode;


    FactorioScreenMetrics metrics =
        FactorioScreenMetricsGet();


    return
        (size_t)metrics.pixels.width;
}


EXPORT
size_t
CGDisplayModeGetPixelHeight(
    FPDisplayModeRef mode
)
{
    (void)mode;


    FactorioScreenMetrics metrics =
        FactorioScreenMetricsGet();


    return
        (size_t)metrics.pixels.height;
}


EXPORT
double
CGDisplayModeGetRefreshRate(
    FPDisplayModeRef mode
)
{
    (void)mode;


    FactorioScreenMetrics metrics =
        FactorioScreenMetricsGet();


    return
        (double)metrics.maximumFPS;
}


EXPORT
uint32_t
CGDisplayModeGetIOFlags(
    FPDisplayModeRef mode
)
{
    (void)mode;


    /*
     * valid + safe.
     *
     * Do not set:
     * - interlaced
     * - stretched
     * - television
     */

    return
        FactorioDisplayModeFlags;
}


EXPORT
FPBoolean
CGDisplayModeIsUsableForDesktopGUI(
    FPDisplayModeRef mode
)
{
    (void)mode;

    return 1;
}


EXPORT
CFStringRef
CGDisplayModeCopyPixelEncoding(
    FPDisplayModeRef mode
)
{
    (void)mode;

    /*
     * This is the actual value of the macro:
     *
     * #define IO32BitDirectPixels
     * "--------RRRRRRRRGGGGGGGGBBBBBBBB"
     *
     * SDL compares the string value, not the macro name.
     */

    CFStringRef result =
        CFSTR("--------RRRRRRRRGGGGGGGGBBBBBBBB");

    CFRetain(result);

    return result;
}

EXPORT
void
CGDisplayModeRelease(
    FPDisplayModeRef mode
)
{
    if (mode) {

        CFRelease(
            (CFTypeRef)mode
        );

    }
}



#pragma mark - Display mode switching

typedef void (*FPDisplayReconfigurationCallBack)(FPDisplayID display, uint32_t flags, void *userInfo);

// The single virtual display never reconfigures; UIKit owns display changes.
EXPORT FPCGError CGDisplayRegisterReconfigurationCallback(FPDisplayReconfigurationCallBack callback, void *userInfo)
{
    (void)callback;
    (void)userInfo;
    return FP_CG_SUCCESS;
}

EXPORT FPCGError CGDisplayRemoveReconfigurationCallback(FPDisplayReconfigurationCallBack callback, void *userInfo)
{
    (void)callback;
    (void)userInfo;
    return FP_CG_SUCCESS;
}


EXPORT
FPCGError
CGDisplaySetDisplayMode(
    FPDisplayID display,
    FPDisplayModeRef mode,
    CFDictionaryRef options
)
{
    (void)display;
    (void)mode;
    (void)options;


    /*
     * iPadOS controls the physical display mode.
     *
     * Report success to SDL.
     */

    return FP_CG_SUCCESS;
}



#pragma mark - Display capture


EXPORT
FPCGError
CGCaptureAllDisplays(void)
{
    return FP_CG_SUCCESS;
}


EXPORT
FPCGError
CGDisplayCapture(
    FPDisplayID display
)
{
    (void)display;

    return FP_CG_SUCCESS;
}


EXPORT
FPCGError
CGReleaseAllDisplays(void)
{
    return FP_CG_SUCCESS;
}


EXPORT
FPCGError
CGDisplayRelease(
    FPDisplayID display
)
{
    (void)display;

    return FP_CG_SUCCESS;
}



#pragma mark - Cursor


EXPORT
FPCGError
CGAssociateMouseAndMouseCursorPosition(
    FPBoolean connected
)
{
    (void)connected;

    return FP_CG_SUCCESS;
}


EXPORT
FPCGError
CGDisplayMoveCursorToPoint(
    FPDisplayID display,
    CGPoint point
)
{
    (void)display;
    (void)point;

    return FP_CG_SUCCESS;
}


EXPORT
FPCGError
CGWarpMouseCursorPosition(
    CGPoint point
)
{
    (void)point;

    return FP_CG_SUCCESS;
}



#pragma mark - Display fade


EXPORT
FPCGError
CGAcquireDisplayFadeReservation(
    float seconds,
    FPFadeReservationToken *token
)
{
    (void)seconds;


    if (token) {

        *token = 1;

    }


    return FP_CG_SUCCESS;
}


EXPORT
FPCGError
CGReleaseDisplayFadeReservation(
    FPFadeReservationToken token
)
{
    (void)token;

    return FP_CG_SUCCESS;
}


EXPORT
FPCGError
CGDisplayFade(
    FPFadeReservationToken token,
    float duration,
    float startBlend,
    float endBlend,
    float redBlend,
    float greenBlend,
    float blueBlend,
    FPBoolean synchronous
)
{
    (void)token;

    (void)duration;

    (void)startBlend;
    (void)endBlend;

    (void)redBlend;
    (void)greenBlend;
    (void)blueBlend;

    (void)synchronous;


    return FP_CG_SUCCESS;
}



#pragma mark - Gamma


EXPORT
FPCGError
CGGetDisplayTransferByTable(
    FPDisplayID display,
    uint32_t capacity,
    FPGammaValue *redTable,
    FPGammaValue *greenTable,
    FPGammaValue *blueTable,
    uint32_t *sampleCount
)
{
    (void)display;


    if (sampleCount) {

        *sampleCount =
            capacity;

    }


    for (
        uint32_t i = 0;
        i < capacity;
        ++i
    ) {

        float value;


        if (capacity <= 1) {

            value = 1.0f;

        } else {

            value =
                (float)i /
                (float)(capacity - 1);

        }


        if (redTable) {
            redTable[i] = value;
        }

        if (greenTable) {
            greenTable[i] = value;
        }

        if (blueTable) {
            blueTable[i] = value;
        }

    }


    return FP_CG_SUCCESS;
}


EXPORT
FPCGError
CGSetDisplayTransferByTable(
    FPDisplayID display,
    uint32_t tableSize,
    const FPGammaValue *redTable,
    const FPGammaValue *greenTable,
    const FPGammaValue *blueTable
)
{
    (void)display;

    (void)tableSize;

    (void)redTable;
    (void)greenTable;
    (void)blueTable;


    return FP_CG_SUCCESS;
}



#pragma mark - Legacy OpenGL/display helpers


EXPORT
FPOpenGLDisplayMask
CGDisplayIDToOpenGLDisplayMask(
    FPDisplayID display
)
{
    /*
     * One display = the first bit.
     */

    return
        display == FactorioDisplayID
        ? 1u
        : 0u;
}


/*
 * On Darwin, io_service_t is uint32_t/mach_port_t.
 *
 * A real framebuffer service is not needed.
 */
EXPORT
uint32_t
CGDisplayIOServicePort(
    FPDisplayID display
)
{
    (void)display;

    return 0;
}


EXPORT
FPWindowLevel
CGShieldingWindowLevel(void)
{
    return 0;
}
