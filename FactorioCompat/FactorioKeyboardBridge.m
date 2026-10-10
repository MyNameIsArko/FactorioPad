#import "FactorioKeyboardBridge.h"

#import <dlfcn.h>
#import <stdint.h>
#import <string.h>


// ============================================================
// Minimal SDL2 ABI
// ============================================================

typedef uint8_t  FPUint8;
typedef uint16_t FPUint16;
typedef uint32_t FPUint32;
typedef int32_t  FPSint32;


enum {
    FP_SDL_KEYDOWN   = 0x300,
    FP_SDL_KEYUP     = 0x301,
    FP_SDL_TEXTINPUT = 0x303,

    FP_SDL_RELEASED = 0,
    FP_SDL_PRESSED  = 1,

    FP_SDL_SCANCODE_RETURN    = 40,
    FP_SDL_SCANCODE_ESCAPE    = 41,
    FP_SDL_SCANCODE_BACKSPACE = 42,
    FP_SDL_SCANCODE_TAB       = 43,

    FP_SDL_MOUSEMOTION     = 0x400,
    FP_SDL_MOUSEBUTTONDOWN = 0x401,
    FP_SDL_MOUSEBUTTONUP   = 0x402,
    FP_SDL_MOUSEWHEEL      = 0x403,

    FP_SDL_BUTTON_LEFT  = 1,
    FP_SDL_BUTTON_RIGHT = 3,

    FP_KMOD_LSHIFT = 0x0001,
    FP_KMOD_LCTRL  = 0x0040
};

enum {
    FP_SDL_SCANCODE_A = 4,

    FP_KMOD_LGUI = 0x0400
};

typedef struct {
    FPSint32 scancode;
    FPSint32 sym;
    FPUint16 mod;
    FPUint16 padding;
    FPUint32 unused;
} FPSDLKeysym;


typedef struct {
    FPUint32 type;
    FPUint32 timestamp;
    FPUint32 windowID;

    FPUint8 state;
    FPUint8 repeat;
    FPUint8 padding2;
    FPUint8 padding3;

    FPSDLKeysym keysym;
} FPSDLKeyboardEvent;


typedef struct {
    FPUint32 type;
    FPUint32 timestamp;
    FPUint32 windowID;

    char text[32];
} FPSDLTextInputEvent;

typedef struct {
    FPUint32 type;
    FPUint32 timestamp;
    FPUint32 windowID;
    FPUint32 which;
    FPUint32 state;

    FPSint32 x;
    FPSint32 y;
    FPSint32 xrel;
    FPSint32 yrel;
} FPSDLMouseMotionEvent;


typedef struct {
    FPUint32 type;
    FPUint32 timestamp;
    FPUint32 windowID;
    FPUint32 which;

    FPUint8 button;
    FPUint8 state;
    FPUint8 clicks;
    FPUint8 padding1;

    FPSint32 x;
    FPSint32 y;
} FPSDLMouseButtonEvent;


typedef struct {
    FPUint32 type;
    FPUint32 timestamp;
    FPUint32 windowID;
    FPUint32 which;

    FPSint32 x;
    FPSint32 y;

    FPUint32 direction;

    float preciseX;
    float preciseY;

    FPSint32 mouseX;
    FPSint32 mouseY;
} FPSDLMouseWheelEvent;

typedef union {
    FPUint32 type;

    FPSDLKeyboardEvent key;
    FPSDLTextInputEvent text;

    FPSDLMouseMotionEvent motion;
    FPSDLMouseButtonEvent button;
    FPSDLMouseWheelEvent wheel;

    FPUint8 padding[56];
} FPSDLEvent;

typedef int (*FPSDLSendKeyboardKeyFn)(
    FPUint8 state,
    FPSint32 scancode
);

typedef void (*FPSDLSetModStateFn)(
    FPUint16 modstate
);

// ============================================================
// SDL functions from FactorioGuest
// ============================================================

typedef int (*FPSDLPushEventFn)(
    FPSDLEvent *event
);

typedef void *(*FPSDLGetKeyboardFocusFn)(void);

typedef FPUint32 (*FPSDLGetWindowIDFn)(
    void *window
);

typedef FPUint32 (*FPSDLGetTicksFn)(void);


static FPSDLPushEventFn
    gPushEvent = NULL;

static FPSDLGetKeyboardFocusFn
    gGetKeyboardFocus = NULL;

static FPSDLGetWindowIDFn
    gGetWindowID = NULL;

static FPSDLGetTicksFn
    gGetTicks = NULL;

static FPSDLSendKeyboardKeyFn
    gSendKeyboardKey = NULL;

static FPSDLSetModStateFn
    gSetModState = NULL;

static void (*gSetKeyboardFocus)(void *window);
static void *(*gGetWindowFromID)(uint32_t windowID);
static void (*gLockJoysticks)(void);
static void (*gUnlockJoysticks)(void);
static int (*gNumJoysticks)(void);
static int32_t (*gJoystickGetDeviceInstanceID)(int index);
static void *(*gJoystickFromInstanceID)(int32_t instanceID);
static void (*gRecenterJoystick)(void *joystick);
static int (*gSetHintWithPriority)(const char *name, const char *value, int priority);
static uint32_t gSuspendedWindowID;

static FPUint16
    gSyntheticModifiers = 0;

static FPUint16
    gPhysicalModifiers = 0;

static FPUint32
    gSyntheticMouseButtons = 0;

enum { FP_KEY_SYNTHETIC = 1, FP_KEY_PHYSICAL = 2, FP_KEY_COUNT = 512 };
static FPUint8 gKeySources[FP_KEY_COUNT];

static NSObject *FPInputLock(void)
{
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lock = [NSObject new]; });
    return lock;
}

void FactorioInputPerform(dispatch_block_t operation)
{
    @synchronized (FPInputLock()) { operation(); }
}

// ============================================================
// Helpers
// ============================================================

static FPUint32
FPKeyboardTimestamp(void)
{
    if (gGetTicks) {
        return gGetTicks();
    }

    return 0;
}


static FPUint32
FPKeyboardWindowID(void)
{
    if (!gGetKeyboardFocus ||
        !gGetWindowID) {

        return 0;
    }

    void *window =
        gGetKeyboardFocus();

    if (!window) {
        return 0;
    }

    return gGetWindowID(window);
}

static void
FPPushUTF8Chunk(
    const char *bytes,
    size_t length
)
{
    if (!gPushEvent ||
        !bytes ||
        length == 0 ||
        length > 31) {

        return;
    }

    FPSDLEvent event;
    memset(
        &event,
        0,
        sizeof(event)
    );

    event.text.type =
        FP_SDL_TEXTINPUT;

    event.text.timestamp =
        FPKeyboardTimestamp();

    event.text.windowID =
        FPKeyboardWindowID();

    memcpy(
        event.text.text,
        bytes,
        length
    );

    event.text.text[length] = '\0';

    gPushEvent(&event);
}


// ============================================================
// Public
// ============================================================

BOOL
FactorioKeyboardBridgeSetGuestHandle(
    void *handle,
    BOOL nativeController
)
{
    @synchronized (FPInputLock()) {
        gPushEvent =
            (FPSDLPushEventFn)
            (handle ? dlsym(
                handle,
                "SDL_PushEvent"
            ) : NULL);

        gGetKeyboardFocus =
            (FPSDLGetKeyboardFocusFn)
            (handle ? dlsym(
                handle,
                "SDL_GetKeyboardFocus"
            ) : NULL);

        gGetWindowID =
            (FPSDLGetWindowIDFn)
            (handle ? dlsym(
                handle,
                "SDL_GetWindowID"
            ) : NULL);

        gGetTicks =
            (FPSDLGetTicksFn)
            (handle ? dlsym(
                handle,
                "SDL_GetTicks"
            ) : NULL);

        gSendKeyboardKey =
            (FPSDLSendKeyboardKeyFn)
            (handle ? dlsym(
                handle,
                "SDL_SendKeyboardKey"
            ) : NULL);

        gSetModState =
            (FPSDLSetModStateFn)
            (handle ? dlsym(
                handle,
                "SDL_SetModState"
            ) : NULL);
        void *nativeHandle = nativeController ? handle : NULL;
        gSetKeyboardFocus = nativeHandle ? dlsym(nativeHandle, "SDL_SetKeyboardFocus") : NULL;
        gGetWindowFromID = nativeHandle ? dlsym(nativeHandle, "SDL_GetWindowFromID") : NULL;
        gLockJoysticks = nativeHandle ? dlsym(nativeHandle, "SDL_LockJoysticks") : NULL;
        gUnlockJoysticks = nativeHandle ? dlsym(nativeHandle, "SDL_UnlockJoysticks") : NULL;
        gNumJoysticks = nativeHandle ? dlsym(nativeHandle, "SDL_NumJoysticks") : NULL;
        gJoystickGetDeviceInstanceID = nativeHandle ? dlsym(nativeHandle, "SDL_JoystickGetDeviceInstanceID") : NULL;
        gJoystickFromInstanceID = nativeHandle ? dlsym(nativeHandle, "SDL_JoystickFromInstanceID") : NULL;
        gRecenterJoystick = nativeHandle ? dlsym(nativeHandle, "SDL_PrivateJoystickForceRecentering") : NULL;
        gSetHintWithPriority = nativeHandle ? dlsym(nativeHandle, "SDL_SetHintWithPriority") : NULL;
        BOOL nativeReady = gSetKeyboardFocus && gGetWindowFromID && gLockJoysticks && gUnlockJoysticks &&
            gNumJoysticks && gJoystickGetDeviceInstanceID && gJoystickFromInstanceID && gRecenterJoystick && gSetHintWithPriority;
        BOOL ready = gPushEvent && gGetKeyboardFocus && gGetWindowID && gGetTicks && gSendKeyboardKey && gSetModState &&
            (!nativeController || nativeReady);
        if (ready && nativeController) {
            // Focus loss must block native input even if Factorio requests background events.
            ready = gSetHintWithPriority("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "0", 2) != 0;
        }
        if (!ready) {
            // Do not leave a partially initialized bridge available to other input sources.
            gPushEvent = NULL;
            gSendKeyboardKey = NULL;
            gSetModState = NULL;
            gSetKeyboardFocus = NULL;
            if (handle) NSLog(@"[FactorioPad] The guest is missing required SDL input functions.");
        }
        gSuspendedWindowID = 0;
        gSyntheticModifiers = 0;
        gPhysicalModifiers = 0;
        gSyntheticMouseButtons = 0;
        memset(gKeySources, 0, sizeof(gKeySources));
        return ready;
    }
}

void FactorioInputSetActive(BOOL active)
{
    @synchronized (FPInputLock()) {
        if (!gSetKeyboardFocus || (active && !gSuspendedWindowID)) return;
        gLockJoysticks();
        if (!active) {
            void *window = gGetKeyboardFocus();
            if (window) {
                gSuspendedWindowID = gGetWindowID(window);
                gSetKeyboardFocus(NULL);
                // Focus loss blocks new presses; recentering also releases controls already held.
                int count = gNumJoysticks();
                for (int index = 0; index < count; index++) {
                    void *joystick = gJoystickFromInstanceID(gJoystickGetDeviceInstanceID(index));
                    if (joystick) gRecenterJoystick(joystick);
                }
            }
        } else {
            void *window = gGetWindowFromID(gSuspendedWindowID);
            gSuspendedWindowID = 0;
            if (window && !gGetKeyboardFocus()) gSetKeyboardFocus(window);
        }
        gUnlockJoysticks();
    }
}



void
FactorioKeyboardInsertText(
    NSString *text
)
{
    @synchronized (FPInputLock()) {
        if (!text ||
            text.length == 0 ||
            !gPushEvent) {

            return;
        }

        NSData *data =
            [text
                dataUsingEncoding:NSUTF8StringEncoding];

        if (!data ||
            data.length == 0) {

            return;
        }

        const uint8_t *bytes =
            data.bytes;

        size_t length =
            data.length;

        size_t offset = 0;


        /*
         * SDL_TextInputEvent has text[32],
         * which holds up to 31 UTF-8 bytes plus NUL.
         *
         * Do not split a UTF-8 character.
         */
        while (offset < length) {

            size_t remaining =
                length - offset;

            size_t chunk =
                remaining < 31
                    ? remaining
                    : 31;

            if (offset + chunk < length) {

                while (
                    chunk > 0 &&
                    (bytes[offset + chunk] & 0xC0) == 0x80
                ) {
                    --chunk;
                }
            }

            if (chunk == 0) {
                return;
            }

            FPPushUTF8Chunk(
                (const char *)(bytes + offset),
                chunk
            );

            offset += chunk;
        }
    }
}


static void
FPPushKeyWithMod(
    FPSint32 scancode,
    FPSint32 keycode,
    FPUint16 mod
)
{
    if (!gPushEvent) {
        return;
    }

    FPUint32 windowID =
        FPKeyboardWindowID();

    FPSDLEvent event;
    memset(&event, 0, sizeof(event));

    // DOWN
    event.key.type = FP_SDL_KEYDOWN;
    event.key.timestamp = FPKeyboardTimestamp();
    event.key.windowID = windowID;
    event.key.state = FP_SDL_PRESSED;
    event.key.repeat = 0;

    event.key.keysym.scancode = scancode;
    event.key.keysym.sym = keycode;
    event.key.keysym.mod = mod;

    gPushEvent(&event);


    // UP
    memset(&event, 0, sizeof(event));

    event.key.type = FP_SDL_KEYUP;
    event.key.timestamp = FPKeyboardTimestamp();
    event.key.windowID = windowID;
    event.key.state = FP_SDL_RELEASED;

    event.key.keysym.scancode = scancode;
    event.key.keysym.sym = keycode;
    event.key.keysym.mod = mod;

    gPushEvent(&event);
}

static void
FPPushKey(
    FPSint32 scancode,
    FPSint32 keycode
)
{
    FPPushKeyWithMod(
        scancode,
        keycode,
        0
    );
}


void
FactorioKeyboardBackspace(void)
{
    @synchronized (FPInputLock()) {
        FPPushKey(
            FP_SDL_SCANCODE_BACKSPACE,
            '\b'
        );
    }
}



void
FactorioKeyboardReturn(void)
{
    @synchronized (FPInputLock()) {
        FPPushKey(
            FP_SDL_SCANCODE_RETURN,
            '\r'
        );
    }
}



void
FactorioKeyboardTab(void)
{
    @synchronized (FPInputLock()) {
        FPPushKey(
            FP_SDL_SCANCODE_TAB,
            '\t'
        );
    }
}


void
FactorioKeyboardSetModifierState(
    uint16_t modifiers
)
{
    @synchronized (FPInputLock()) {
        gSyntheticModifiers =
            modifiers;

        if (gSetModState) {
            gSetModState(
                gSyntheticModifiers | gPhysicalModifiers
            );
        }
    }
}

void
FactorioKeyboardSetPhysicalModifierState(uint16_t modifiers)
{
    @synchronized (FPInputLock()) {
        gPhysicalModifiers = modifiers;
        if (gSetModState) gSetModState(gSyntheticModifiers | gPhysicalModifiers);
    }
}



static void
FPPushKeyboardState(
    FPSint32 scancode,
    FPSint32 keycode,
    FPUint8 state
)
{
    /*
     * Prefer the internal SDL path,
     * because it also updates SDL_GetKeyboardState().
     */
    if (gSendKeyboardKey) {

        if (gSetModState) {
            gSetModState(
                gSyntheticModifiers | gPhysicalModifiers
            );
        }

        gSendKeyboardKey(
            state,
            scancode
        );

        return;
    }


    /*
     * Fallback.
     */
    if (!gPushEvent) {
        return;
    }

    FPSDLEvent event;
    memset(
        &event,
        0,
        sizeof(event)
    );

    event.key.type =
        state == FP_SDL_PRESSED
            ? FP_SDL_KEYDOWN
            : FP_SDL_KEYUP;

    event.key.timestamp =
        FPKeyboardTimestamp();

    event.key.windowID =
        FPKeyboardWindowID();

    event.key.state =
        state;

    event.key.repeat = 0;

    event.key.keysym.scancode =
        scancode;

    event.key.keysym.sym =
        keycode;

    event.key.keysym.mod =
        gSyntheticModifiers | gPhysicalModifiers;

    gPushEvent(
        &event
    );
}


static void
FPSetKeySource(int32_t scancode, int32_t keycode, FPUint8 source, FPUint8 state)
{
    if (scancode < 0 || scancode >= FP_KEY_COUNT) return;
    FPUint8 previous = gKeySources[scancode];
    if (state == FP_SDL_PRESSED) {
        if (previous & source) return;
        gKeySources[scancode] = previous | source;
        if (!previous) FPPushKeyboardState(scancode, keycode, state);
    } else {
        if (!(previous & source)) return;
        gKeySources[scancode] = previous & ~source;
        if (!gKeySources[scancode]) FPPushKeyboardState(scancode, keycode, state);
    }
}

void FactorioKeyboardKeyDown(int32_t scancode, int32_t keycode)
{
    @synchronized (FPInputLock()) { FPSetKeySource(scancode, keycode, FP_KEY_SYNTHETIC, FP_SDL_PRESSED); }
}

void FactorioKeyboardKeyUp(int32_t scancode, int32_t keycode)
{
    @synchronized (FPInputLock()) { FPSetKeySource(scancode, keycode, FP_KEY_SYNTHETIC, FP_SDL_RELEASED); }
}

void FactorioKeyboardPhysicalKeyDown(int32_t scancode, int32_t keycode)
{
    @synchronized (FPInputLock()) { FPSetKeySource(scancode, keycode, FP_KEY_PHYSICAL, FP_SDL_PRESSED); }
}

void FactorioKeyboardPhysicalKeyUp(int32_t scancode, int32_t keycode)
{
    @synchronized (FPInputLock()) { FPSetKeySource(scancode, keycode, FP_KEY_PHYSICAL, FP_SDL_RELEASED); }
}



void
FactorioMouseMove(
    int32_t x,
    int32_t y,
    int32_t xrel,
    int32_t yrel
)
{
    @synchronized (FPInputLock()) {
        if (!gPushEvent) {
            return;
        }

        FPSDLEvent event;
        memset(
            &event,
            0,
            sizeof(event)
        );

        event.motion.type =
            FP_SDL_MOUSEMOTION;

        event.motion.timestamp =
            FPKeyboardTimestamp();

        event.motion.windowID =
            FPKeyboardWindowID();

        event.motion.which = 0;

        event.motion.state =
            gSyntheticMouseButtons;

        event.motion.x = x;
        event.motion.y = y;
        event.motion.xrel = xrel;
        event.motion.yrel = yrel;

        gPushEvent(
            &event
        );
    }
}



void
FactorioMouseButton(
    uint8_t button,
    bool pressed,
    int32_t x,
    int32_t y
)
{
    @synchronized (FPInputLock()) {
        if (button < 1 || button > 32) return;
        if (!gPushEvent) {
            return;
        }

        if (pressed) {
            gSyntheticMouseButtons |=
                (1u << (button - 1));
        } else {
            gSyntheticMouseButtons &=
                ~(1u << (button - 1));
        }

        FPSDLEvent event;
        memset(
            &event,
            0,
            sizeof(event)
        );

        event.button.type =
            pressed
                ? FP_SDL_MOUSEBUTTONDOWN
                : FP_SDL_MOUSEBUTTONUP;

        event.button.timestamp =
            FPKeyboardTimestamp();

        event.button.windowID =
            FPKeyboardWindowID();

        event.button.which = 0;
        event.button.button = button;

        event.button.state =
            pressed
                ? FP_SDL_PRESSED
                : FP_SDL_RELEASED;

        event.button.clicks = 1;

        event.button.x = x;
        event.button.y = y;

        gPushEvent(
            &event
        );
    }
}



void
FactorioMouseWheel(
    int32_t x,
    int32_t y
)
{
    @synchronized (FPInputLock()) {
        if (!gPushEvent) {
            return;
        }

        FPSDLEvent event;
        memset(
            &event,
            0,
            sizeof(event)
        );

        event.wheel.type =
            FP_SDL_MOUSEWHEEL;

        event.wheel.timestamp =
            FPKeyboardTimestamp();

        event.wheel.windowID =
            FPKeyboardWindowID();

        event.wheel.which = 0;

        event.wheel.x = x;
        event.wheel.y = y;

        event.wheel.direction = 0;

        event.wheel.preciseX =
            (float)x;

        event.wheel.preciseY =
            (float)y;

        gPushEvent(
            &event
        );
    }
}
