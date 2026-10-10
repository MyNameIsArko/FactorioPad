#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// App-generated SDL calls share one recursive lock. Group compound shortcuts here.
FOUNDATION_EXPORT void FactorioInputPerform(dispatch_block_t operation);

FOUNDATION_EXPORT BOOL
FactorioKeyboardBridgeSetGuestHandle(void *handle, BOOL nativeController);

FOUNDATION_EXPORT void FactorioInputSetActive(BOOL active);

FOUNDATION_EXPORT void
FactorioKeyboardInsertText(NSString *text);

FOUNDATION_EXPORT void
FactorioKeyboardBackspace(void);

FOUNDATION_EXPORT void
FactorioKeyboardReturn(void);

FOUNDATION_EXPORT void
FactorioKeyboardTab(void);

NS_ASSUME_NONNULL_END

#include <stdint.h>
#include <stdbool.h>

void FactorioKeyboardKeyDown(
    int32_t scancode,
    int32_t keycode
);

void FactorioKeyboardKeyUp(
    int32_t scancode,
    int32_t keycode
);

void FactorioKeyboardPhysicalKeyDown(int32_t scancode, int32_t keycode);
void FactorioKeyboardPhysicalKeyUp(int32_t scancode, int32_t keycode);

void FactorioKeyboardSetModifierState(
    uint16_t modifiers
);

void FactorioKeyboardSetPhysicalModifierState(
    uint16_t modifiers
);

void FactorioMouseMove(
    int32_t x,
    int32_t y,
    int32_t xrel,
    int32_t yrel
);

void FactorioMouseButton(
    uint8_t button,
    bool pressed,
    int32_t x,
    int32_t y
);

void FactorioMouseWheel(
    int32_t x,
    int32_t y
);
