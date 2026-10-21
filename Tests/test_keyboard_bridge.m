#include "../FactorioCompat/FactorioKeyboardBridge.m"

static NSMutableData *receivedText;
static NSMutableArray<NSNumber *> *keyTypes;
static NSMutableArray<NSData *> *events;
static int32_t lastScancode;
static int32_t lastKeycode;

static int captureEvent(FPSDLEvent *event)
{
    [events addObject:[NSData dataWithBytes:event length:sizeof(*event)]];
    if (event->type == FP_SDL_TEXTINPUT) {
        size_t length = strlen(event->text.text);
        NSCAssert(length <= 31, @"SDL text chunks must fit the event buffer");
        NSCAssert([[NSString alloc] initWithBytes:event->text.text length:length encoding:NSUTF8StringEncoding],
            @"SDL text chunks must preserve complete UTF-8 characters");
        [receivedText appendBytes:event->text.text length:length];
    } else {
        [keyTypes addObject:@(event->type)];
        lastScancode = event->key.keysym.scancode;
        lastKeycode = event->key.keysym.sym;
    }
    return 1;
}

static void expectTypedKey(NSString *text, int32_t scancode, int32_t keycode, uint16_t modifiers)
{
    [events removeAllObjects];
    receivedText.length = 0;
    FactorioKeyboardTypeKey(text);
    NSCAssert(events.count == 3, @"a touch key must send one press, one release, and one text event");
    FPSDLEvent down, up, typed;
    [events[0] getBytes:&down length:sizeof(down)];
    [events[1] getBytes:&up length:sizeof(up)];
    [events[2] getBytes:&typed length:sizeof(typed)];
    NSCAssert(down.type == FP_SDL_KEYDOWN && down.key.state == FP_SDL_PRESSED &&
        up.type == FP_SDL_KEYUP && up.key.state == FP_SDL_RELEASED && typed.type == FP_SDL_TEXTINPUT,
        @"shortcut presses and releases must accompany text input");
    NSCAssert(down.key.keysym.scancode == scancode && up.key.keysym.scancode == scancode &&
        down.key.keysym.sym == keycode && up.key.keysym.sym == keycode &&
        down.key.keysym.mod == modifiers && up.key.keysym.mod == modifiers,
        @"touch keys must use the matching physical key and modifiers");
    NSCAssert([receivedText isEqualToData:[text dataUsingEncoding:NSUTF8StringEncoding]],
        @"login text must arrive once with its original case");
}

int main(void)
{
    @autoreleasepool {
        receivedText = [NSMutableData data];
        keyTypes = [NSMutableArray array];
        events = [NSMutableArray array];
        gPushEvent = captureEvent;
        NSString *prefix = [@"a" stringByPaddingToLength:30 withString:@"a" startingAtIndex:0];
        NSString *text = [prefix stringByAppendingString:@"é🏭 Aa0!@#$%^&*()_+-=[]{}\\|;:'\",.<>/?`~ café abcdefghijklmnopqrstuvwxyz"];
        FactorioKeyboardInsertText(text);
        NSCAssert([receivedText isEqualToData:[text dataUsingEncoding:NSUTF8StringEncoding]],
            @"typed characters must reach SDL unchanged");
        FactorioKeyboardBackspace();
        NSCAssert(([keyTypes isEqualToArray:@[@(FP_SDL_KEYDOWN), @(FP_SDL_KEYUP)]]),
            @"Backspace must send both press and release");
        NSCAssert(lastScancode == 42 && lastKeycode == '\b', @"Backspace mapping must be preserved");
        FactorioKeyboardTab();
        NSCAssert(lastScancode == 43 && lastKeycode == '\t', @"Tab must move between fields");
        FactorioKeyboardReturn();
        NSCAssert(lastScancode == 40 && lastKeycode == '\r', @"Return must submit the field");
        expectTypedKey(@"k", 14, 'k', 0);
        expectTypedKey(@"K", 14, 'k', FP_KMOD_LSHIFT);
        expectTypedKey(@"`", 53, '`', 0);
        expectTypedKey(@"~", 53, '`', FP_KMOD_LSHIFT);
        expectTypedKey(@"!", 30, '1', FP_KMOD_LSHIFT);
        expectTypedKey(@"0", 39, '0', 0);
        expectTypedKey(@"?", 56, '/', FP_KMOD_LSHIFT);
        expectTypedKey(@" ", 44, ' ', 0);
        for (unichar character = 32; character <= 126; character++) {
            NSString *key = [NSString stringWithCharacters:&character length:1];
            [events removeAllObjects];
            FactorioKeyboardTypeKey(key);
            NSCAssert(events.count == 3, @"every printable ASCII key must work in the binding picker");
        }
        gSyntheticModifiers = FP_KMOD_LCTRL;
        gPhysicalModifiers = FP_KMOD_LGUI;
        gTouchModifiers = 0x0100;
        expectTypedKey(@"K", 14, 'k', FP_KMOD_LCTRL | FP_KMOD_LGUI | 0x0100 | FP_KMOD_LSHIFT);
        NSCAssert(gSyntheticModifiers == FP_KMOD_LCTRL && gPhysicalModifiers == FP_KMOD_LGUI && gTouchModifiers == 0x0100,
            @"typing must preserve modifiers held by other input sources");
        gSyntheticModifiers = gPhysicalModifiers = gTouchModifiers = 0;
        FactorioKeyboardPhysicalKeyDown(14, 'k');
        [events removeAllObjects];
        FactorioKeyboardTypeKey(@"k");
        NSCAssert(events.count == 1 && gKeySources[14] == FP_KEY_PHYSICAL,
            @"typing must not release an already-held physical key");
        FactorioKeyboardPhysicalKeyUp(14, 'k');
        [events removeAllObjects];
        receivedText.length = 0;
        FactorioKeyboardTypeKey(@"é🏭 €£¥");
        NSCAssert(events.count == 1 && [receivedText isEqualToData:[@"é🏭 €£¥" dataUsingEncoding:NSUTF8StringEncoding]],
            @"Unicode text must remain available without inventing physical key bindings");
        puts("Factorio keyboard bridge tests passed.");
    }
    return 0;
}
