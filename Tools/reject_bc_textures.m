// Loaded only by the native Mac debug runner. Never included in the iOS app.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <stdio.h>
#include <unistd.h>

static void RejectBC(MTLPixelFormat format, MTLTextureDescriptor *descriptor)
{
    if (format < MTLPixelFormatBC1_RGBA || format > MTLPixelFormatBC7_RGBAUnorm_sRGB) { return; }
    fprintf(stderr, "[FactorioPad GPU guard] Rejected BC texture: pixelFormat=%lu, size=%lux%lu\n",
        (unsigned long)format, (unsigned long)descriptor.width, (unsigned long)descriptor.height);
    fprintf(stderr, "%s\n", [[NSThread callStackSymbols] componentsJoinedByString:@"\n"].UTF8String);
    fflush(stderr);
    // Skip Factorio's crash handler so the first offending call stays visible.
    _exit(86);
}

__attribute__((constructor)) static void InstallBCGuard(void)
{
    @autoreleasepool {
        NSArray<id<MTLDevice>> *devices = MTLCopyAllDevices();
        if (!devices.count) {
            fprintf(stderr, "[FactorioPad GPU guard] No Metal device is available.\n");
            _exit(87);
        }
        MTLTextureDescriptor *descriptor = [MTLTextureDescriptor new];
        Class descriptorClass = object_getClass(descriptor);
        SEL formatSelector = @selector(pixelFormat);
        Method formatMethod = class_getInstanceMethod(descriptorClass, formatSelector);
        IMP originalFormat = method_getImplementation(formatMethod);
        class_replaceMethod(descriptorClass, formatSelector, imp_implementationWithBlock(^MTLPixelFormat(MTLTextureDescriptor *object) {
            MTLPixelFormat format = ((MTLPixelFormat (*)(id, SEL))originalFormat)(object, formatSelector);
            RejectBC(format, object);
            return format;
        }), method_getTypeEncoding(formatMethod));

        NSMutableSet *classes = [NSMutableSet set];
        for (id<MTLDevice> device in devices) {
            Class deviceClass = object_getClass(device);
            NSString *name = NSStringFromClass(deviceClass);
            if ([classes containsObject:name]) { continue; }
            [classes addObject:name];
            SEL support = @selector(supportsBCTextureCompression);
            Method supportMethod = class_getInstanceMethod(deviceClass, support);
            class_replaceMethod(deviceClass, support, imp_implementationWithBlock(^BOOL(id object) { return NO; }),
                method_getTypeEncoding(supportMethod));
            SEL create = @selector(newTextureWithDescriptor:);
            Method createMethod = class_getInstanceMethod(deviceClass, create);
            IMP originalCreate = method_getImplementation(createMethod);
            class_replaceMethod(deviceClass, create, imp_implementationWithBlock(^id(id object, MTLTextureDescriptor *texture) __attribute__((ns_returns_retained)) {
                // Reading pixelFormat invokes the guard even if Metal bypasses its accessor internally.
                (void)texture.pixelFormat;
                typedef id (*CreateTexture)(id, SEL, id) __attribute__((ns_returns_retained));
                return ((CreateTexture)originalCreate)(object, create, texture);
            }), method_getTypeEncoding(createMethod));
            fprintf(stderr, "[FactorioPad GPU guard] Armed for %s; BC support forced off.\n", device.name.UTF8String);
        }
        fflush(stderr);
    }
}
