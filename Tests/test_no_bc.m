#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <assert.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    @autoreleasepool {
        assert(argc == 2);
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        assert(device && !device.supportsBCTextureCompression);
        MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:
            (MTLPixelFormat)strtoul(argv[1], NULL, 10) width:4 height:4 mipmapped:NO];
        assert([device newTextureWithDescriptor:descriptor] != nil);
        return 0;
    }
}
