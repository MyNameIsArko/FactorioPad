#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <string.h>
#import "FactorioMetalHost.h"
#import "FactorioTouchBridge.h"

#pragma mark - AppKit globals


__attribute__((visibility("default")))
id NSApp = nil;


__attribute__((visibility("default")))
double NSAppKitVersionNumber = 2022.0;


__attribute__((visibility("default")))
NSString *NSApplicationDidBecomeActiveNotification =
    @"NSApplicationDidBecomeActiveNotification";


__attribute__((visibility("default")))
NSString *NSBackingPropertyOldScaleFactorKey =
    @"NSBackingPropertyOldScaleFactorKey";


__attribute__((visibility("default")))
NSString *NSDeviceRGBColorSpace =
    @"NSDeviceRGBColorSpace";


__attribute__((visibility("default")))
NSString *NSFilenamesPboardType =
    @"NSFilenamesPboardType";


__attribute__((visibility("default")))
NSString *NSPasteboardTypeString =
    @"public.utf8-plain-text";


#define EXPORT_NOTIFICATION(name) \
__attribute__((visibility("default"))) \
NSString *name = @#name;


EXPORT_NOTIFICATION(NSWindowDidBecomeKeyNotification)
EXPORT_NOTIFICATION(NSWindowDidChangeBackingPropertiesNotification)
EXPORT_NOTIFICATION(NSWindowDidChangeScreenNotification)
EXPORT_NOTIFICATION(NSWindowDidChangeScreenProfileNotification)
EXPORT_NOTIFICATION(NSWindowDidDeminiaturizeNotification)
EXPORT_NOTIFICATION(NSWindowDidEnterFullScreenNotification)
EXPORT_NOTIFICATION(NSWindowDidExitFullScreenNotification)
EXPORT_NOTIFICATION(NSWindowDidExposeNotification)
EXPORT_NOTIFICATION(NSWindowDidMiniaturizeNotification)
EXPORT_NOTIFICATION(NSWindowDidMoveNotification)
EXPORT_NOTIFICATION(NSWindowDidResignKeyNotification)
EXPORT_NOTIFICATION(NSWindowDidResizeNotification)
EXPORT_NOTIFICATION(NSWindowWillCloseNotification)
EXPORT_NOTIFICATION(NSWindowWillEnterFullScreenNotification)
EXPORT_NOTIFICATION(NSWindowWillExitFullScreenNotification)


static CGFloat FPDisplayScale(void)
{
    CGFloat scale = [FactorioMetalHost hostScale];

    return scale > 0.0 ? scale : 1.0;
}

static CGRect FPDisplayBounds(void)
{
    return [FactorioMetalHost hostBounds];
}

#pragma mark - Simple AppKit functions


__attribute__((visibility("default")))
BOOL NSMouseInRect(
    CGPoint point,
    CGRect rect,
    BOOL flipped
)
{
    (void)flipped;

    return CGRectContainsPoint(rect, point);
}


__attribute__((visibility("default")))
void NSRectFill(CGRect rect)
{
    (void)rect;
}


#pragma mark - NSResponder


@interface NSResponder : NSObject
{
    __unsafe_unretained NSResponder *_fpNextResponder;
}

- (NSResponder *)nextResponder;
- (void)setNextResponder:(NSResponder *)responder;

@end


@implementation NSResponder


- (NSResponder *)nextResponder
{
    return _fpNextResponder;
}


- (void)setNextResponder:(NSResponder *)responder
{
    _fpNextResponder = responder;
    NSString *selfClass =
        NSStringFromClass([self class]);

    NSString *nextClass =
            responder
            ? NSStringFromClass([responder class])
            : nil;

    if ([selfClass isEqualToString:@"SDLView"] &&
        [nextClass isEqualToString:@"Cocoa_WindowListener"]) {

        FactorioTouchRegisterSDLResponder(
            self,
            responder
        );
    }
}


@end


#pragma mark - NSApplication

@class NSImage;

@interface NSApplication : NSResponder
{
    NSImage *_fpApplicationIconImage;
}

@property(nonatomic, weak) id delegate;

+ (instancetype)sharedApplication;

- (void)finishLaunching;

- (id)nextEventMatchingMask:(NSUInteger)mask
                  untilDate:(NSDate *)date
                     inMode:(NSString *)mode
                    dequeue:(BOOL)dequeue;

- (void)sendEvent:(id)event;

- (BOOL)setActivationPolicy:(NSInteger)activationPolicy;
- (NSInteger)activationPolicy;

- (id)mainMenu;
- (void)setMainMenu:(id)menu;

- (void)activateIgnoringOtherApps:(BOOL)flag;

- (void)setAppleMenu:(id)menu;
- (void)setServicesMenu:(id)menu;
- (void)setWindowsMenu:(id)menu;

- (NSArray *)orderedWindows;
- (id)windowWithWindowNumber:(NSInteger)number;

- (id)keyWindow;
- (id)mainWindow;

- (BOOL)isActive;

- (id)windowsMenu;

- (id)servicesMenu;

- (id)helpMenu;
- (void)setHelpMenu:(id)menu;

- (void)setApplicationIconImage:(NSImage *)image;
- (NSImage *)applicationIconImage;

@end

static id FactorioCompatCreateMenu(NSString *name)
{
    Class menuClass =
        NSClassFromString(@"NSMenu");

    id menu = nil;

    if (menuClass) {

        if (
            [menuClass
                instancesRespondToSelector:
                    @selector(initWithTitle:)
            ]
        ) {

            menu =
                [[menuClass alloc]
                    initWithTitle:name
                ];

        } else {

            menu =
                [menuClass new];
        }

    } else {

        menu =
            [NSObject new];
    }

    return menu;
}

@implementation NSApplication


+ (instancetype)sharedApplication
{
    static NSApplication *application = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        application = [NSApplication new];
        NSApp = application;
    });

    return application;
}


- (void)finishLaunching
{
}


- (id)nextEventMatchingMask:(NSUInteger)mask
                  untilDate:(NSDate *)date
                     inMode:(NSString *)mode
                    dequeue:(BOOL)dequeue
{
    (void)mask;
    (void)date;
    (void)mode;
    (void)dequeue;

    return nil;
}


- (void)sendEvent:(id)event
{
    (void)event;
}

- (BOOL)setActivationPolicy:(NSInteger)activationPolicy
{
    /*
     * iPadOS has no equivalent of the macOS activation policy.
     * The UIKit app is already active in the foreground.
     */

    return YES;
}


- (NSInteger)activationPolicy
{
    /*
     * 0 represents a regular macOS application.
     */
    return 0;
}

- (id)mainMenu
{
    static id menu = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        Class menuClass = NSClassFromString(@"NSMenu");

        if (menuClass) {
            menu = [menuClass new];
        } else {
            menu = [NSObject new];
        }
    });

    return menu;
}


- (void)setMainMenu:(id)menu
{
    /*
     * iPadOS has no macOS application menu.
     * Ignore menu assignment.
     */
}

- (void)activateIgnoringOtherApps:(BOOL)flag
{
}


- (void)setAppleMenu:(id)menu
{
    (void)menu;
}


- (NSArray *)orderedWindows
{
    return @[];
}


- (id)windowWithWindowNumber:(NSInteger)number
{
    (void)number;
    return nil;
}


- (id)keyWindow
{
    return nil;
}


- (id)mainWindow
{
    return nil;
}


- (BOOL)isActive
{
    return YES;
}

- (id)windowsMenu
{
    static id menu = nil;
    static dispatch_once_t onceToken;

    dispatch_once(
        &onceToken,
        ^{
            menu =
                FactorioCompatCreateMenu(
                    @"Windows"
                );
        }
    );

    return menu;
}


- (void)setWindowsMenu:(id)menu
{
}


- (id)servicesMenu
{
    static id menu = nil;
    static dispatch_once_t onceToken;

    dispatch_once(
        &onceToken,
        ^{
            menu =
                FactorioCompatCreateMenu(
                    @"Services"
                );
        }
    );

    return menu;
}


- (void)setServicesMenu:(id)menu
{
}


- (id)helpMenu
{
    static id menu = nil;
    static dispatch_once_t onceToken;

    dispatch_once(
        &onceToken,
        ^{
            menu =
                FactorioCompatCreateMenu(
                    @"Help"
                );
        }
    );

    return menu;
}


- (void)setHelpMenu:(id)menu
{
}

- (void)setApplicationIconImage:(NSImage *)image
{
    _fpApplicationIconImage = image;
}


- (NSImage *)applicationIconImage
{
    return _fpApplicationIconImage;
}

@end


#pragma mark - NSView

@class NSScreen;

@interface NSView : NSResponder
{
    CGRect _fpFrame;

    __unsafe_unretained NSView *_fpSuperview;
    NSMutableArray *_fpSubviews;

    CALayer *_fpLayer;

    __unsafe_unretained id _fpWindow;

    BOOL _fpWantsLayer;
    BOOL _fpWantsBestResolutionOpenGLSurface;
    
    BOOL _fpAcceptsTouchEvents;
    
    NSUInteger _fpAutoresizingMask;
    NSInteger _fpTag;
}


- (instancetype)init;
- (instancetype)initWithFrame:(CGRect)frame;


- (CGRect)frame;
- (void)setFrame:(CGRect)frame;

- (CGRect)bounds;
- (void)setBounds:(CGRect)bounds;

- (void)setFrameOrigin:(CGPoint)origin;
- (void)setFrameSize:(CGSize)size;


- (NSView *)superview;
- (NSArray *)subviews;

- (void)addSubview:(NSView *)view;
- (void)removeFromSuperview;


- (id)window;

- (void)setWantsBestResolutionOpenGLSurface:(BOOL)value;
- (BOOL)wantsBestResolutionOpenGLSurface;


/*
 * Private helper used by NSWindow to connect the view hierarchy.
 */
- (void)_fpSetWindow:(id)window;


/*
 * Layer-backed view emulation.
 */
- (void)setWantsLayer:(BOOL)wantsLayer;
- (BOOL)wantsLayer;

- (CALayer *)layer;
- (void)setLayer:(CALayer *)layer;

- (CALayer *)makeBackingLayer;


/*
 * Basic SDL/Cocoa view helpers.
 */
- (BOOL)isFlipped;

- (BOOL)acceptsFirstResponder;
- (BOOL)becomeFirstResponder;
- (BOOL)resignFirstResponder;

- (NSView *)hitTest:(CGPoint)point;

- (CGRect)convertRect:(CGRect)rect
               toView:(NSView *)view;

- (CGRect)convertRect:(CGRect)rect
             fromView:(NSView *)view;

- (CGPoint)convertPoint:(CGPoint)point
                 toView:(NSView *)view;

- (CGPoint)convertPoint:(CGPoint)point
               fromView:(NSView *)view;

- (void)setNeedsDisplay:(BOOL)needsDisplay;
- (void)setNeedsLayout:(BOOL)needsLayout;

- (void)layout;
- (void)layoutSubtreeIfNeeded;

- (void)setAcceptsTouchEvents:(BOOL)value;
- (BOOL)acceptsTouchEvents;

- (void)setAutoresizingMask:(NSUInteger)mask;
- (NSUInteger)autoresizingMask;

- (CGSize)convertSizeToBacking:(CGSize)size;
- (CGSize)convertSizeFromBacking:(CGSize)size;

- (NSInteger)tag;
- (void)setTag:(NSInteger)tag;

- (NSView *)viewWithTag:(NSInteger)tag;

- (CGRect)convertRectToBacking:(CGRect)rect;
- (CGRect)convertRectFromBacking:(CGRect)rect;

- (BOOL)mouse:(CGPoint)point inRect:(CGRect)rect;

@end



@implementation NSView


- (instancetype)init
{
    return [self initWithFrame:CGRectZero];
}


- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super init];

    if (self) {

        _fpFrame = frame;

        _fpSubviews =
            [NSMutableArray array];

        _fpSuperview = nil;
        _fpWindow = nil;

        _fpLayer = nil;

        _fpWantsLayer = NO;
        _fpWantsBestResolutionOpenGLSurface = NO;
        _fpAutoresizingMask = 0;
        _fpTag = 0;
    }

    return self;
}



#pragma mark Geometry


- (CGRect)frame
{
    return _fpFrame;
}


- (void)setFrame:(CGRect)frame
{
    _fpFrame = frame;

    if (_fpLayer) {
        _fpLayer.frame =
            CGRectMake(
                0,
                0,
                frame.size.width,
                frame.size.height
            );
    }
}


- (CGRect)bounds
{
    return CGRectMake(
        0,
        0,
        _fpFrame.size.width,
        _fpFrame.size.height
    );
}


- (void)setBounds:(CGRect)bounds
{
    _fpFrame.size =
        bounds.size;

    if (_fpLayer) {
        _fpLayer.bounds = bounds;
    }
}


- (void)setFrameOrigin:(CGPoint)origin
{
    _fpFrame.origin =
        origin;
}


- (void)setFrameSize:(CGSize)size
{
    _fpFrame.size =
        size;

    if (_fpLayer) {
        _fpLayer.frame =
            CGRectMake(
                0,
                0,
                size.width,
                size.height
            );
    }
}



#pragma mark Hierarchy


- (NSView *)superview
{
    return _fpSuperview;
}


- (NSArray *)subviews
{
    return [_fpSubviews copy];
}


- (void)addSubview:(NSView *)view
{
    if (!view) {
        return;
    }

    if (view == self) {
        return;
    }


    if ([view superview]) {
        [view removeFromSuperview];
    }


    [_fpSubviews addObject:view];

    view->_fpSuperview =
        self;


    [view _fpSetWindow:
        [self window]
    ];
}


- (void)removeFromSuperview
{
    NSView *parent =
        _fpSuperview;


    if (!parent) {
        return;
    }


    [parent->_fpSubviews removeObjectIdenticalTo:self];

    _fpSuperview =
        nil;

    [self _fpSetWindow:nil];
}



#pragma mark Window relation


- (id)window
{
    if (_fpWindow) {
        return _fpWindow;
    }

    if (_fpSuperview) {
        return [_fpSuperview window];
    }

    return nil;
}


- (void)_fpSetWindow:(id)window
{
    _fpWindow =
        window;


    /*
     * Propagate NSWindow to child views.
     */
    for (NSView *child in _fpSubviews) {

        [child _fpSetWindow:window];

    }
}



#pragma mark Layer backing


- (void)setWantsLayer:(BOOL)wantsLayer
{
    _fpWantsLayer =
        wantsLayer;


    if (wantsLayer && !_fpLayer) {

        NSString *className =
            NSStringFromClass([self class]);


        if ([className isEqualToString:@"SDL_cocoametalview"]) {

            CAMetalLayer *hostLayer =
                [FactorioMetalHost hostMetalLayer];


            if (hostLayer) {

                _fpLayer = hostLayer;

            } else {

                _fpLayer =
                    [self makeBackingLayer];
            }

        } else {

            _fpLayer =
                [self makeBackingLayer];
        }
    }
}


- (BOOL)wantsLayer
{
    return _fpWantsLayer;
}


- (CALayer *)layer
{
    if (
        _fpLayer &&
        [_fpLayer isKindOfClass:[CAMetalLayer class]]
    ) {
        [FactorioMetalHost
            attachMetalLayer:(CAMetalLayer *)_fpLayer
        ];
    }

    return _fpLayer;
}


- (void)setLayer:(CALayer *)layer
{
    _fpLayer = layer;

    if (
        [_fpLayer isKindOfClass:[CAMetalLayer class]]
    ) {
        [FactorioMetalHost
            attachMetalLayer:(CAMetalLayer *)_fpLayer
        ];
    }
}


- (CALayer *)makeBackingLayer
{
    return [CALayer layer];
}



#pragma mark First responder


- (BOOL)acceptsFirstResponder
{
    return YES;
}


- (BOOL)becomeFirstResponder
{
    return YES;
}


- (BOOL)resignFirstResponder
{
    return YES;
}



#pragma mark Hit testing


- (NSView *)hitTest:(CGPoint)point
{
    (void)point;

    return self;
}



#pragma mark Coordinate conversion


- (CGRect)convertRect:(CGRect)rect
               toView:(NSView *)view
{
    (void)view;

    return rect;
}


- (CGRect)convertRect:(CGRect)rect
             fromView:(NSView *)view
{
    (void)view;

    return rect;
}


- (CGPoint)convertPoint:(CGPoint)point
                 toView:(NSView *)view
{
    (void)view;

    return point;
}


- (CGPoint)convertPoint:(CGPoint)point
               fromView:(NSView *)view
{
    (void)view;

    return point;
}



#pragma mark Drawing/layout


- (BOOL)isFlipped
{
    return NO;
}


- (void)setNeedsDisplay:(BOOL)needsDisplay
{
    (void)needsDisplay;
}


- (void)setNeedsLayout:(BOOL)needsLayout
{
    (void)needsLayout;
}


- (void)layout
{
}


- (void)layoutSubtreeIfNeeded
{
}

- (void)setWantsBestResolutionOpenGLSurface:(BOOL)value
{
    _fpWantsBestResolutionOpenGLSurface = value;
}


- (BOOL)wantsBestResolutionOpenGLSurface
{
    return _fpWantsBestResolutionOpenGLSurface;
}

- (void)setAcceptsTouchEvents:(BOOL)value
{
    _fpAcceptsTouchEvents = value;
}


- (BOOL)acceptsTouchEvents
{
    return _fpAcceptsTouchEvents;
}

- (void)setAutoresizingMask:(NSUInteger)mask
{
    _fpAutoresizingMask = mask;
}


- (NSUInteger)autoresizingMask
{
    return _fpAutoresizingMask;
}

- (CGSize)convertSizeToBacking:(CGSize)size
{
    CGFloat scale = FPDisplayScale();

    if (scale <= 0.0) {
        scale = 1.0;
    }

    CGSize result =
        CGSizeMake(
            size.width * scale,
            size.height * scale
        );

    return result;
}


- (CGSize)convertSizeFromBacking:(CGSize)size
{
    CGFloat scale = FPDisplayScale();

    if (scale <= 0.0) {
        scale = 1.0;
    }

    return CGSizeMake(
        size.width / scale,
        size.height / scale
    );
}

- (NSInteger)tag
{
    return _fpTag;
}


- (void)setTag:(NSInteger)tag
{
    _fpTag = tag;
}


- (NSView *)viewWithTag:(NSInteger)wantedTag
{
    if ([self tag] == wantedTag) {
        return self;
    }

    for (NSView *subview in _fpSubviews) {
        NSView *found = [subview viewWithTag:wantedTag];

        if (found) {
            return found;
        }
    }

    return nil;
}

- (CGRect)convertRectToBacking:(CGRect)rect
{
    CGFloat scale = FPDisplayScale();

    if (scale <= 0.0) {
        scale = 1.0;
    }

    CGRect result = CGRectMake(
        rect.origin.x * scale,
        rect.origin.y * scale,
        rect.size.width * scale,
        rect.size.height * scale
    );

    return result;
}

- (CGRect)convertRectFromBacking:(CGRect)rect
{
    CGFloat scale = FPDisplayScale();

    if (scale <= 0.0) {
        scale = 1.0;
    }

    return CGRectMake(
        rect.origin.x / scale,
        rect.origin.y / scale,
        rect.size.width / scale,
        rect.size.height / scale
    );
}

- (BOOL)mouse:(CGPoint)point inRect:(CGRect)rect
{
    return CGRectContainsPoint(rect, point);
}

@end

#pragma mark - NSColorSpace


@interface NSColorSpace : NSObject
{
    NSString *_fpName;
}

+ (instancetype)sRGBColorSpace;
+ (instancetype)deviceRGBColorSpace;
+ (instancetype)genericRGBColorSpace;
+ (instancetype)displayP3ColorSpace;

- (NSString *)localizedName;
- (NSData *)ICCProfileData;

@end


@implementation NSColorSpace


+ (instancetype)_fpColorSpaceNamed:(NSString *)name
{
    NSColorSpace *space =
        [NSColorSpace new];

    space->_fpName =
        [name copy];

    return space;
}


+ (instancetype)sRGBColorSpace
{
    static NSColorSpace *space = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        space =
            [self _fpColorSpaceNamed:@"sRGB"];
    });

    return space;
}


+ (instancetype)deviceRGBColorSpace
{
    return [self sRGBColorSpace];
}


+ (instancetype)genericRGBColorSpace
{
    return [self sRGBColorSpace];
}


+ (instancetype)displayP3ColorSpace
{
    /*
     * For now, tag everything as sRGB.
     */
    return [self sRGBColorSpace];
}


- (NSString *)localizedName
{
    return _fpName ?: @"sRGB";
}


- (NSData *)ICCProfileData
{
    /*
     * No macOS ICC profile is available.
     *
     * nil is safer than a fabricated profile.
     * SDL can report a missing profile without crashing.
     */
    return nil;
}


@end

#pragma mark - NSWindow


@interface NSWindow : NSResponder
{
    CGRect _fpFrame;
    NSView *_fpContentView;

    __unsafe_unretained id _fpDelegate;
    __unsafe_unretained id _fpFirstResponder;

    NSUInteger _fpStyleMask;
    NSString *_fpTitle;
    
    NSColorSpace *_fpColorSpace;

    NSUInteger _fpTabbingMode;
    NSUInteger _fpCollectionBehavior;
    
    BOOL _fpAcceptsMouseMovedEvents;
    BOOL _fpRestorable;
    BOOL _fpOpaque;
    BOOL _fpHasShadow;

    CGSize _fpContentMinSize;
    CGSize _fpContentMaxSize;
    CGSize _fpContentAspectRatio;

    NSInteger _fpLevel;
    
    NSInteger _fpWindowNumber;
    
    BOOL _fpZoomed;
    BOOL _fpMiniaturized;
    
    BOOL _fpReleasedWhenClosed;
    
    BOOL _fpOneShot;
    
    CGRect _fpMouseConfinementRect;
}


- (instancetype)initWithContentRect:(CGRect)contentRect
                          styleMask:(NSUInteger)styleMask
                            backing:(NSUInteger)backing
                              defer:(BOOL)deferFlag
                             screen:(id)screen;


- (NSView *)contentView;
- (void)setContentView:(NSView *)view;


- (CGRect)frame;
- (void)setFrame:(CGRect)frame
         display:(BOOL)display;

- (void)setFrameOrigin:(CGPoint)origin;


- (NSUInteger)styleMask;
- (void)setStyleMask:(NSUInteger)styleMask;


- (void)setTitle:(NSString *)title;


- (void)setDelegate:(id)delegate;
- (id)delegate;


- (void)makeKeyAndOrderFront:(id)sender;
- (void)orderFront:(id)sender;
- (void)orderOut:(id)sender;


- (BOOL)makeFirstResponder:(id)responder;
- (id)firstResponder;


- (CGFloat)backingScaleFactor;

- (id)screen;

- (BOOL)isVisible;
- (BOOL)isKeyWindow;
- (BOOL)isMainWindow;

- (void)toggleFullScreen:(id)sender;

- (void)setColorSpace:(NSColorSpace *)colorSpace;
- (NSColorSpace *)colorSpace;

- (void)setTabbingMode:(NSUInteger)mode;
- (NSUInteger)tabbingMode;

- (void)setCollectionBehavior:(NSUInteger)behavior;
- (NSUInteger)collectionBehavior;

- (CGRect)contentRectForFrameRect:(CGRect)frameRect;
- (CGRect)frameRectForContentRect:(CGRect)contentRect;

- (CGRect)contentRectForFrameRect:(CGRect)frameRect
                       styleMask:(NSUInteger)styleMask;

- (CGRect)frameRectForContentRect:(CGRect)contentRect
                        styleMask:(NSUInteger)styleMask;

- (void)setAcceptsMouseMovedEvents:(BOOL)value;
- (BOOL)acceptsMouseMovedEvents;

- (void)setRestorable:(BOOL)value;
- (BOOL)isRestorable;

- (void)setContentMinSize:(CGSize)size;
- (CGSize)contentMinSize;

- (void)setContentMaxSize:(CGSize)size;
- (CGSize)contentMaxSize;

- (void)setMinSize:(CGSize)size;
- (CGSize)minSize;

- (void)setMaxSize:(CGSize)size;
- (CGSize)maxSize;

- (void)setContentAspectRatio:(CGSize)ratio;
- (CGSize)contentAspectRatio;

- (void)setLevel:(NSInteger)level;
- (NSInteger)level;

- (void)setOpaque:(BOOL)opaque;
- (BOOL)isOpaque;

- (void)setHasShadow:(BOOL)hasShadow;
- (BOOL)hasShadow;

- (NSInteger)windowNumber;

- (BOOL)isZoomed;
- (BOOL)isMiniaturized;

- (void)zoom:(id)sender;
- (void)miniaturize:(id)sender;
- (void)deminiaturize:(id)sender;

- (void)setReleasedWhenClosed:(BOOL)value;
- (BOOL)isReleasedWhenClosed;

- (void)registerForDraggedTypes:(NSArray *)types;
- (void)unregisterDraggedTypes;

- (void)setOneShot:(BOOL)flag;
- (BOOL)isOneShot;

- (void)invalidateCursorRectsForView:(id)view;

- (void)setMouseConfinementRect:(CGRect)rect;
- (CGRect)mouseConfinementRect;

- (void)close;

@end

static NSInteger FactorioNextWindowNumber = 1;

@implementation NSWindow


- (instancetype)init
{
    return [self
        initWithContentRect:CGRectMake(0, 0, 1024, 768)
        styleMask:0
        backing:0
        defer:NO
        screen:nil
    ];
}


- (instancetype)initWithContentRect:(CGRect)contentRect
                          styleMask:(NSUInteger)styleMask
                            backing:(NSUInteger)backing
                              defer:(BOOL)deferFlag
                             screen:(id)screen
{
    self = [super init];

    if (self) {

        _fpFrame = contentRect;
        _fpStyleMask = styleMask;

        _fpDelegate = nil;
        _fpFirstResponder = nil;

        _fpTitle = @"";

        _fpContentView =
            [[NSView alloc]
                initWithFrame:CGRectMake(
                    0,
                    0,
                    contentRect.size.width,
                    contentRect.size.height
                )
            ];

        _fpWindowNumber =
            FactorioNextWindowNumber++;
        
        _fpZoomed = NO;
        _fpMiniaturized = NO;
        _fpReleasedWhenClosed = NO;
        _fpOneShot = NO;
        
        _fpMouseConfinementRect =
            CGRectZero;

        if (
            [_fpContentView
                respondsToSelector:
                    @selector(_fpSetWindow:)
            ]
        ) {

            [_fpContentView
                _fpSetWindow:self
            ];
        }
    }


    (void)backing;
    (void)deferFlag;
    (void)screen;


    return self;
}



#pragma mark Content view


- (NSView *)contentView
{
    return _fpContentView;
}


- (void)setContentView:(NSView *)view
{
    _fpContentView =
        view;


    if (
        [view respondsToSelector:
            @selector(_fpSetWindow:)
        ]
    ) {

        [view
            _fpSetWindow:self
        ];
    }
}



#pragma mark Geometry


- (CGRect)frame
{
    return _fpFrame;
}


- (void)setFrame:(CGRect)frame
         display:(BOOL)display
{
    _fpFrame =
        frame;


    if (_fpContentView) {

        [_fpContentView
            setFrame:CGRectMake(
                0,
                0,
                frame.size.width,
                frame.size.height
            )
        ];
    }


    (void)display;
}


- (void)setFrameOrigin:(CGPoint)origin
{
    _fpFrame.origin =
        origin;
}



#pragma mark Style


- (NSUInteger)styleMask
{
    return _fpStyleMask;
}


- (void)setStyleMask:(NSUInteger)styleMask
{
    _fpStyleMask =
        styleMask;
}


- (void)setTitle:(NSString *)title
{
    _fpTitle =
        [title copy];
}



#pragma mark Delegate


- (void)setDelegate:(id)delegate
{
    _fpDelegate =
        delegate;
}


- (id)delegate
{
    return _fpDelegate;
}



#pragma mark Ordering


- (void)makeKeyAndOrderFront:(id)sender
{
    (void)sender;
}


- (void)orderFront:(id)sender
{
    (void)sender;
}


- (void)orderOut:(id)sender
{
    (void)sender;
}



#pragma mark First responder


- (BOOL)makeFirstResponder:(id)responder
{
    _fpFirstResponder =
        responder;


    return YES;
}


- (id)firstResponder
{
    return _fpFirstResponder;
}



#pragma mark Screen


- (CGFloat)backingScaleFactor
{
    return FPDisplayScale();
}


- (id)screen
{
    Class screenClass =
        NSClassFromString(@"NSScreen");

    if (
        screenClass &&
        [screenClass
            respondsToSelector:@selector(mainScreen)
        ]
    ) {

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

        return
            [screenClass
                performSelector:@selector(mainScreen)
            ];

#pragma clang diagnostic pop
    }


    return nil;
}



#pragma mark State


- (BOOL)isVisible
{
    return YES;
}


- (BOOL)isKeyWindow
{
    return YES;
}


- (BOOL)isMainWindow
{
    return YES;
}


- (void)toggleFullScreen:(id)sender
{
    /*
     * iPadOS has no macOS fullscreen transition.
     */
    (void)sender;
}

#pragma mark Color space


- (void)setColorSpace:(NSColorSpace *)colorSpace
{
    _fpColorSpace =
        colorSpace;
}


- (NSColorSpace *)colorSpace
{
    if (!_fpColorSpace) {
        _fpColorSpace =
            [NSColorSpace sRGBColorSpace];
    }

    return _fpColorSpace;
}



#pragma mark Window policy


- (void)setTabbingMode:(NSUInteger)mode
{
    _fpTabbingMode =
        mode;
}


- (NSUInteger)tabbingMode
{
    return _fpTabbingMode;
}


- (void)setCollectionBehavior:(NSUInteger)behavior
{
    _fpCollectionBehavior =
        behavior;
}


- (NSUInteger)collectionBehavior
{
    return _fpCollectionBehavior;
}

#pragma mark Frame/content conversion


- (CGRect)contentRectForFrameRect:(CGRect)frameRect
{
    /*
     * The iPad host window has no macOS title bar or decorations,
     * so frame == content.
     */
    return frameRect;
}


- (CGRect)frameRectForContentRect:(CGRect)contentRect
{
    return contentRect;
}


- (CGRect)contentRectForFrameRect:(CGRect)frameRect
                       styleMask:(NSUInteger)styleMask
{
    (void)styleMask;

    return frameRect;
}


- (CGRect)frameRectForContentRect:(CGRect)contentRect
                        styleMask:(NSUInteger)styleMask
{
    (void)styleMask;

    return contentRect;
}

#pragma mark Additional window state


- (void)setAcceptsMouseMovedEvents:(BOOL)value
{
    _fpAcceptsMouseMovedEvents = value;
}


- (BOOL)acceptsMouseMovedEvents
{
    return _fpAcceptsMouseMovedEvents;
}


- (void)setRestorable:(BOOL)value
{
    _fpRestorable = value;
}


- (BOOL)isRestorable
{
    return _fpRestorable;
}


- (void)setContentMinSize:(CGSize)size
{
    _fpContentMinSize = size;
}


- (CGSize)contentMinSize
{
    return _fpContentMinSize;
}


- (void)setContentMaxSize:(CGSize)size
{
    _fpContentMaxSize = size;
}


- (CGSize)contentMaxSize
{
    return _fpContentMaxSize;
}


- (void)setMinSize:(CGSize)size
{
    _fpContentMinSize = size;
}


- (CGSize)minSize
{
    return _fpContentMinSize;
}


- (void)setMaxSize:(CGSize)size
{
    _fpContentMaxSize = size;
}


- (CGSize)maxSize
{
    return _fpContentMaxSize;
}


- (void)setContentAspectRatio:(CGSize)ratio
{
    _fpContentAspectRatio = ratio;
}


- (CGSize)contentAspectRatio
{
    return _fpContentAspectRatio;
}


- (void)setLevel:(NSInteger)level
{
    _fpLevel = level;
}


- (NSInteger)level
{
    return _fpLevel;
}


- (void)setOpaque:(BOOL)opaque
{
    _fpOpaque = opaque;
}


- (BOOL)isOpaque
{
    return _fpOpaque;
}


- (void)setHasShadow:(BOOL)hasShadow
{
    _fpHasShadow = hasShadow;
}


- (BOOL)hasShadow
{
    return _fpHasShadow;
}

- (NSInteger)windowNumber
{
    return _fpWindowNumber;
}

#pragma mark Zoom / minimize state


- (BOOL)isZoomed
{
    return _fpZoomed;
}


- (BOOL)isMiniaturized
{
    return _fpMiniaturized;
}


- (void)zoom:(id)sender
{
    (void)sender;

    _fpZoomed = !_fpZoomed;
}


- (void)miniaturize:(id)sender
{
    (void)sender;

    /*
     * iPadOS has no equivalent of minimizing to the Dock.
     * Keep only the state for SDL.
     */
    _fpMiniaturized = YES;
}


- (void)deminiaturize:(id)sender
{
    (void)sender;

    _fpMiniaturized = NO;
}

- (void)setReleasedWhenClosed:(BOOL)value
{
    _fpReleasedWhenClosed = value;
}


- (BOOL)isReleasedWhenClosed
{
    return _fpReleasedWhenClosed;
}

- (void)registerForDraggedTypes:(NSArray *)types
{
}


- (void)unregisterDraggedTypes
{
}

#pragma mark One-shot window device


- (void)setOneShot:(BOOL)flag
{
    _fpOneShot = flag;
}


- (BOOL)isOneShot
{
    return _fpOneShot;
}

- (void)invalidateCursorRectsForView:(id)view
{
    // UIKit does not use AppKit cursor rectangles.
    // SDL calls this after a cursor change or mouse movement.
    (void)view;
}

- (void)setMouseConfinementRect:(CGRect)rect
{
    /*
     * SDL Cocoa uses this property to confine the system mouse cursor.
     *
     * iPadOS does not apply confinement,
     * but keep the value for SDL compatibility.
     */
    _fpMouseConfinementRect =
        rect;
}


- (CGRect)mouseConfinementRect
{
    return _fpMouseConfinementRect;
}

- (void)close
{
    /*
     * SDL Cocoa calls this during SDL_DestroyWindow().
     *
     * On iOS, the host manages the actual UIView/CAMetalLayer.
     * Do not destroy the UIKit window through this macOS path.
     */
}

@end


#pragma mark - NSScreen


@interface NSScreen : NSObject

+ (instancetype)mainScreen;
+ (NSArray *)screens;

- (CGRect)frame;
- (CGRect)visibleFrame;

- (CGFloat)backingScaleFactor;

- (NSDictionary *)deviceDescription;

- (NSColorSpace *)colorSpace;

@end


@implementation NSScreen


+ (instancetype)mainScreen
{
    static NSScreen *screen = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        screen = [NSScreen new];
    });

    return screen;
}


+ (NSArray *)screens
{
    return @[
        [NSScreen mainScreen]
    ];
}


- (CGRect)frame
{
    CGSize s = FPDisplayBounds().size;

    CGFloat w = MAX(s.width, s.height);
    CGFloat h = MIN(s.width, s.height);

    return CGRectMake(
        0,
        0,
        w,
        h
    );
}


- (CGRect)visibleFrame
{
    return self.frame;
}


- (CGFloat)backingScaleFactor
{
    return FPDisplayScale();
}


- (NSDictionary *)deviceDescription
{
    /*
     * SDL Cocoa uses NSScreenNumber to connect
     * NSScreen to CGDirectDisplayID.
     */
    return @{
        @"NSScreenNumber": @(1)
    };
}

- (NSColorSpace *)colorSpace
{
    return [NSColorSpace sRGBColorSpace];
}

@end


#pragma mark - NSEvent


@interface NSEvent : NSObject

/*
 * Class methods used by the SDL Cocoa backend.
 */

+ (NSUInteger)modifierFlags;
+ (NSUInteger)pressedMouseButtons;

+ (CGPoint)mouseLocation;
+ (CGPoint)mouseLocationOutsideOfEventStream;

+ (NSTimeInterval)doubleClickInterval;
+ (NSTimeInterval)keyRepeatDelay;
+ (NSTimeInterval)keyRepeatInterval;

+ (void)startPeriodicEventsAfterDelay:(NSTimeInterval)delay
                           withPeriod:(NSTimeInterval)period;

+ (void)stopPeriodicEvents;


/*
 * Minimal set of instance methods.
 *
 * Most events ultimately come from our iPadOS backend.
 * These methods prevent crashes during ordinary SDL reads.
 */

- (NSUInteger)type;
- (NSUInteger)modifierFlags;

- (unsigned short)keyCode;

- (NSString *)characters;
- (NSString *)charactersIgnoringModifiers;

- (BOOL)isARepeat;

- (NSInteger)windowNumber;

- (CGPoint)locationInWindow;

- (NSTimeInterval)timestamp;

- (NSInteger)buttonNumber;
- (NSInteger)clickCount;

- (CGFloat)deltaX;
- (CGFloat)deltaY;
- (CGFloat)deltaZ;

- (CGFloat)scrollingDeltaX;
- (CGFloat)scrollingDeltaY;

- (BOOL)hasPreciseScrollingDeltas;

- (NSUInteger)phase;
- (NSUInteger)momentumPhase;

- (short)subtype;

- (NSInteger)data1;
- (NSInteger)data2;

@end


@implementation NSEvent


#pragma mark Class state


+ (NSUInteger)modifierFlags
{
    /*
     * Initially, Shift/Ctrl/Option/Cmd are not pressed.
     */
    return 0;
}


+ (NSUInteger)pressedMouseButtons
{
    return 0;
}


+ (CGPoint)mouseLocation
{
    return CGPointZero;
}


+ (CGPoint)mouseLocationOutsideOfEventStream
{
    return CGPointZero;
}


+ (NSTimeInterval)doubleClickInterval
{
    return 0.5;
}


+ (NSTimeInterval)keyRepeatDelay
{
    return 0.5;
}


+ (NSTimeInterval)keyRepeatInterval
{
    return 0.033;
}


+ (void)startPeriodicEventsAfterDelay:(NSTimeInterval)delay
                           withPeriod:(NSTimeInterval)period
{
    (void)delay;
    (void)period;
}


+ (void)stopPeriodicEvents
{
}


#pragma mark Instance state


- (NSUInteger)type
{
    return 0;
}


- (NSUInteger)modifierFlags
{
    return 0;
}


- (unsigned short)keyCode
{
    return 0;
}


- (NSString *)characters
{
    return @"";
}


- (NSString *)charactersIgnoringModifiers
{
    return @"";
}


- (BOOL)isARepeat
{
    return NO;
}


- (NSInteger)windowNumber
{
    return 0;
}


- (CGPoint)locationInWindow
{
    return CGPointZero;
}


- (NSTimeInterval)timestamp
{
    return NSProcessInfo.processInfo.systemUptime;
}


- (NSInteger)buttonNumber
{
    return 0;
}


- (NSInteger)clickCount
{
    return 1;
}


- (CGFloat)deltaX
{
    return 0.0;
}


- (CGFloat)deltaY
{
    return 0.0;
}


- (CGFloat)deltaZ
{
    return 0.0;
}


- (CGFloat)scrollingDeltaX
{
    return 0.0;
}


- (CGFloat)scrollingDeltaY
{
    return 0.0;
}


- (BOOL)hasPreciseScrollingDeltas
{
    return NO;
}


- (NSUInteger)phase
{
    return 0;
}


- (NSUInteger)momentumPhase
{
    return 0;
}


- (short)subtype
{
    return 0;
}


- (NSInteger)data1
{
    return 0;
}


- (NSInteger)data2
{
    return 0;
}


@end


#pragma mark - NSPasteboard


@interface NSPasteboard : NSObject

+ (instancetype)generalPasteboard;

@end


@implementation NSPasteboard


+ (instancetype)generalPasteboard
{
    static NSPasteboard *pasteboard = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        pasteboard = [NSPasteboard new];
    });

    return pasteboard;
}


@end


#pragma mark - NSAppleEventManager


@interface NSAppleEventManager : NSObject

+ (instancetype)sharedAppleEventManager;

- (void)setEventHandler:(id)handler
            andSelector:(SEL)selector
          forEventClass:(uint32_t)eventClass
             andEventID:(uint32_t)eventID;

- (void)removeEventHandlerForEventClass:(uint32_t)eventClass
                              andEventID:(uint32_t)eventID;

@end


@implementation NSAppleEventManager


+ (instancetype)sharedAppleEventManager
{
    static NSAppleEventManager *manager = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        manager = [NSAppleEventManager new];
    });

    return manager;
}


- (void)setEventHandler:(id)handler
            andSelector:(SEL)selector
          forEventClass:(uint32_t)eventClass
             andEventID:(uint32_t)eventID
{
    (void)eventClass;
    (void)eventID;
}


- (void)removeEventHandlerForEventClass:(uint32_t)eventClass
                              andEventID:(uint32_t)eventID
{
    (void)eventClass;
    (void)eventID;
}


@end

#pragma mark - NSMenuItem


@interface NSMenuItem : NSObject
{
    NSString *_fpTitle;
    SEL _fpAction;
    __unsafe_unretained id _fpTarget;
    id _fpSubmenu;

    NSString *_fpKeyEquivalent;

    BOOL _fpEnabled;
    NSInteger _fpTag;
    NSUInteger _fpKeyEquivalentModifierMask;
}

+ (instancetype)separatorItem;

- (instancetype)initWithTitle:(NSString *)title
                       action:(SEL)action
                keyEquivalent:(NSString *)keyEquivalent;

- (NSString *)title;
- (void)setTitle:(NSString *)title;

- (SEL)action;
- (void)setAction:(SEL)action;

- (id)target;
- (void)setTarget:(id)target;

- (id)submenu;
- (void)setSubmenu:(id)submenu;

- (NSString *)keyEquivalent;
- (void)setKeyEquivalent:(NSString *)keyEquivalent;

- (void)setKeyEquivalentModifierMask:(NSUInteger)mask;
- (NSUInteger)keyEquivalentModifierMask;

- (void)setEnabled:(BOOL)enabled;
- (BOOL)isEnabled;

- (void)setTag:(NSInteger)tag;
- (NSInteger)tag;

@end


@implementation NSMenuItem


+ (instancetype)separatorItem
{
    NSMenuItem *item =
        [[NSMenuItem alloc]
            initWithTitle:@""
            action:NULL
            keyEquivalent:@""
        ];

    return item;
}


- (instancetype)init
{
    return [self
        initWithTitle:@""
        action:NULL
        keyEquivalent:@""
    ];
}


- (instancetype)initWithTitle:(NSString *)title
                       action:(SEL)action
                keyEquivalent:(NSString *)keyEquivalent
{
    self = [super init];

    if (self) {
        _fpTitle = [title copy] ?: @"";
        _fpAction = action;
        _fpTarget = nil;
        _fpSubmenu = nil;
        _fpKeyEquivalent = [keyEquivalent copy] ?: @"";
        _fpEnabled = YES;
        _fpTag = 0;
        _fpKeyEquivalentModifierMask = 0;
    }

    return self;
}


- (NSString *)title
{
    return _fpTitle;
}


- (void)setTitle:(NSString *)title
{
    _fpTitle = [title copy] ?: @"";
}


- (SEL)action
{
    return _fpAction;
}


- (void)setAction:(SEL)action
{
    _fpAction = action;
}


- (id)target
{
    return _fpTarget;
}


- (void)setTarget:(id)target
{
    _fpTarget = target;
}


- (id)submenu
{
    return _fpSubmenu;
}


- (void)setSubmenu:(id)submenu
{
    _fpSubmenu = submenu;
}


- (NSString *)keyEquivalent
{
    return _fpKeyEquivalent;
}


- (void)setKeyEquivalent:(NSString *)keyEquivalent
{
    _fpKeyEquivalent = [keyEquivalent copy] ?: @"";
}


- (void)setKeyEquivalentModifierMask:(NSUInteger)mask
{
    _fpKeyEquivalentModifierMask = mask;
}


- (NSUInteger)keyEquivalentModifierMask
{
    return _fpKeyEquivalentModifierMask;
}


- (void)setEnabled:(BOOL)enabled
{
    _fpEnabled = enabled;
}


- (BOOL)isEnabled
{
    return _fpEnabled;
}


- (void)setTag:(NSInteger)tag
{
    _fpTag = tag;
}


- (NSInteger)tag
{
    return _fpTag;
}


@end



#pragma mark - NSMenu


@interface NSMenu : NSObject
{
    NSString *_fpTitle;
    NSMutableArray *_fpItems;
    BOOL _fpAutoenablesItems;
}


- (instancetype)initWithTitle:(NSString *)title;

- (NSString *)title;
- (void)setTitle:(NSString *)title;


- (void)addItem:(NSMenuItem *)item;

- (NSMenuItem *)addItemWithTitle:(NSString *)title
                          action:(SEL)action
                   keyEquivalent:(NSString *)keyEquivalent;


- (NSMenuItem *)itemWithTitle:(NSString *)title;
- (NSMenuItem *)itemWithTag:(NSInteger)tag;

- (NSInteger)indexOfItemWithTitle:(NSString *)title;
- (NSInteger)indexOfItemWithTag:(NSInteger)tag;

- (NSInteger)numberOfItems;
- (NSArray *)itemArray;

- (NSMenuItem *)itemAtIndex:(NSInteger)index;

- (void)removeItem:(NSMenuItem *)item;
- (void)removeItemAtIndex:(NSInteger)index;

- (void)setAutoenablesItems:(BOOL)flag;
- (BOOL)autoenablesItems;

@end


@implementation NSMenu


- (instancetype)init
{
    return [self initWithTitle:@""];
}


- (instancetype)initWithTitle:(NSString *)title
{
    self = [super init];

    if (self) {
        _fpTitle = [title copy] ?: @"";
        _fpItems = [NSMutableArray array];
        _fpAutoenablesItems = NO;
    }

    return self;
}


- (NSString *)title
{
    return _fpTitle;
}


- (void)setTitle:(NSString *)title
{
    _fpTitle = [title copy] ?: @"";
}


- (void)addItem:(NSMenuItem *)item
{
    if (!item) {
        return;
    }

    [_fpItems addObject:item];
}


- (NSMenuItem *)addItemWithTitle:(NSString *)title
                          action:(SEL)action
                   keyEquivalent:(NSString *)keyEquivalent
{
    NSMenuItem *item =
        [[NSMenuItem alloc]
            initWithTitle:title
            action:action
            keyEquivalent:keyEquivalent
        ];

    [_fpItems addObject:item];

    return item;
}


- (NSMenuItem *)itemWithTitle:(NSString *)title
{
    for (NSMenuItem *item in _fpItems) {

        if ([[item title] isEqualToString:title]) {
            return item;
        }
    }

    return nil;
}


- (NSMenuItem *)itemWithTag:(NSInteger)tag
{
    for (NSMenuItem *item in _fpItems) {

        if ([item tag] == tag) {
            return item;
        }
    }

    return nil;
}


- (NSInteger)indexOfItemWithTitle:(NSString *)title
{
    NSInteger index = 0;

    for (NSMenuItem *item in _fpItems) {

        if ([[item title] isEqualToString:title]) {
            return index;
        }

        index++;
    }

    return -1;
}


- (NSInteger)indexOfItemWithTag:(NSInteger)tag
{
    NSInteger index = 0;

    for (NSMenuItem *item in _fpItems) {

        if ([item tag] == tag) {
            return index;
        }

        index++;
    }

    return -1;
}


- (NSInteger)numberOfItems
{
    return (NSInteger)_fpItems.count;
}


- (NSArray *)itemArray
{
    return [_fpItems copy];
}


- (NSMenuItem *)itemAtIndex:(NSInteger)index
{
    if (
        index < 0 ||
        index >= (NSInteger)_fpItems.count
    ) {
        return nil;
    }

    return _fpItems[(NSUInteger)index];
}


- (void)removeItem:(NSMenuItem *)item
{
    if (item) {
        [_fpItems removeObjectIdenticalTo:item];
    }
}


- (void)removeItemAtIndex:(NSInteger)index
{
    if (
        index < 0 ||
        index >= (NSInteger)_fpItems.count
    ) {
        return;
    }

    [_fpItems removeObjectAtIndex:(NSUInteger)index];
}


- (void)setAutoenablesItems:(BOOL)flag
{
    _fpAutoenablesItems = flag;
}


- (BOOL)autoenablesItems
{
    return _fpAutoenablesItems;
}


@end

#pragma mark - NSRunningApplication


@interface NSRunningApplication : NSObject

+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)identifier;

- (BOOL)activateWithOptions:(NSUInteger)options;

@end


@implementation NSRunningApplication


+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)identifier
{
    (void)identifier;

    /*
     * Do not try to activate the Dock on iPadOS.
     */
    return @[];
}


- (BOOL)activateWithOptions:(NSUInteger)options
{
    (void)options;
    return YES;
}


@end

#pragma mark - NSOpenGLContext


@interface NSOpenGLContext : NSObject

+ (instancetype)currentContext;
+ (void)clearCurrentContext;

- (void)makeCurrentContext;

- (void)update;
- (void)updateIfNeeded;

- (void)flushBuffer;
- (void)clearDrawable;

@end


@implementation NSOpenGLContext


+ (instancetype)currentContext
{
    /*
     * Factorio uses Metal here.
     * Do not emulate an active OpenGL context.
     */
    return nil;
}


+ (void)clearCurrentContext
{
    /*
     * No-op: no real CGL/NSOpenGL context is available.
     */
}


- (void)makeCurrentContext
{
}


- (void)update
{
}


- (void)updateIfNeeded
{
}


- (void)flushBuffer
{
}


- (void)clearDrawable
{
}


@end

#pragma mark - NSBitmapImageRep


@interface NSBitmapImageRep : NSObject
{
    NSData *_fpData;
    UIImage *_fpImage;

    NSMutableData *_fpBitmapData;

    CGSize _fpLogicalSize;

    NSInteger _fpPixelsWide;
    NSInteger _fpPixelsHigh;
    NSInteger _fpBytesPerRow;
    
    NSInteger _fpBitsPerSample;
    NSInteger _fpSamplesPerPixel;
    NSInteger _fpBitsPerPixel;

    BOOL _fpHasAlpha;
    BOOL _fpPlanar;

    NSUInteger _fpBitmapFormat;

    NSString *_fpColorSpaceName;
}

+ (instancetype)imageRepWithData:(NSData *)data;

- (instancetype)initWithData:(NSData *)data;


/*
 * Geometry.
 */
- (NSInteger)pixelsWide;
- (NSInteger)pixelsHigh;

- (CGSize)size;
- (void)setSize:(CGSize)size;


/*
 * Color.
 */
- (NSColorSpace *)colorSpace;
- (NSString *)colorSpaceName;


/*
 * Raw bitmap.
 */
- (unsigned char *)bitmapData;
- (void)getBitmapDataPlanes:(unsigned char **)planes;


/*
 * Bitmap metadata.
 */
- (NSInteger)bitsPerSample;
- (NSInteger)samplesPerPixel;
- (NSInteger)bitsPerPixel;

- (NSInteger)bytesPerRow;
- (NSInteger)bytesPerPlane;

- (NSInteger)numberOfPlanes;

- (BOOL)hasAlpha;
- (BOOL)isPlanar;
- (BOOL)planar;

- (NSUInteger)bitmapFormat;


/*
 * CoreGraphics backing.
 */
- (CGImageRef)CGImage;


/*
 * Private helper.
 */
- (BOOL)_fpEnsureBitmapData;

- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes
                              pixelsWide:(NSInteger)width
                              pixelsHigh:(NSInteger)height
                           bitsPerSample:(NSInteger)bitsPerSample
                         samplesPerPixel:(NSInteger)samplesPerPixel
                                hasAlpha:(BOOL)hasAlpha
                                isPlanar:(BOOL)isPlanar
                          colorSpaceName:(NSString *)colorSpaceName
                             bytesPerRow:(NSInteger)bytesPerRow
                            bitsPerPixel:(NSInteger)bitsPerPixel;

- (NSBitmapImageRep *)bitmapImageRepByRetaggingWithColorSpace:
    (NSColorSpace *)colorSpace;

- (NSBitmapImageRep *)bitmapImageRepByConvertingToColorSpace:
    (NSColorSpace *)colorSpace
                                             renderingIntent:
    (NSInteger)renderingIntent;

@end



@implementation NSBitmapImageRep


+ (instancetype)imageRepWithData:(NSData *)data
{
    if (!data) {

        return nil;
    }


    NSBitmapImageRep *rep =
        [[NSBitmapImageRep alloc]
            initWithData:data
        ];


    return rep;
}



- (instancetype)initWithData:(NSData *)data
{
    self = [super init];

    if (self) {

        _fpData =
            [data copy];


        _fpImage =
            [[UIImage alloc] initWithData:data];


        if (
            !_fpImage ||
            !_fpImage.CGImage
        ) {

            return nil;
        }


        CGImageRef image =
            _fpImage.CGImage;


        _fpPixelsWide =
            (NSInteger)CGImageGetWidth(image);

        _fpPixelsHigh =
            (NSInteger)CGImageGetHeight(image);


        _fpBytesPerRow =
            _fpPixelsWide * 4;
        
        _fpBitsPerSample = 8;
        _fpSamplesPerPixel = 4;
        _fpBitsPerPixel = 32;

        _fpHasAlpha = YES;
        _fpPlanar = NO;

        _fpBitmapFormat = 0;

        _fpColorSpaceName =
            @"NSDeviceRGBColorSpace";


        _fpLogicalSize =
            CGSizeMake(
                _fpPixelsWide,
                _fpPixelsHigh
            );


        _fpBitmapData =
            nil;

    }


    return self;
}



#pragma mark Geometry


- (NSInteger)pixelsWide
{
    return _fpPixelsWide;
}


- (NSInteger)pixelsHigh
{
    return _fpPixelsHigh;
}


- (CGSize)size
{
    return _fpLogicalSize;
}


- (void)setSize:(CGSize)size
{
    _fpLogicalSize =
        size;
}



#pragma mark Color


- (NSColorSpace *)colorSpace
{
    return
        [NSColorSpace sRGBColorSpace];
}




#pragma mark Bitmap creation


- (BOOL)_fpEnsureBitmapData
{
    if (_fpBitmapData) {
        return YES;
    }


    if (
        !_fpImage ||
        !_fpImage.CGImage ||
        _fpPixelsWide <= 0 ||
        _fpPixelsHigh <= 0
    ) {
        return NO;
    }


    NSUInteger length =
        (NSUInteger)_fpBytesPerRow *
        (NSUInteger)_fpPixelsHigh;


    _fpBitmapData =
        [[NSMutableData alloc] initWithLength:length];


    if (!_fpBitmapData) {
        return NO;
    }


    CGColorSpaceRef colorSpace =
        CGColorSpaceCreateWithName(
            kCGColorSpaceSRGB
        );


    if (!colorSpace) {

        colorSpace =
            CGColorSpaceCreateDeviceRGB();

    }


    CGBitmapInfo bitmapInfo =
        (CGBitmapInfo)kCGImageAlphaPremultipliedLast |
        (CGBitmapInfo)kCGBitmapByteOrder32Big;


    CGContextRef context =
        CGBitmapContextCreate(
            _fpBitmapData.mutableBytes,
            (size_t)_fpPixelsWide,
            (size_t)_fpPixelsHigh,
            8,
            (size_t)_fpBytesPerRow,
            colorSpace,
            bitmapInfo
        );


    CGColorSpaceRelease(
        colorSpace
    );


    if (!context) {

        _fpBitmapData = nil;

        return NO;
    }


    CGContextSetBlendMode(
        context,
        kCGBlendModeCopy
    );


    CGContextDrawImage(
        context,
        CGRectMake(
            0,
            0,
            _fpPixelsWide,
            _fpPixelsHigh
        ),
        _fpImage.CGImage
    );


    CGContextRelease(
        context
    );


    return YES;
}



#pragma mark Raw bitmap


- (unsigned char *)bitmapData
{
    if (![self _fpEnsureBitmapData]) {

        return NULL;
    }


    unsigned char *bytes =
        (unsigned char *)
            _fpBitmapData.mutableBytes;


    return bytes;
}


- (void)getBitmapDataPlanes:(unsigned char **)planes
{
    if (!planes) {
        return;
    }


    planes[0] =
        [self bitmapData];


    /*
     * The AppKit API accepts up to five plane pointers.
     * Our bitmap is packed/non-planar.
     */
    planes[1] = NULL;
    planes[2] = NULL;
    planes[3] = NULL;
    planes[4] = NULL;
}



#pragma mark Bitmap metadata

- (NSInteger)bitsPerSample
{
    return _fpBitsPerSample ?: 8;
}


- (NSInteger)samplesPerPixel
{
    return _fpSamplesPerPixel ?: 4;
}


- (NSInteger)bitsPerPixel
{
    return _fpBitsPerPixel ?: 32;
}


- (BOOL)hasAlpha
{
    return _fpHasAlpha;
}


- (BOOL)isPlanar
{
    return _fpPlanar;
}


- (BOOL)planar
{
    return _fpPlanar;
}


- (NSUInteger)bitmapFormat
{
    return _fpBitmapFormat;
}


- (NSString *)colorSpaceName
{
    return
        _fpColorSpaceName
            ?: @"NSDeviceRGBColorSpace";
}


- (NSInteger)bytesPerRow
{
    return _fpBytesPerRow;
}


- (NSInteger)bytesPerPlane
{
    return
        _fpBytesPerRow *
        _fpPixelsHigh;
}


- (NSInteger)numberOfPlanes
{
    return 1;
}



#pragma mark CoreGraphics


- (CGImageRef)CGImage
{
    return
        _fpImage.CGImage;
}

- (instancetype)initWithBitmapDataPlanes:(unsigned char **)planes
                              pixelsWide:(NSInteger)width
                              pixelsHigh:(NSInteger)height
                           bitsPerSample:(NSInteger)bitsPerSample
                         samplesPerPixel:(NSInteger)samplesPerPixel
                                hasAlpha:(BOOL)hasAlpha
                                isPlanar:(BOOL)isPlanar
                          colorSpaceName:(NSString *)colorSpaceName
                             bytesPerRow:(NSInteger)bytesPerRow
                            bitsPerPixel:(NSInteger)bitsPerPixel
{
    self = [super init];

    if (self) {

        _fpData = nil;
        _fpImage = nil;

        _fpPixelsWide = width;
        _fpPixelsHigh = height;

        _fpBitsPerSample =
            bitsPerSample;

        _fpSamplesPerPixel =
            samplesPerPixel;

        _fpHasAlpha =
            hasAlpha;

        _fpPlanar =
            isPlanar;

        _fpColorSpaceName =
            [colorSpaceName copy]
                ?: @"NSDeviceRGBColorSpace";


        if (bitsPerPixel > 0) {

            _fpBitsPerPixel =
                bitsPerPixel;

        } else {

            _fpBitsPerPixel =
                bitsPerSample *
                samplesPerPixel;
        }


        if (bytesPerRow > 0) {

            _fpBytesPerRow =
                bytesPerRow;

        } else {

            _fpBytesPerRow =
                ((_fpBitsPerPixel * width) + 7) / 8;
        }


        _fpBitmapFormat = 0;


        _fpLogicalSize =
            CGSizeMake(
                width,
                height
            );


        NSUInteger length =
            (NSUInteger)_fpBytesPerRow *
            (NSUInteger)_fpPixelsHigh;


        _fpBitmapData =
            [NSMutableData
                dataWithLength:length
            ];


        /*
         * If the caller supplies a plane, copy it to our own buffer.
         *
         * For the SDL invisible cursor path:
         *
         * planes == NULL
         *
         * This produces a zero-filled, transparent image.
         */
        if (
            planes &&
            planes[0] &&
            _fpBitmapData
        ) {

            memcpy(
                _fpBitmapData.mutableBytes,
                planes[0],
                length
            );
        }
    }


    return self;
}

- (NSBitmapImageRep *)bitmapImageRepByRetaggingWithColorSpace:
    (NSColorSpace *)colorSpace
{

    /*
     * CGBitmapContext already creates our raw bitmap
     * in kCGColorSpaceSRGB.
     *
     * AppKit retagging changes the color space interpretation/profile
     * without changing the bitmap geometry.
     *
     * This shim already uses an sRGB representation,
     * so another large copy is not needed.
     */
    _fpColorSpaceName =
        @"NSDeviceRGBColorSpace";

    return self;
}

- (NSBitmapImageRep *)bitmapImageRepByConvertingToColorSpace:
    (NSColorSpace *)colorSpace
                                             renderingIntent:
    (NSInteger)renderingIntent
{

    /*
     * Our bitmapData is created in this context:
     *
     *     kCGColorSpaceSRGB
     *
     * CGContextDrawImage therefore converts the source CGImage
     * to sRGB.
     *
     * Do not create a second bitmap, because Factorio atlases
     * require a large amount of memory.
     */
    _fpColorSpaceName =
        @"NSDeviceRGBColorSpace";

    return self;
}

@end

#pragma mark - NSImage


@interface NSImage : NSObject
{
    CGSize _fpSize;
    NSMutableArray *_fpRepresentations;
    UIImage *_fpUIImage;
}

- (instancetype)initWithSize:(CGSize)size;
- (instancetype)initWithData:(NSData *)data;

- (CGSize)size;
- (void)setSize:(CGSize)size;

- (void)addRepresentation:(id)representation;
- (NSArray *)representations;

- (BOOL)isValid;

@end


@implementation NSImage


- (instancetype)init
{
    return [self initWithSize:CGSizeZero];
}


- (instancetype)initWithSize:(CGSize)size
{
    self = [super init];

    if (self) {
        _fpSize = size;
        _fpRepresentations =
            [NSMutableArray array];
    }

    return self;
}


- (instancetype)initWithData:(NSData *)data
{
    self = [super init];

    if (self) {

        _fpRepresentations =
            [NSMutableArray array];

        _fpUIImage =
            [UIImage imageWithData:data];

        if (!_fpUIImage || !_fpUIImage.CGImage) {
            return nil;
        }

        _fpSize =
            CGSizeMake(
                CGImageGetWidth(_fpUIImage.CGImage),
                CGImageGetHeight(_fpUIImage.CGImage)
            );
        
    }

    return self;
}


- (CGSize)size
{
    return _fpSize;
}


- (void)setSize:(CGSize)size
{
    _fpSize = size;
}


- (void)addRepresentation:(id)representation
{
    if (!representation) {
        return;
    }

    [_fpRepresentations addObject:representation];

    if (
        _fpSize.width <= 0 ||
        _fpSize.height <= 0
    ) {

        if (
            [representation
                respondsToSelector:@selector(size)
            ]
        ) {

            _fpSize =
                [(NSBitmapImageRep *)representation size];
        }
    }

}


- (NSArray *)representations
{
    return [_fpRepresentations copy];
}


- (BOOL)isValid
{
    return
        _fpUIImage != nil ||
        _fpRepresentations.count > 0;
}


@end

#pragma mark - NSCursor


@interface NSCursor : NSObject

+ (instancetype)arrowCursor;
+ (instancetype)IBeamCursor;
+ (instancetype)crosshairCursor;
+ (instancetype)pointingHandCursor;
+ (instancetype)closedHandCursor;
+ (instancetype)openHandCursor;

+ (void)hide;
+ (void)unhide;

- (void)set;
- (void)push;

+ (void)pop;

- (instancetype)initWithImage:(NSImage *)image
                      hotSpot:(CGPoint)hotSpot;

+ (NSCursor *)currentCursor;

@end

static NSCursor *gFactorioCurrentCursor = nil;

@implementation NSCursor


+ (instancetype)sharedCursor
{
    static NSCursor *cursor = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        cursor = [NSCursor new];
    });

    return cursor;
}


+ (instancetype)arrowCursor
{
    return [self sharedCursor];
}


+ (instancetype)IBeamCursor
{
    return [self sharedCursor];
}


+ (instancetype)crosshairCursor
{
    return [self sharedCursor];
}


+ (instancetype)pointingHandCursor
{
    return [self sharedCursor];
}


+ (instancetype)closedHandCursor
{
    return [self sharedCursor];
}


+ (instancetype)openHandCursor
{
    return [self sharedCursor];
}


+ (void)hide
{
}


+ (void)unhide
{
}


- (void)set
{
}


- (void)push
{
}


+ (void)pop
{
}

- (instancetype)initWithImage:(NSImage *)image
                      hotSpot:(CGPoint)hotSpot
{
    self = [super init];

    return self;
}

+ (NSCursor *)currentCursor
{
    if (!gFactorioCurrentCursor) {
        gFactorioCurrentCursor = [self arrowCursor];
    }

    return gFactorioCurrentCursor;
}

@end

@interface NSAlert : NSObject
@end

@implementation NSAlert

- (void)setAlertStyle:(NSInteger)style
{
    (void)style;
}

- (void)setMessageText:(NSString *)text
{
    (void)text;
}

- (void)setInformativeText:(NSString *)text
{
    (void)text;
}

- (id)addButtonWithTitle:(NSString *)title
{
    (void)title;

    // SDL usually does not need a real NSButton
    // if it only uses the runModal result afterward.
    return nil;
}

- (NSInteger)runModal
{
    /*
     * NSAlertFirstButtonReturn
     *
     * Cocoa uses 1000 for the first button.
     * For a basic message box, this accepts the first/default choice.
     */
    return 1000;
}

@end

#pragma mark - Load-time-only classes


#define EMPTY_APPKIT_CLASS(name) \
@interface name : NSObject @end \
@implementation name @end


EMPTY_APPKIT_CLASS(NSBezierPath)
EMPTY_APPKIT_CLASS(NSGraphicsContext)
EMPTY_APPKIT_CLASS(NSOpenGLPixelFormat)

EMPTY_APPKIT_CLASS(FactorioNSColor)

@compatibility_alias NSColor FactorioNSColor;
