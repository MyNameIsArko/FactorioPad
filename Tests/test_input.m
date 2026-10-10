#include "../FactorioCompat/FactorioKeyboardBridge.m"
#include "../FactorioCompat/FactorioControllerBridge.m"

// Capture only the SDL boundary. The controller and input bridge are production code.
static NSMutableArray<NSData *> *events;
static uint16_t sdlModifiers;
static int window;
static void *keyboardFocus = &window;
static BOOL windowExists = YES;
static int joystick;
static BOOL nativeButtonHeld;
static float nativeAxis;
static int joystickLockDepth, recenterCount, focusChanges;
static BOOL acceptsBackgroundHint = YES;

int SDL_PushEvent(FPSDLEvent *event)
{
    [events addObject:[NSData dataWithBytes:event length:sizeof(*event)]];
    return 1;
}
void *SDL_GetKeyboardFocus(void) { return keyboardFocus; }
uint32_t SDL_GetWindowID(void *value) { NSCAssert(value == &window, @"window must match"); return 77; }
uint32_t SDL_GetTicks(void) { return 42; }
void SDL_SetKeyboardFocus(void *value) {
    NSCAssert(joystickLockDepth == 1, @"focus changes must hold SDL's joystick lock");
    keyboardFocus = value;
    focusChanges++;
}
void *SDL_GetWindowFromID(uint32_t windowID) { return windowID == 77 && windowExists ? &window : NULL; }
void SDL_LockJoysticks(void) { joystickLockDepth++; }
void SDL_UnlockJoysticks(void) { NSCAssert(joystickLockDepth == 1, @"joystick locks must balance"); joystickLockDepth--; }
int SDL_NumJoysticks(void) { return 2; }
int32_t SDL_JoystickGetDeviceInstanceID(int index) { return 100 + index; }
void *SDL_JoystickFromInstanceID(int32_t instanceID) { return instanceID == 100 ? &joystick : NULL; }
void SDL_PrivateJoystickForceRecentering(void *value) {
    NSCAssert(value == &joystick && joystickLockDepth == 1 && !keyboardFocus,
        @"release held controls under SDL's lock after focus loss");
    nativeButtonHeld = NO;
    nativeAxis = 0;
    recenterCount++;
}
int SDL_SetHintWithPriority(const char *name, const char *value, int priority) {
    NSCAssert(strcmp(name, "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS") == 0 && strcmp(value, "0") == 0 && priority == 2,
        @"native input must respect focus even if the game enables background events");
    return acceptsBackgroundHint;
}
void SDL_SetModState(uint16_t modifiers) { sdlModifiers = modifiers; }
int SDL_SendKeyboardKey(uint8_t state, int32_t scancode)
{
    uint16_t modifier = scancode == 224 ? FP_MOD_LCTRL : scancode == 225 ? FP_MOD_LSHIFT : scancode == 227 ? FP_MOD_LGUI : 0;
    if (state) sdlModifiers |= modifier; else sdlModifiers &= ~modifier;
    FPSDLEvent event = {0};
    event.key.type = state ? FP_SDL_KEYDOWN : FP_SDL_KEYUP;
    event.key.windowID = 77;
    event.key.timestamp = 42;
    event.key.state = state;
    event.key.keysym.scancode = scancode;
    event.key.keysym.mod = sdlModifiers;
    return SDL_PushEvent(&event);
}

int main(void)
{
    @autoreleasepool {
        events = [NSMutableArray array];
        void *fixture = dlopen(NULL, RTLD_NOW);
        NSCAssert(FactorioKeyboardBridgeSetGuestHandle(fixture, NO), @"all SDL functions must resolve through dlsym");
        FactorioInputSetActive(NO);
        NSCAssert(keyboardFocus == &window && !gSetKeyboardFocus && !focusChanges,
            @"mapped mode must keep its existing focus behavior");
        gControllerQueue = dispatch_queue_create("FactorioPad.InputTest", DISPATCH_QUEUE_SERIAL);
        GCController *controller = [GCController controllerWithExtendedGamepad];
        FPInstallController(controller);
        GCExtendedGamepad *pad = controller.extendedGamepad;
        dispatch_sync(gControllerQueue, ^{
            pad.rightShoulder.pressedChangedHandler(pad.rightShoulder, 1, YES);
            [events removeAllObjects];
            pad.dpad.up.pressedChangedHandler(pad.dpad.up, 1, YES);
            pad.dpad.up.pressedChangedHandler(pad.dpad.up, 0, NO);
            NSCAssert(events.count == 6, @"filter must send six shortcut events");
            FPSDLEvent click;
            [events[2] getBytes:&click length:sizeof(click)];
            NSCAssert(click.type == FP_SDL_MOUSEBUTTONDOWN && click.button.button == FP_MOUSE_RIGHT &&
                click.button.windowID == 77 && click.button.timestamp == 42 &&
                click.button.x == llround(gCursorX) && click.button.y == llround(gCursorY),
                @"controller clicks must reach the real bridge with correct SDL fields");
            [events removeAllObjects];
            pad.dpad.right.pressedChangedHandler(pad.dpad.right, 1, YES);
            FPSDLEvent weapon;
            [events[1] getBytes:&weapon length:sizeof(weapon)];
            NSCAssert(weapon.key.keysym.scancode == FP_SC_C && weapon.key.keysym.mod == 0 &&
                sdlModifiers == FP_MOD_LCTRL, @"next weapon must restore the held shoulder");
        });

        [events removeAllObjects];
        dispatch_group_t group = dispatch_group_create();
        dispatch_group_async(group, gControllerQueue, ^{
            @autoreleasepool {
                for (int index = 0; index < 1000; index++) {
                    pad.dpad.up.pressedChangedHandler(pad.dpad.up, 1, YES);
                    pad.dpad.up.pressedChangedHandler(pad.dpad.up, 0, NO);
                }
            }
        });
        dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                for (int index = 0; index < 1000; index++) {
                    FactorioKeyboardInsertText(@"Factory é");
                    FactorioKeyboardBackspace();
                    FactorioKeyboardReturn();
                }
            }
        });
        NSCAssert(dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0,
            @"concurrent input must finish without a deadlock");
        BOOL commandHeld = NO;
        NSUInteger textCount = 0, clickCount = 0;
        for (NSUInteger index = 0; index < events.count; index++) {
            FPSDLEvent event;
            [events[index] getBytes:&event length:sizeof(event)];
            if (event.type == FP_SDL_KEYDOWN && event.key.keysym.scancode == FP_SC_LGUI) commandHeld = YES;
            if (event.type == FP_SDL_KEYUP && event.key.keysym.scancode == FP_SC_LGUI) commandHeld = NO;
            if (event.type == FP_SDL_MOUSEBUTTONDOWN) {
                NSCAssert(commandHeld, @"filter clicks must stay inside their Command transaction");
                clickCount++;
            }
            if (event.type == FP_SDL_TEXTINPUT) {
                NSCAssert(!commandHeld && strcmp(event.text.text, "Factory é") == 0,
                    @"text must not interrupt a controller shortcut or become corrupted");
                textCount++;
            }
            if (event.type == FP_SDL_KEYDOWN &&
                (event.key.keysym.scancode == 40 || event.key.keysym.scancode == 42)) {
                NSCAssert(!commandHeld && index + 1 < events.count, @"typing keys must stay outside shortcuts");
                FPSDLEvent release;
                [events[index + 1] getBytes:&release length:sizeof(release)];
                NSCAssert(release.type == FP_SDL_KEYUP && release.key.keysym.scancode == event.key.keysym.scancode,
                    @"a typing key press and release must not be interleaved");
            }
        }
        NSCAssert(!commandHeld && textCount == 1000 && clickCount == 1000, @"no concurrent input may be lost");
        dispatch_sync(gControllerQueue, ^{ FPReleaseEverything(); });
        FactorioInputPerform(^{ NSCAssert(gSyntheticModifiers == 0 && gSyntheticMouseButtons == 0,
            @"suspension must leave no held modifiers or mouse buttons"); });
        [events removeAllObjects];
        FactorioKeyboardPhysicalKeyDown(FP_SC_W, 0);
        dispatch_sync(gControllerQueue, ^{
            pad.leftThumbstick.valueChangedHandler(pad.leftThumbstick, 0, 1);
        });
        FactorioKeyboardPhysicalKeyUp(FP_SC_W, 0);
        NSCAssert(events.count == 1 && gKeySources[FP_SC_W] == FP_KEY_SYNTHETIC,
            @"releasing physical W must not stop a held gamepad direction");
        dispatch_sync(gControllerQueue, ^{
            pad.leftThumbstick.valueChangedHandler(pad.leftThumbstick, 0, 0);
        });
        NSCAssert(events.count == 2 && gKeySources[FP_SC_W] == 0,
            @"the last owner must release W");
        [events removeAllObjects];
        dispatch_sync(gControllerQueue, ^{
            pad.leftThumbstick.valueChangedHandler(pad.leftThumbstick, 0, 1);
        });
        FactorioKeyboardPhysicalKeyDown(FP_SC_W, 0);
        dispatch_sync(gControllerQueue, ^{ FPReleaseEverything(); });
        NSCAssert(gKeySources[FP_SC_W] == FP_KEY_PHYSICAL,
            @"disconnecting the gamepad must preserve a physical key");
        FactorioKeyboardPhysicalKeyUp(FP_SC_W, 0);
        NSCAssert(gKeySources[FP_SC_W] == 0, @"releasing the physical key must clear its last owner");
        FactorioKeyboardSetModifierState(FP_MOD_LCTRL);
        FactorioKeyboardSetPhysicalModifierState(FP_MOD_LSHIFT);
        FactorioKeyboardKeyDown(FP_SC_W, 'w');
        NSCAssert(sdlModifiers == (FP_MOD_LCTRL | FP_MOD_LSHIFT),
            @"physical and controller modifiers must coexist");
        FactorioKeyboardSetModifierState(0);
        FactorioKeyboardKeyUp(FP_SC_W, 'w');
        NSCAssert(sdlModifiers == FP_MOD_LSHIFT,
            @"releasing the controller must preserve a held physical modifier");
        FactorioKeyboardSetPhysicalModifierState(0);
        NSUInteger previousCount = events.count;
        FactorioMouseButton(0, YES, 0, 0);
        FactorioMouseButton(33, YES, 0, 0);
        NSCAssert(events.count == previousCount && gSyntheticMouseButtons == 0, @"invalid button numbers must be rejected");
        NSCAssert(FactorioKeyboardBridgeSetGuestHandle(fixture, YES), @"native functions must resolve from the guest");
        nativeButtonHeld = YES;
        nativeAxis = 0.8f;
        FactorioInputSetActive(NO);
        NSCAssert(!keyboardFocus && !nativeButtonHeld && nativeAxis == 0 && recenterCount == 1 && joystickLockDepth == 0,
            @"app screens must remove SDL focus and release held native controls");
        FactorioInputSetActive(NO);
        NSCAssert(recenterCount == 1 && focusChanges == 1, @"repeated suspension must not emit duplicate releases");
        FactorioInputSetActive(YES);
        NSCAssert(keyboardFocus == &window && gSuspendedWindowID == 0 && focusChanges == 2,
            @"closing an app screen must restore the game's focus");
        FactorioInputSetActive(YES);
        NSCAssert(focusChanges == 2, @"repeated resume must not change focus");
        keyboardFocus = NULL;
        FactorioInputSetActive(NO);
        NSCAssert(gSuspendedWindowID == 0, @"suspension before window creation must be harmless");
        keyboardFocus = &window;
        FactorioInputSetActive(NO);
        NSCAssert(!keyboardFocus && recenterCount == 2,
            @"a window created or refocused behind an app screen must also lose input");
        windowExists = NO;
        FactorioInputSetActive(YES);
        NSCAssert(!keyboardFocus && gSuspendedWindowID == 0, @"resume must not use a destroyed SDL window");
        windowExists = YES;
        acceptsBackgroundHint = NO;
        NSCAssert(!FactorioKeyboardBridgeSetGuestHandle(fixture, YES) && !gSetKeyboardFocus && !gPushEvent,
            @"native mode must fail safely if background input cannot be blocked");
        acceptsBackgroundHint = YES;
        void *incompatible = dlopen("/usr/lib/libSystem.B.dylib", RTLD_NOW | RTLD_LOCAL);
        NSCAssert(incompatible && !FactorioKeyboardBridgeSetGuestHandle(incompatible, NO),
            @"an incompatible guest must fail initialization");
        previousCount = events.count;
        FactorioKeyboardReturn();
        FactorioMouseButton(0, YES, 0, 0);
        NSCAssert(events.count == previousCount && !gPushEvent && !gSendKeyboardKey,
            @"failed initialization must disable the bridge");
        dlclose(incompatible);
        dlclose(fixture);
        puts("Factorio input integration tests passed.");
    }
    return 0;
}
