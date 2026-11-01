#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "FactorioMetalHost.h"
#import "FactorioMetalLayer.h"

@interface TestMetalHostView : UIView
@end
@implementation TestMetalHostView
+ (Class)layerClass { return FactorioMetalLayer.class; }
@end

static CALayer *makeMetalLayer(id self, SEL selector)
{
    return [CAMetalLayer layer];
}

int main(void)
{
    @autoreleasepool {
        UIView *host = [[TestMetalHostView alloc] initWithFrame:CGRectMake(0, 0, 320, 240)];
        [FactorioMetalHost setHostView:host];
        Class viewClass = NSClassFromString(@"NSView");
        NSCAssert(viewClass, @"load the production AppKit shims");
        for (NSString *name in @[@"SDL_cocoametalview", @"SDL3_cocoametalview"]) {
            Class metalViewClass = objc_allocateClassPair(viewClass, name.UTF8String, 0);
            class_addMethod(metalViewClass, @selector(makeBackingLayer), (IMP)makeMetalLayer, "@@:");
            objc_registerClassPair(metalViewClass);
            id view = [metalViewClass new];
            ((void (*)(id, SEL, BOOL))objc_msgSend)(view, @selector(setWantsLayer:), YES);
            CALayer *layer = ((id (*)(id, SEL))objc_msgSend)(view, @selector(layer));
            NSCAssert(layer == host.layer, @"%@ must reuse the iPad presentation layer", name);
        }
        id plainView = [viewClass new];
        ((void (*)(id, SEL, BOOL))objc_msgSend)(plainView, @selector(setWantsLayer:), YES);
        CALayer *plainLayer = ((id (*)(id, SEL))objc_msgSend)(plainView, @selector(layer));
        NSCAssert(plainLayer && plainLayer != host.layer, @"ordinary views must keep their own layer");
        NSLog(@"PASS: SDL 2 and SDL 3 reuse the iPad Metal layer; ordinary views do not.");
    }
}
