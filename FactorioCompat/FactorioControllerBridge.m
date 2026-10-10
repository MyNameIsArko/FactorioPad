#import "FactorioControllerBridge.h"
#import "FactorioKeyboardBridge.h"

#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>

#include <math.h>


enum {
    FP_SC_A = 4,
    FP_SC_B = 5,
    FP_SC_C = 6,
    FP_SC_D = 7,
    FP_SC_E = 8,
    FP_SC_F = 9,
    FP_SC_M = 16,
    FP_SC_P = 19,
    FP_SC_Q = 20,
    FP_SC_R = 21,
    FP_SC_S = 22,
    FP_SC_T = 23,
    FP_SC_U = 24,
    FP_SC_V = 25,
    FP_SC_W = 26,
    FP_SC_X = 27,
    FP_SC_Y = 28,
    FP_SC_Z = 29,

    FP_SC_1 = 30,
    FP_SC_2 = 31,
    FP_SC_3 = 32,
    FP_SC_4 = 33,

    FP_SC_ESCAPE = 41,
    FP_SC_RETURN = 40,
    FP_SC_SPACE = 44,

    FP_SC_LCTRL = 224,
    FP_SC_LSHIFT = 225,
    FP_SC_LALT = 226,
    FP_SC_LGUI = 227
};

enum {
    FP_MOD_LSHIFT = 0x0001,
    FP_MOD_LCTRL = 0x0040,
    FP_MOD_LALT = 0x0100,
    FP_MOD_LGUI = 0x0400,

    FP_MOUSE_LEFT = 1,
    FP_MOUSE_RIGHT = 3
};


static dispatch_queue_t
    gControllerQueue;

static dispatch_source_t
    gCursorTimer;


static BOOL gActive = YES;
static BOOL gEmulateController = YES;
static GCController *gCurrentController = nil;

static CGFloat gWidth = 1133.0;
static CGFloat gHeight = 744.0;

static double gCursorX = 566.5;
static double gCursorY = 372.0;

static float gRightX = 0.0f;
static float gRightY = 0.0f;

static CFTimeInterval
    gLastCursorTime = 0.0;


static BOOL gW = NO;
static BOOL gA = NO;
static BOOL gS = NO;
static BOOL gD = NO;

static BOOL gShift = NO;
static BOOL gCtrl = NO;
static uint16_t gEmittedModifiers = 0;
static BOOL gRightMousePressed = NO;

typedef struct {
    int scancode;
    int keycode;
    uint16_t modifiers;
    BOOL hold;
} FPShortcut;

typedef struct {
    BOOL pressed;
    FPShortcut shortcut;
    unsigned long sequence;
} FPActionState;

enum { FP_ACTION_A, FP_ACTION_B, FP_ACTION_X, FP_ACTION_Y, FP_ACTION_VIEW, FP_ACTION_COUNT };
static FPActionState gActions[FP_ACTION_COUNT];
static unsigned long gActionSequence = 0;

#define FP_SHORTCUT(sc, key, mod, held) {sc, key, mod, held}
static const FPShortcut gActionShortcuts[FP_ACTION_COUNT][4] = {
    {FP_SHORTCUT(FP_SC_E, 'e', 0, NO), FP_SHORTCUT(FP_SC_F, 'f', 0, YES),
     FP_SHORTCUT(FP_SC_RETURN, '\r', 0, NO), FP_SHORTCUT(FP_SC_RETURN, '\r', 0, NO)},
    {FP_SHORTCUT(FP_SC_Q, 'q', 0, NO), FP_SHORTCUT(FP_SC_Z, 'z', 0, YES),
     FP_SHORTCUT(FP_SC_C, 'c', FP_MOD_LCTRL, NO), FP_SHORTCUT(FP_SC_X, 'x', FP_MOD_LCTRL, NO)},
    {FP_SHORTCUT(FP_SC_R, 'r', 0, NO), FP_SHORTCUT(FP_SC_R, 'r', FP_MOD_LSHIFT, NO),
     FP_SHORTCUT(FP_SC_V, 'v', FP_MOD_LCTRL, NO), FP_SHORTCUT(FP_SC_Z, 'z', FP_MOD_LCTRL, NO)},
    {FP_SHORTCUT(FP_SC_SPACE, ' ', 0, YES), FP_SHORTCUT(FP_SC_SPACE, ' ', FP_MOD_LSHIFT, YES),
     FP_SHORTCUT(FP_SC_LALT, 0x40000000 | FP_SC_LALT, 0, NO),
     FP_SHORTCUT(FP_SC_Y, 'y', FP_MOD_LCTRL, NO)},
    {FP_SHORTCUT(FP_SC_M, 'm', 0, NO), FP_SHORTCUT(FP_SC_T, 't', 0, NO),
     FP_SHORTCUT(FP_SC_P, 'p', 0, NO), FP_SHORTCUT(FP_SC_B, 'b', 0, NO)}
};
#undef FP_SHORTCUT

static const void *gControllerQueueKey =
    &gControllerQueueKey;

static uint16_t
FPCurrentModifiers(void)
{
    uint16_t result = 0;

    if (gShift) {
        result |= FP_MOD_LSHIFT;
    }

    if (gCtrl) {
        result |= FP_MOD_LCTRL;
    }

    return result;
}


static void
FPSetEmittedModifiers(uint16_t modifiers)
{
    const int scancodes[] = {FP_SC_LSHIFT, FP_SC_LCTRL, FP_SC_LALT};
    const uint16_t bits[] = {FP_MOD_LSHIFT, FP_MOD_LCTRL, FP_MOD_LALT};
    FactorioKeyboardSetModifierState(modifiers);
    for (NSUInteger index = 0; index < 3; index++) {
        if ((gEmittedModifiers & bits[index]) && !(modifiers & bits[index])) {
            FactorioKeyboardKeyUp(scancodes[index], 0x40000000 | scancodes[index]);
        }
    }
    for (NSUInteger index = 0; index < 3; index++) {
        if (!(gEmittedModifiers & bits[index]) && (modifiers & bits[index])) {
            FactorioKeyboardKeyDown(scancodes[index], 0x40000000 | scancodes[index]);
        }
    }
    gEmittedModifiers = modifiers;
}

static void
FPRefreshModifiers(void)
{
    FPActionState *latest = NULL;
    for (NSUInteger index = 0; index < FP_ACTION_COUNT; index++) {
        FPActionState *action = &gActions[index];
        if (action->pressed && action->shortcut.hold &&
            (!latest || action->sequence > latest->sequence)) latest = action;
    }
    FPSetEmittedModifiers(latest ? latest->shortcut.modifiers : FPCurrentModifiers());
}


static void
FPSetKey(
    BOOL *storage,
    BOOL pressed,
    int scancode,
    int keycode
)
{
    if (*storage == pressed) {
        return;
    }

    *storage = pressed;

    if (pressed) {
        FactorioKeyboardKeyDown(
            scancode,
            keycode
        );
    } else {
        FactorioKeyboardKeyUp(
            scancode,
            keycode
        );
    }
}


static void
FPTapKeyState(
    BOOL pressed,
    int scancode,
    int keycode
)
{
    if (pressed) {
        FactorioKeyboardKeyDown(
            scancode,
            keycode
        );
    } else {
        FactorioKeyboardKeyUp(
            scancode,
            keycode
        );
    }
}

static void
FPTapShortcutKey(int scancode, int keycode)
{
    BOOL resumeMovement = scancode == FP_SC_D && gD;
    if (resumeMovement) FPTapKeyState(NO, FP_SC_D, 'd');
    FPTapKeyState(YES, scancode, keycode);
    FPTapKeyState(NO, scancode, keycode);
    if (resumeMovement) {
        FPRefreshModifiers();
        FPTapKeyState(YES, FP_SC_D, 'd');
    }
}

static void
FPBindActionButton(GCControllerButtonInput *button, NSUInteger index)
{
    button.pressedChangedHandler = ^(GCControllerButtonInput *input, float value, BOOL pressed) {
        if (!gActive) return;
        FactorioInputPerform(^{
            FPActionState *action = &gActions[index];
            if (action->pressed == pressed) return;
            if (pressed) {
                action->shortcut = gActionShortcuts[index][(gCtrl ? 2 : 0) | (gShift ? 1 : 0)];
                action->pressed = YES;
                action->sequence = ++gActionSequence;
                if (action->shortcut.hold) {
                    FPRefreshModifiers();
                    FPTapKeyState(YES, action->shortcut.scancode, action->shortcut.keycode);
                } else {
                    FPSetEmittedModifiers(action->shortcut.modifiers);
                    FPTapShortcutKey(action->shortcut.scancode, action->shortcut.keycode);
                    FPRefreshModifiers();
                }
            } else {
                if (action->shortcut.hold)
                    FPTapKeyState(NO, action->shortcut.scancode, action->shortcut.keycode);
                action->pressed = NO;
                FPRefreshModifiers();
            }
        });
    };
}

static void
FPBindDPad(
    GCControllerButtonInput *button,
    int numberScancode,
    int numberKeycode,
    uint16_t shortcutModifiers,
    void (^shortcut)(void)
)
{
    button.pressedChangedHandler = ^(GCControllerButtonInput *input, float value, BOOL pressed) {
        if (!gActive) return;
        if (pressed && gCtrl) {
            FactorioInputPerform(^{
                uint16_t restore = gEmittedModifiers;
                FPSetEmittedModifiers(shortcutModifiers);
                shortcut();
                FPSetEmittedModifiers(restore);
            });
        } else {
            // Always release the number, even if RB changed while it was held.
            FPTapKeyState(pressed, numberScancode, numberKeycode);
        }
    };
}


static void
FPReleaseMovement(void)
{
    FPSetKey(
        &gW,
        NO,
        FP_SC_W,
        'w'
    );

    FPSetKey(
        &gA,
        NO,
        FP_SC_A,
        'a'
    );

    FPSetKey(
        &gS,
        NO,
        FP_SC_S,
        's'
    );

    FPSetKey(
        &gD,
        NO,
        FP_SC_D,
        'd'
    );
}


static void
FPReleaseModifiers(void)
{
    gShift = NO;
    gCtrl = NO;
    FPSetEmittedModifiers(0);
}


static void
FPReleaseEverything(void)
{
    FactorioInputPerform(^{
        FPReleaseMovement();
        for (NSUInteger index = 0; index < FP_ACTION_COUNT; index++) {
            FPActionState *action = &gActions[index];
            if (action->pressed && action->shortcut.hold)
                FPTapKeyState(NO, action->shortcut.scancode, action->shortcut.keycode);
            action->pressed = NO;
        }
        FPReleaseModifiers();

        // Release actions too: a disconnected pad cannot send their key-up events.
        const int scancodes[] = {FP_SC_1, FP_SC_2, FP_SC_3, FP_SC_4, FP_SC_ESCAPE};
        const int keycodes[] = {'1', '2', '3', '4', 27};
        for (NSUInteger index = 0; index < sizeof(scancodes) / sizeof(scancodes[0]); index++) {
            FactorioKeyboardKeyUp(scancodes[index], keycodes[index]);
        }

        gRightX = 0.0f;
        gRightY = 0.0f;
        gRightMousePressed = NO;

        /*
         * Release both mouse buttons as a precaution.
         */
        FactorioMouseButton(
            FP_MOUSE_LEFT,
            false,
            (int32_t)llround(gCursorX),
            (int32_t)llround(gCursorY)
        );

        FactorioMouseButton(
            FP_MOUSE_RIGHT,
            false,
            (int32_t)llround(gCursorX),
            (int32_t)llround(gCursorY)
        );
    });
}


static CGPoint
FPStickCurve(
    double x,
    double y
)
{
    const double deadzone = 0.10;
    const double exponent = 2.5;
    double magnitude = hypot(x, y);

    if (magnitude <= deadzone) {
        return CGPointZero;
    }

    // Preserve direction, with slow fine adjustments and unchanged full-stick speed.
    double speed = pow((fmin(magnitude, 1.0) - deadzone) / (1.0 - deadzone), exponent);
    return CGPointMake(x / magnitude * speed, y / magnitude * speed);
}


static void
FPCursorTick(void)
{
    if (!gActive) {
        return;
    }

    CFTimeInterval now =
        CACurrentMediaTime();

    if (gLastCursorTime == 0.0) {
        gLastCursorTime = now;
        return;
    }

    double dt =
        now - gLastCursorTime;

    gLastCursorTime = now;

    /*
     * Prevent a large cursor jump after suspension.
     */
    if (dt > 0.1) {
        dt = 0.1;
    }


    CGPoint velocity = FPStickCurve(gRightX, gRightY);
    double x = velocity.x;
    double y = velocity.y;

    if (x == 0.0 &&
        y == 0.0) {

        return;
    }


    const double speed =
    700.0;


    double oldX =
        gCursorX;

    double oldY =
        gCursorY;


    gCursorX +=
        x * speed * dt;

    /*
     * GameController:
     * +Y = up
     *
     * UIKit/SDL:
     * +Y = down
     */
    gCursorY -=
        y * speed * dt;


    gCursorX =
        fmax(
            0.0,
            fmin(
                gCursorX,
                MAX(
                    gWidth - 1.0,
                    0.0
                )
            )
        );

    gCursorY =
        fmax(
            0.0,
            fmin(
                gCursorY,
                MAX(
                    gHeight - 1.0,
                    0.0
                )
            )
        );


    int newX =
        (int)llround(
            gCursorX
        );

    int newY =
        (int)llround(
            gCursorY
        );

    int oldXi =
        (int)llround(
            oldX
        );

    int oldYi =
        (int)llround(
            oldY
        );


    if (newX == oldXi &&
        newY == oldYi) {

        return;
    }


    FactorioMouseMove(
        newX,
        newY,
        newX - oldXi,
        newY - oldYi
    );
}


static void
FPInstallController(
    GCController *controller
)
{
    GCExtendedGamepad *pad =
        controller.extendedGamepad;

    if (!gEmulateController || !pad || gCurrentController) {
        return;
    }
    gCurrentController = controller;

    controller.handlerQueue =
        gControllerQueue;


    // ---------------------------------------------------------
    // Left stick -> WASD
    // ---------------------------------------------------------

    pad.leftThumbstick.valueChangedHandler =
    ^(
        GCControllerDirectionPad *dpad,
        float x,
        float y
    ) {

        if (!gActive) {
            return;
        }

        const float threshold =
            0.35f;

        FPSetKey(
            &gW,
            y > threshold,
            FP_SC_W,
            'w'
        );

        FPSetKey(
            &gS,
            y < -threshold,
            FP_SC_S,
            's'
        );

        FPSetKey(
            &gA,
            x < -threshold,
            FP_SC_A,
            'a'
        );

        FPSetKey(
            &gD,
            x > threshold,
            FP_SC_D,
            'd'
        );
    };


    // ---------------------------------------------------------
    // Right stick -> mouse velocity
    // ---------------------------------------------------------

    pad.rightThumbstick.valueChangedHandler =
    ^(
        GCControllerDirectionPad *dpad,
        float x,
        float y
    ) {

        gRightX = x;
        gRightY = y;
    };


    // ---------------------------------------------------------
    // Triggers -> mouse
    // ---------------------------------------------------------

    pad.rightTrigger.pressedChangedHandler =
    ^(
        GCControllerButtonInput *button,
        float value,
        BOOL pressed
    ) {

        if (!gActive) {
            return;
        }

        FactorioMouseButton(
            FP_MOUSE_LEFT,
            pressed,
            (int32_t)llround(gCursorX),
            (int32_t)llround(gCursorY)
        );
    };


    pad.leftTrigger.pressedChangedHandler =
    ^(
        GCControllerButtonInput *button,
        float value,
        BOOL pressed
    ) {

        if (!gActive) {
            return;
        }

        gRightMousePressed = pressed;
        FactorioMouseButton(
            FP_MOUSE_RIGHT,
            pressed,
            (int32_t)llround(gCursorX),
            (int32_t)llround(gCursorY)
        );
    };


    // ---------------------------------------------------------
    // LB -> Shift
    // ---------------------------------------------------------

    pad.leftShoulder.pressedChangedHandler =
    ^(
        GCControllerButtonInput *button,
        float value,
        BOOL pressed
    ) {

        if (!gActive) {
            return;
        }

        if (gShift == pressed) {
            return;
        }

        FactorioInputPerform(^{
            gShift = pressed;
            FPRefreshModifiers();
        });
    };


    // ---------------------------------------------------------
    // RB -> Ctrl
    // ---------------------------------------------------------

    pad.rightShoulder.pressedChangedHandler =
    ^(
        GCControllerButtonInput *button,
        float value,
        BOOL pressed
    ) {

        if (!gActive) {
            return;
        }

        if (gCtrl == pressed) {
            return;
        }

        FactorioInputPerform(^{
            gCtrl = pressed;
            FPRefreshModifiers();
        });
    };


#define FP_BIND_BUTTON(button, scancode, keycode) \
    button.pressedChangedHandler = ^( \
        GCControllerButtonInput *b, \
        float value, \
        BOOL pressed \
    ) { \
        if (!gActive) return; \
        FPTapKeyState( \
            pressed, \
            scancode, \
            keycode \
        ); \
    }


    FPBindActionButton(pad.buttonA, FP_ACTION_A);
    FPBindActionButton(pad.buttonB, FP_ACTION_B);
    FPBindActionButton(pad.buttonX, FP_ACTION_X);
    FPBindActionButton(pad.buttonY, FP_ACTION_Y);


    // ---------------------------------------------------------
    // D-pad -> slots; LB -> pages; RB -> filter, weapon and planners.
    // ---------------------------------------------------------

    FPBindDPad(
        pad.dpad.up,
        FP_SC_1,
        '1', FP_MOD_LGUI, ^{
            // ponytail: ignore filter while LT is held; restore its click if simultaneous input is needed.
            if (gRightMousePressed) return;
            // Command uses a separate modifier key from the shoulder shortcuts.
            FactorioKeyboardSetModifierState(FP_MOD_LGUI);
            FPTapKeyState(YES, FP_SC_LGUI, 0x40000000 | FP_SC_LGUI);
            FactorioMouseButton(FP_MOUSE_RIGHT, YES, (int32_t)llround(gCursorX), (int32_t)llround(gCursorY));
            FactorioMouseButton(FP_MOUSE_RIGHT, NO, (int32_t)llround(gCursorX), (int32_t)llround(gCursorY));
            FPTapKeyState(NO, FP_SC_LGUI, 0x40000000 | FP_SC_LGUI);
        }
    );

    FPBindDPad(
        pad.dpad.right,
        FP_SC_2,
        '2', 0, ^{ FPTapShortcutKey(FP_SC_C, 'c'); }
    );

    FPBindDPad(
        pad.dpad.down,
        FP_SC_3,
        '3', FP_MOD_LALT, ^{ FPTapShortcutKey(FP_SC_D, 'd'); }
    );

    FPBindDPad(
        pad.dpad.left,
        FP_SC_4,
        '4', FP_MOD_LALT, ^{ FPTapShortcutKey(FP_SC_U, 'u'); }
    );


    // ---------------------------------------------------------
    // View / Menu
    // ---------------------------------------------------------

    if (pad.buttonOptions) {
        FPBindActionButton(pad.buttonOptions, FP_ACTION_VIEW);
    }

    if (pad.buttonMenu) {

        FP_BIND_BUTTON(
            pad.buttonMenu,
            FP_SC_ESCAPE,
            27
        );
    }


    // ---------------------------------------------------------
    // Stick clicks -> wheel
    // ---------------------------------------------------------

    if (pad.leftThumbstickButton) {

        pad.leftThumbstickButton
            .pressedChangedHandler =
        ^(
            GCControllerButtonInput *button,
            float value,
            BOOL pressed
        ) {

            if (gActive &&
                pressed) {

                FactorioMouseWheel(
                    0,
                    -1
                );
            }
        };
    }


    if (pad.rightThumbstickButton) {

        pad.rightThumbstickButton
            .pressedChangedHandler =
        ^(
            GCControllerButtonInput *button,
            float value,
            BOOL pressed
        ) {

            if (gActive &&
                pressed) {

                FactorioMouseWheel(
                    0,
                    1
                );
            }
        };
    }


#undef FP_BIND_BUTTON
}


void
FactorioControllerBridgeStart(BOOL emulateController)
{
    static dispatch_once_t onceToken;

    dispatch_once(
        &onceToken,
        ^{

        gEmulateController = emulateController;
        gControllerQueue =
            dispatch_queue_create(
                "FactorioPad.ControllerBridge",
                DISPATCH_QUEUE_SERIAL
            );

        dispatch_queue_set_specific(
            gControllerQueue,
            gControllerQueueKey,
            (void *)gControllerQueueKey,
            NULL
        );

        gLastCursorTime =
            CACurrentMediaTime();


        /*
         * Existing controllers.
         */
        for (
            GCController *controller
            in GCController.controllers
        ) {

            FPInstallController(
                controller
            );
        }


        /*
         * Hot-plug.
         */
        [
            NSNotificationCenter.defaultCenter
            addObserverForName:
                GCControllerDidConnectNotification
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:^(
                NSNotification *notification
            ) {

                GCController *controller =
                    notification.object;

                if (!controller) {
                    return;
                }

                FPInstallController(
                    controller
                );
            }
        ];


        [NSNotificationCenter.defaultCenter
            addObserverForName:GCControllerDidDisconnectNotification
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:^(NSNotification *notification) {
                GCController *controller = notification.object;
                if (controller != gCurrentController) {
                    return;
                }
                for (GCControllerButtonInput *button in controller.physicalInputProfile.buttons.allValues) {
                    button.pressedChangedHandler = nil;
                }
                for (GCControllerDirectionPad *dpad in controller.physicalInputProfile.dpads.allValues) {
                    dpad.valueChangedHandler = nil;
                    dpad.up.pressedChangedHandler = nil;
                    dpad.down.pressedChangedHandler = nil;
                    dpad.left.pressedChangedHandler = nil;
                    dpad.right.pressedChangedHandler = nil;
                }
                dispatch_sync(gControllerQueue, ^{ FPReleaseEverything(); });
                gCurrentController = nil;
                for (GCController *replacement in GCController.controllers) {
                    FPInstallController(replacement);
                }
            }];


        /*
         * 60 Hz cursor loop.
         */
        gCursorTimer =
            dispatch_source_create(
                DISPATCH_SOURCE_TYPE_TIMER,
                0,
                0,
                gControllerQueue
            );

        dispatch_source_set_timer(
            gCursorTimer,
            DISPATCH_TIME_NOW,
            NSEC_PER_SEC / 60,
            NSEC_PER_SEC / 600
        );

        dispatch_source_set_event_handler(
            gCursorTimer,
            ^{

            FPCursorTick();
        });

        dispatch_resume(
            gCursorTimer
        );
    });
}


void
FactorioControllerBridgeSetActive(
    BOOL active
)
{
    /*
     * Lifecycle events can arrive before the Factorio guest starts
     * and before FactorioControllerBridgeStart() creates the queue.
     */
    if (!gControllerQueue) {
        gActive = active;
        return;
    }

    dispatch_async(
        gControllerQueue,
        ^{

        if (gActive == active) {
            return;
        }

        gActive = active;

        if (!active) {
            FPReleaseEverything();
        } else {
            gLastCursorTime =
                CACurrentMediaTime();
        }
    });
}


void
FactorioControllerBridgeSetViewportSize(
    CGFloat width,
    CGFloat height
)
{
    if (!gControllerQueue) {
        return;
    }

    dispatch_async(
        gControllerQueue,
        ^{

        gWidth =
            MAX(
                width,
                1.0
            );

        gHeight =
            MAX(
                height,
                1.0
            );

        gCursorX =
            fmax(
                0.0,
                fmin(
                    gCursorX,
                    gWidth - 1.0
                )
            );

        gCursorY =
            fmax(
                0.0,
                fmin(
                    gCursorY,
                    gHeight - 1.0
                )
            );
    });
}


void
FactorioControllerBridgeSetCursorPosition(
    CGFloat x,
    CGFloat y
)
{
    if (!gControllerQueue) {
        return;
    }

    dispatch_async(
        gControllerQueue,
        ^{

        gCursorX = x;
        gCursorY = y;
    });
}

CGPoint
FactorioControllerBridgeGetCursorPosition(void)
{
    if (!gControllerQueue) {
        return CGPointMake(
            gCursorX,
            gCursorY
        );
    }

    /*
     * If the getter runs on the controller queue,
     * do not dispatch_sync to that same queue.
     */
    if (dispatch_get_specific(
            gControllerQueueKey
        )) {

        return CGPointMake(
            gCursorX,
            gCursorY
        );
    }

    __block CGPoint result;

    dispatch_sync(
        gControllerQueue,
        ^{

        result =
            CGPointMake(
                gCursorX,
                gCursorY
            );
    });

    return result;
}
