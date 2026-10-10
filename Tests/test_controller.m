#include "../FactorioCompat/FactorioControllerBridge.m"

static BOOL heldKeys[256];
static BOOL heldMouse[4];
static uint16_t modifierState;
static uint16_t keyDownModifiers[256];
static NSUInteger keyDownCounts[256];
static uint16_t mouseDownModifiers[4];
static NSUInteger mouseDownCounts[4];
static BOOL mouseDownHasCommandOnly;
static CGPoint lastMove, lastClick;
static NSUInteger moveCount;

void FactorioInputPerform(dispatch_block_t operation) { operation(); }

void FactorioKeyboardKeyDown(int32_t scancode, int32_t keycode) {
    heldKeys[scancode] = YES;
    keyDownModifiers[scancode] = modifierState;
    keyDownCounts[scancode]++;
}
void FactorioKeyboardKeyUp(int32_t scancode, int32_t keycode) { heldKeys[scancode] = NO; }
void FactorioKeyboardSetModifierState(uint16_t modifiers) { modifierState = modifiers; }
void FactorioMouseMove(int32_t x, int32_t y, int32_t xrel, int32_t yrel) { lastMove = CGPointMake(x, y); moveCount++; }
void FactorioMouseButton(uint8_t button, bool pressed, int32_t x, int32_t y) {
    heldMouse[button] = pressed;
    lastClick = CGPointMake(x, y);
    if (pressed) {
        mouseDownModifiers[button] = modifierState;
        mouseDownCounts[button]++;
        mouseDownHasCommandOnly = heldKeys[FP_SC_LGUI] && !heldKeys[FP_SC_LCTRL] && !heldKeys[FP_SC_LSHIFT];
    }
}
void FactorioMouseWheel(int32_t x, int32_t y) {}

int main(void)
{
    @autoreleasepool {
        gControllerQueue = dispatch_queue_create("FactorioPad.ControllerTest", DISPATCH_QUEUE_SERIAL);
        GCController *controller = [GCController controllerWithExtendedGamepad];
        gEmulateController = NO;
        FPInstallController(controller);
        NSCAssert(!gCurrentController && !controller.extendedGamepad.buttonA.pressedChangedHandler &&
            !controller.extendedGamepad.leftThumbstick.valueChangedHandler,
            @"native mode must leave the controller to SDL");
        gEmulateController = YES;
        FPInstallController(controller);
        GCExtendedGamepad *pad = controller.extendedGamepad;
        dispatch_sync(gControllerQueue, ^{
            pad.leftThumbstick.valueChangedHandler(pad.leftThumbstick, 1.0f, 1.0f);
            pad.buttonA.pressedChangedHandler(pad.buttonA, 1.0f, YES);
            pad.buttonY.pressedChangedHandler(pad.buttonY, 1.0f, YES);
            pad.rightTrigger.pressedChangedHandler(pad.rightTrigger, 1.0f, YES);
            NSCAssert(heldKeys[FP_SC_W] && heldKeys[FP_SC_D] && keyDownCounts[FP_SC_E] == 1 &&
                heldKeys[FP_SC_SPACE] && heldMouse[FP_MOUSE_LEFT],
                @"controller inputs must reach the guest");
            FPReleaseEverything();
            NSCAssert(!heldKeys[FP_SC_W] && !heldKeys[FP_SC_D] && !heldKeys[FP_SC_SPACE] && !heldMouse[FP_MOUSE_LEFT],
                @"disconnecting or suspending must release movement, actions and mouse buttons");
            GCControllerButtonInput *actionButtons[] = {pad.buttonA, pad.buttonB, pad.buttonX,
                pad.buttonY, pad.buttonOptions};
            const int expectedKeys[5][4] = {
                {FP_SC_E, FP_SC_F, FP_SC_RETURN, FP_SC_RETURN},
                {FP_SC_Q, FP_SC_Z, FP_SC_C, FP_SC_X},
                {FP_SC_R, FP_SC_R, FP_SC_V, FP_SC_Z},
                {FP_SC_SPACE, FP_SC_SPACE, FP_SC_LALT, FP_SC_Y},
                {FP_SC_M, FP_SC_T, FP_SC_P, FP_SC_B}
            };
            const uint16_t expectedMods[5][4] = {
                {0, 0, 0, 0},
                {0, 0, FP_MOD_LCTRL, FP_MOD_LCTRL},
                {0, FP_MOD_LSHIFT, FP_MOD_LCTRL, FP_MOD_LCTRL},
                {0, FP_MOD_LSHIFT, 0, FP_MOD_LCTRL},
                {0, 0, 0, 0}
            };
            for (NSUInteger combination = 0; combination < 4; combination++) {
                if (combination & 1) pad.leftShoulder.pressedChangedHandler(pad.leftShoulder, 1, YES);
                if (combination & 2) pad.rightShoulder.pressedChangedHandler(pad.rightShoulder, 1, YES);
                for (NSUInteger action = 0; action < 5; action++) {
                    GCControllerButtonInput *button = actionButtons[action];
                    int scancode = expectedKeys[action][combination];
                    NSUInteger count = keyDownCounts[scancode];
                    button.pressedChangedHandler(button, 1, YES);
                    NSCAssert(keyDownCounts[scancode] == count + 1 &&
                        keyDownModifiers[scancode] == expectedMods[action][combination],
                        @"each controller chord must send the Factorio default shortcut");
                    button.pressedChangedHandler(button, 0, NO);
                    NSCAssert(!heldKeys[scancode] && modifierState ==
                        ((combination & 1 ? FP_MOD_LSHIFT : 0) | (combination & 2 ? FP_MOD_LCTRL : 0)),
                        @"button release must restore the held shoulder modifiers");
                }
                if (combination & 1) pad.leftShoulder.pressedChangedHandler(pad.leftShoulder, 0, NO);
                if (combination & 2) pad.rightShoulder.pressedChangedHandler(pad.rightShoulder, 0, NO);
            }
            pad.leftShoulder.pressedChangedHandler(pad.leftShoulder, 1, YES);
            pad.buttonB.pressedChangedHandler(pad.buttonB, 1, YES);
            NSCAssert(heldKeys[FP_SC_Z] && modifierState == 0 && !heldKeys[FP_SC_LSHIFT],
                @"LB + B must hold drop-item without Shift");
            pad.buttonB.pressedChangedHandler(pad.buttonB, 0, NO);
            NSCAssert(!heldKeys[FP_SC_Z] && modifierState == FP_MOD_LSHIFT && heldKeys[FP_SC_LSHIFT],
                @"releasing B must stop dropping and restore LB");
            pad.leftShoulder.pressedChangedHandler(pad.leftShoulder, 0, NO);
            pad.leftShoulder.pressedChangedHandler(pad.leftShoulder, 1, YES);
            pad.buttonA.pressedChangedHandler(pad.buttonA, 1, YES);
            pad.rightShoulder.pressedChangedHandler(pad.rightShoulder, 1, YES);
            NSCAssert(heldKeys[FP_SC_F] && modifierState == 0 && !heldKeys[FP_SC_LCTRL],
                @"pickup must stay held without shoulder modifiers even if RB changes");
            pad.buttonA.pressedChangedHandler(pad.buttonA, 0, NO);
            NSCAssert(!heldKeys[FP_SC_F] && modifierState == (FP_MOD_LSHIFT | FP_MOD_LCTRL),
                @"pickup release must restore both shoulders");
            FPReleaseEverything();
            pad.leftShoulder.pressedChangedHandler(pad.leftShoulder, 1, YES);
            pad.dpad.up.pressedChangedHandler(pad.dpad.up, 1, YES);
            NSCAssert(heldKeys[FP_SC_1] && keyDownModifiers[FP_SC_1] == FP_MOD_LSHIFT,
                @"LB + D-pad must still select quickbar pages");
            pad.rightShoulder.pressedChangedHandler(pad.rightShoulder, 1, YES);
            pad.dpad.up.pressedChangedHandler(pad.dpad.up, 0, NO);
            NSCAssert(!heldKeys[FP_SC_1], @"changing modifiers before release must not leave a number held");
            FPReleaseEverything();
            pad.rightShoulder.pressedChangedHandler(pad.rightShoulder, 1, YES);
            NSArray<GCControllerButtonInput *> *directions = @[pad.dpad.up, pad.dpad.right, pad.dpad.down, pad.dpad.left];
            const int shortcuts[] = {FP_SC_LGUI, FP_SC_C, FP_SC_D, FP_SC_U};
            const uint16_t shortcutModifiers[] = {FP_MOD_LGUI, 0, FP_MOD_LALT, FP_MOD_LALT};
            NSUInteger filterClicks = mouseDownCounts[FP_MOUSE_RIGHT];
            for (NSUInteger index = 0; index < directions.count; index++) {
                int scancode = shortcuts[index];
                NSUInteger count = keyDownCounts[scancode];
                directions[index].pressedChangedHandler(directions[index], 1, YES);
                NSCAssert(keyDownCounts[scancode] == count + 1 && !heldKeys[scancode] &&
                    keyDownModifiers[scancode] == shortcutModifiers[index],
                    @"RB + D-pad must send filter, next weapon and planner shortcuts");
                NSCAssert(modifierState == FP_MOD_LCTRL && heldKeys[FP_SC_LCTRL],
                    @"shortcuts must restore RB for later controller actions");
                directions[index].pressedChangedHandler(directions[index], 0, NO);
            }
            NSCAssert(mouseDownCounts[FP_MOUSE_RIGHT] == filterClicks + 1 &&
                mouseDownModifiers[FP_MOUSE_RIGHT] == FP_MOD_LGUI && mouseDownHasCommandOnly &&
                !heldMouse[FP_MOUSE_RIGHT] && !heldKeys[FP_SC_LGUI] &&
                CGPointEqualToPoint(lastClick, CGPointMake(llround(gCursorX), llround(gCursorY))),
                @"clearing a slot must send Command + right-click at the cursor and release Command");
            pad.leftShoulder.pressedChangedHandler(pad.leftShoulder, 1, YES);
            pad.dpad.up.pressedChangedHandler(pad.dpad.up, 1, YES);
            pad.dpad.up.pressedChangedHandler(pad.dpad.up, 0, NO);
            NSCAssert(mouseDownHasCommandOnly && heldKeys[FP_SC_LSHIFT] && heldKeys[FP_SC_LCTRL] &&
                modifierState == (FP_MOD_LSHIFT | FP_MOD_LCTRL),
                @"filtering must temporarily release and then restore both held shoulders");
            pad.leftShoulder.pressedChangedHandler(pad.leftShoulder, 0, NO);
            pad.leftTrigger.pressedChangedHandler(pad.leftTrigger, 1, YES);
            filterClicks = mouseDownCounts[FP_MOUSE_RIGHT];
            pad.dpad.up.pressedChangedHandler(pad.dpad.up, 1, YES);
            pad.dpad.up.pressedChangedHandler(pad.dpad.up, 0, NO);
            NSCAssert(heldMouse[FP_MOUSE_RIGHT] && mouseDownCounts[FP_MOUSE_RIGHT] == filterClicks &&
                modifierState == FP_MOD_LCTRL, @"filtering must not interrupt a held LT action");
            pad.leftTrigger.pressedChangedHandler(pad.leftTrigger, 0, NO);
            pad.leftThumbstick.valueChangedHandler(pad.leftThumbstick, 1, 0);
            pad.dpad.down.pressedChangedHandler(pad.dpad.down, 1, YES);
            NSCAssert(gD && heldKeys[FP_SC_D] && keyDownModifiers[FP_SC_D] == FP_MOD_LCTRL,
                @"the planner shortcut must resume rightward movement without Alt");
            pad.rightShoulder.pressedChangedHandler(pad.rightShoulder, 0, NO);
            pad.dpad.down.pressedChangedHandler(pad.dpad.down, 0, NO);
            NSCAssert(heldKeys[FP_SC_D] && !heldKeys[FP_SC_3],
                @"releasing RB before the D-pad must not release movement or leave a number held");
            FPReleaseEverything();
            NSCAssert(CGPointEqualToPoint(FPStickCurve(0.05, -0.05), CGPointZero) &&
                CGPointEqualToPoint(FPStickCurve(0.1, 0), CGPointZero),
                @"the cursor must ignore stick drift");
            CGPoint diagonal = FPStickCurve(0.5, -0.1);
            NSCAssert(diagonal.x > 0 && fabs(diagonal.y / diagonal.x + 0.2) < 1e-9,
                @"the radial curve must preserve direction, including small diagonal corrections");
            NSCAssert(FPStickCurve(0.08, 0.08).x > 0,
                @"the deadzone must use radial distance, not separate axis thresholds");
            CGPoint fullTilt = FPStickCurve(M_SQRT1_2, M_SQRT1_2);
            CGPoint corner = FPStickCurve(-1, -1);
            NSCAssert(FPStickCurve(1, 0).x == 1 && FPStickCurve(-1, 0).x == -1 &&
                fabs(hypot(fullTilt.x, fullTilt.y) - 1) < 1e-9 &&
                fabs(hypot(corner.x, corner.y) - 1) < 1e-9,
                @"full speed must be unchanged and capped equally in every direction");
            NSCAssert(fabs(FPStickCurve(0.4, 0).x * 700 - 44.90502094) < 1e-6,
                @"gentle stick input must use the slower precision curve");

            gCursorX = 100;
            gCursorY = 100.75;
            pad.rightThumbstick.valueChangedHandler(pad.rightThumbstick, 0.25f, 0);
            gLastCursorTime = CACurrentMediaTime() - 0.01;
            FPCursorTick();
            NSCAssert(gCursorX > 100 && moveCount == 0, @"subpixel movement must not jump a whole point");
            for (int tick = 0; tick < 60; tick++) {
                gLastCursorTime = CACurrentMediaTime() - 0.01;
                FPCursorTick();
            }
            NSCAssert(moveCount > 0 && lastMove.x > 100, @"small movements must accumulate instead of disappearing");
            pad.rightThumbstick.valueChangedHandler(pad.rightThumbstick, 0, 0);
            double stoppedX = gCursorX;
            FPCursorTick();
            NSCAssert(gCursorX == stoppedX, @"releasing the stick must stop immediately");
            pad.rightTrigger.pressedChangedHandler(pad.rightTrigger, 1, YES);
            NSCAssert(CGPointEqualToPoint(lastClick, lastMove), @"left clicks must use the rounded motion coordinates");
            pad.leftTrigger.pressedChangedHandler(pad.leftTrigger, 1, YES);
            NSCAssert(CGPointEqualToPoint(lastClick, lastMove), @"right clicks must use the rounded motion coordinates");
            FPReleaseEverything();
            NSCAssert(CGPointEqualToPoint(lastClick, lastMove), @"mouse releases must use the rounded motion coordinates");
        });
        puts("Factorio controller tests passed.");
    }
    return 0;
}
