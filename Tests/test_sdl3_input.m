#include "../FactorioCompat/FactorioKeyboardBridge.m"

static int window;
static uint16_t modifiers;
static bool keys[512];
static NSMutableArray<NSArray *> *keyEvents;
static NSMutableArray<NSString *> *textEvents;
static CGPoint mousePosition, wheel;
static uint32_t mouseButtons;
static int mouseButtonChanges;

uint32_t SDL_GetPrimaryDisplay(void) { return 1; }
void *SDL_GetKeyboardFocus(void) { return &window; }
uint32_t SDL_GetWindowID(void *value) { NSCAssert(value == &window, @"window must match"); return 77; }
void SDL_SetModState(uint16_t value) { modifiers = value; }
bool SDL_SendKeyboardKey(uint64_t timestamp, uint32_t keyboardID, int rawcode, int32_t scancode, bool down)
{
    NSCAssert(!timestamp && !keyboardID && !rawcode, @"SDL 3 keyboard arguments must use the new signature");
    NSCAssert(scancode >= 0 && scancode < 512, @"SDL 3 must receive the actual scancode");
    keys[scancode] = down;
    [keyEvents addObject:@[@(scancode), @(down), @(modifiers)]];
    return true;
}
void SDL_SendKeyboardText(const char *text)
{
    [textEvents addObject:[NSString stringWithUTF8String:text]];
}
void SDL_SendMouseMotion(uint64_t timestamp, void *value, uint32_t mouseID, bool relative, float x, float y)
{
    NSCAssert(!timestamp && value == &window && !mouseID && !relative, @"SDL 3 motion arguments must match");
    mousePosition = CGPointMake(x, y);
}
void SDL_SendMouseButton(uint64_t timestamp, void *value, uint32_t mouseID, uint8_t button, bool down)
{
    NSCAssert(!timestamp && value == &window && !mouseID, @"SDL 3 button arguments must match");
    if (down) mouseButtons |= 1u << (button - 1); else mouseButtons &= ~(1u << (button - 1));
    mouseButtonChanges++;
}
void SDL_SendMouseWheel(uint64_t timestamp, void *value, uint32_t mouseID, float x, float y, int direction)
{
    NSCAssert(!timestamp && value == &window && !mouseID && !direction, @"SDL 3 wheel arguments must match");
    wheel = CGPointMake(x, y);
}

int main(void)
{
    @autoreleasepool {
        keyEvents = [NSMutableArray array];
        textEvents = [NSMutableArray array];
        NSCAssert(FactorioKeyboardBridgeSetGuestHandle(dlopen(NULL, RTLD_NOW), NO), @"SDL 3 functions must resolve");
        NSCAssert(!gPushEvent && !gSendKeyboardKey && !gGetTicks, @"SDL 3 must never use SDL 2 event layouts or signatures");
        FactorioMouseMove(123, 456, 10, -20);
        NSCAssert(CGPointEqualToPoint(mousePosition, CGPointMake(123, 456)), @"touch coordinates must reach SDL as floats");
        FactorioTouchMouseButton(1, true, 200, 300);
        NSCAssert(mouseButtons == 1 && CGPointEqualToPoint(mousePosition, CGPointMake(200, 300)), @"a tap must move before pressing");
        FactorioMouseButton(1, true, 200, 300);
        FactorioTouchMouseButton(1, false, 200, 300);
        NSCAssert(mouseButtons == 1 && mouseButtonChanges == 1, @"touch release must preserve another source's held button");
        FactorioMouseButton(1, false, 200, 300);
        NSCAssert(!mouseButtons && mouseButtonChanges == 2, @"the final source must release the button");
        FactorioMouseWheel(-2, 3);
        NSCAssert(CGPointEqualToPoint(wheel, CGPointMake(-2, 3)), @"scroll direction and amount must survive the SDL 3 call");
        FactorioKeyboardPhysicalKeyDown(26, 'w');
        FactorioKeyboardTouchKeyDown(26, 'w');
        FactorioKeyboardPhysicalKeyUp(26, 'w');
        NSCAssert(keys[26] && keyEvents.count == 1, @"held keys must update SDL 3 state and preserve other sources");
        FactorioKeyboardTouchKeyUp(26, 'w');
        NSCAssert(!keys[26] && keyEvents.count == 2, @"the final key source must release SDL 3 state");
        FactorioKeyboardSetPhysicalModifierState(FP_KMOD_LGUI);
        [keyEvents removeAllObjects];
        FactorioKeyboardTypeKey(@"K");
        NSCAssert(([keyEvents isEqualToArray:@[@[@14, @YES, @(FP_KMOD_LGUI | FP_KMOD_LSHIFT)],
            @[@14, @NO, @(FP_KMOD_LGUI | FP_KMOD_LSHIFT)]]]), @"typing must send the correct key and modifiers");
        NSCAssert(modifiers == FP_KMOD_LGUI && !keys[14], @"typing must restore held modifiers and release the key");
        NSString *unicode = [@"Factory é🏭 " stringByPaddingToLength:200 withString:@"é🏭 " startingAtIndex:0];
        FactorioKeyboardInsertText(unicode);
        NSCAssert(([textEvents isEqualToArray:@[@"K", unicode]]), @"SDL 3 must receive valid UTF-8, including text longer than 31 bytes");
        FactorioKeyboardBackspace();
        FactorioKeyboardReturn();
        FactorioKeyboardTab();
        NSCAssert(!keys[40] && !keys[42] && !keys[43] && keyEvents.count == 8, @"special keys must send presses and releases");
        void *incompatible = dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", RTLD_NOW);
        NSCAssert(incompatible && !FactorioKeyboardBridgeSetGuestHandle(incompatible, NO) && !FPHasInput(),
            @"an incompatible guest must disable all input paths");
        FactorioKeyboardTypeKey(@"x");
        FactorioMouseMove(0, 0, 0, 0);
        NSCAssert(keyEvents.count == 8 && textEvents.count == 2, @"disabled input must not call the previous guest");
        puts("Factorio SDL 3 input tests passed.");
    }
}
