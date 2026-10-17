#include "../FactorioCompat/FactorioKeyboardBridge.m"

static NSMutableData *receivedText;
static NSMutableArray<NSNumber *> *keyTypes;
static int32_t lastScancode;
static int32_t lastKeycode;

static int captureEvent(FPSDLEvent *event)
{
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

static int cursorState;
static int cursorQuery(int toggle)
{
    NSCAssert(toggle == -1, @"Cursor inspection must never enable or disable the SDL cursor");
    return cursorState;
}

int main(void)
{
    @autoreleasepool {
        NSCAssert(FactorioMouseCursorVisibility() == -1, @"Missing SDL cursor support must be unknown");
        gShowCursor = cursorQuery;
        for (NSNumber *state in @[@0, @1, @2, @(-1)]) {
            cursorState = state.intValue;
            int expected = cursorState == 0 || cursorState == 1 ? cursorState : -1;
            NSCAssert(FactorioMouseCursorVisibility() == expected, @"Normalize unexpected SDL cursor results");
            NSCAssert(cursorState == state.intValue, @"Querying must preserve the game's cursor state");
        }
        gShowCursor = NULL;
        NSCAssert(FactorioMouseCursorVisibility() == -1, @"Unavailable cursor support must remain optional");
        receivedText = [NSMutableData data];
        keyTypes = [NSMutableArray array];
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
        puts("Factorio keyboard bridge tests passed.");
    }
    return 0;
}
