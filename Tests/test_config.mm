#define FACTORIO_CONFIG_TEST 1
#include "../FactorioPad/FactorioLoader.mm"

int main(void)
{
    @autoreleasepool {
        NSString *defaults = FactorioDefaultConfig(@"/new/read", @"/new/write");
        NSCAssert([defaults hasPrefix:@"; version=13\n"],
            @"defaults must declare the configuration format");
        NSCAssert([defaults containsString:@"[graphics]\nrender-in-native-resolution=true\nhigh-quality-animations=true\ntexture-compression-level=high-quality\n"],
            @"new installations must use high-quality animations and texture compression");
        NSCAssert([defaults containsString:@"[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale=1.5\n"],
            @"new installations must use a manual 150 percent interface scale");
        NSCAssert([defaults containsString:@"pick-ghost-cursor=true\ntooltip-delay=0.1\n"],
            @"new installations must enable ghost selection and a 0.1-second tooltip delay");
        NSCAssert([defaults containsString:@"[input]\ninput-method=keyboard-and-mouse\nheading-vehicle-driving=true\n"],
            @"heading driving must apply to the emulated keyboard input, not native controller input");
        NSCAssert(![defaults containsString:@"flat-character-gui="], @"inventory layout must stay unchanged");
        NSCAssert([defaults containsString:@"active-quick-bars=1\n"], @"new installations must show only one quickbar row");
        NSCAssert(![defaults containsString:@"quick-bar-button-1-secondary="],
            @"RB + D-pad must no longer configure second-row quickbar shortcuts");
        NSCAssert(![defaults containsString:@"[controls]\n"],
            @"new installations must keep Factorio's default key bindings");
        for (NSString *config in @[defaults,
            @"[input]\n input-method = keyboard-and-mouse \nheading-vehicle-driving=false\n[controls]\ncopy=ALT + C\n[controller]\nicons=playstation\n",
            @"[graphics]\ncustom-ui-scale=1.25\n"]) {
            NSString *native = FactorioConfigureInput(config, YES);
            NSCAssert([native containsString:@"input-method=game-controller"] &&
                ![native containsString:@"input-method=keyboard-and-mouse"], @"native mode must select controller input");
            NSCAssert([FactorioConfigureInput(native, YES) isEqualToString:native], @"native configuration must be stable");
            NSString *mapped = FactorioConfigureInput(native, NO);
            NSCAssert([mapped containsString:@"input-method=keyboard-and-mouse"] &&
                ![mapped containsString:@"input-method=game-controller"], @"switching back must restore keyboard input");
            for (NSString *setting in @[@"copy=ALT + C", @"icons=playstation", @"heading-vehicle-driving=false", @"custom-ui-scale=1.25"]) {
                if ([config containsString:setting]) NSCAssert([mapped containsString:setting], @"mode changes must preserve custom settings");
            }
        }
        NSArray *mappedArguments = FactorioStartupArguments(@"/config", @"/mods", CGSizeMake(1024, 768), NO);
        NSArray *nativeArguments = FactorioStartupArguments(@"/config", @"/mods", CGSizeMake(1024, 768), YES);
        NSCAssert([mappedArguments containsObject:@"--nogamepad"] && ![nativeArguments containsObject:@"--nogamepad"],
            @"only mapped mode must disable Factorio's gamepad support");
        NSCAssert([[mappedArguments subarrayWithRange:NSMakeRange(0, nativeArguments.count)] isEqualToArray:nativeArguments],
            @"mode changes must preserve all other startup arguments");
        FactorioConfigureEnvironment(NO);
        NSCAssert(strcmp(getenv("SDL_JOYSTICK_MFI"), "0") == 0, @"mapped mode must leave SDL controller handling disabled");
        FactorioConfigureEnvironment(YES);
        NSCAssert(strcmp(getenv("SDL_JOYSTICK_MFI"), "1") == 0 &&
            strcmp(getenv("SDL_JOYSTICK_IOKIT"), "0") == 0 && strcmp(getenv("SDL_JOYSTICK_HIDAPI"), "0") == 0,
            @"native mode must use Apple's controller driver only");
        NSString *oldControllerConfig = [defaults stringByAppendingFormat:@"\n[controls]\n%@\ncopy=ALT + C\n",
            [FactorioControllerBindings() componentsJoinedByString:@"\n"]];
        NSString *upgrade = FactorioApplyConfigSection(oldControllerConfig, @"[controls]",
            FactorioControllerBindings(), NO);
        for (NSString *binding in FactorioControllerBindings()) {
            NSCAssert(![upgrade containsString:binding],
                @"upgrading must remove every old FactorioPad shortcut");
        }
        NSCAssert([upgrade containsString:@"heading-vehicle-driving=true"] &&
            [upgrade containsString:@"copy=ALT + C"],
            @"upgrading must retain driving support and custom key bindings");
        NSCAssert([FactorioUpdateConfigPaths(defaults, @"/new/read", @"/new/write") isEqualToString:defaults],
            @"later launches must preserve the default interface scale");
        NSString *customScale = @"[interface]\nui-scale-mode=manual-display-points\ncustom-ui-scale=1.25\ncustom-proportional-ui-scale=1.25\n";
        NSCAssert([FactorioUpdateConfigPaths(customScale, @"/new/read", @"/new/write") hasPrefix:customScale],
            @"saved interface preferences must not be replaced by new defaults");
        NSString *customControls = @"[interface]\npick-ghost-cursor=false\ntooltip-delay=0.04\nactive-quick-bars=2\n[input]\nheading-vehicle-driving=false\n";
        NSCAssert([FactorioUpdateConfigPaths(customControls, @"/new/read", @"/new/write") hasPrefix:customControls],
            @"saved gameplay preferences must not be replaced by new defaults");
        NSString *customGraphics = @"[graphics]\nhigh-quality-animations=false\ntexture-compression-level=none\n";
        NSCAssert([FactorioUpdateConfigPaths(customGraphics, @"/new/read", @"/new/write") hasPrefix:customGraphics],
            @"saved graphics preferences must not be replaced by new defaults");
        for (NSString *config in @[defaults,
            @"[Graphics]\n graphics-quality = high \n high-quality-animations = true \n high-quality-shadows = true \ntexture-compression-level=none\ngpu-accelerated-compression=false\n[interface]\ncustom-ui-scale=1.25\n",
            @"[interface]\ncustom-ui-scale=1.25\n"]) {
            NSString *low = FactorioConfigureGraphics(config, YES);
            NSCAssert([low containsString:@"graphics-quality=medium"] &&
                [low containsString:@"high-quality-animations=false"] &&
                [low containsString:@"high-quality-shadows=false"] &&
                ![low containsString:@"graphics-quality=high"] &&
                ![low containsString:@"graphics-quality = high"] &&
                ![low containsString:@"high-quality-animations = true"] &&
                ![low containsString:@"high-quality-shadows = true"],
                @"low graphics must replace existing values and work without a graphics section");
            NSCAssert([FactorioConfigureGraphics(low, YES) isEqualToString:low],
                @"low graphics must remain stable across launches");
            NSString *high = FactorioConfigureGraphics(low, NO);
            NSCAssert([high containsString:@"graphics-quality=high"] &&
                [high containsString:@"high-quality-animations=true"] &&
                [high containsString:@"high-quality-shadows=true"] &&
                ![high containsString:@"graphics-quality=medium"] &&
                ![high containsString:@"high-quality-animations=false"] &&
                ![high containsString:@"high-quality-shadows=false"],
                @"switching back to high graphics must restore all preset values");
            NSCAssert([FactorioConfigureGraphics(high, NO) isEqualToString:high],
                @"high graphics must remain stable across launches");
            for (NSString *setting in @[@"custom-ui-scale=1.25", @"texture-compression-level=none", @"gpu-accelerated-compression=false"]) {
                if ([config containsString:setting]) NSCAssert([low containsString:setting] && [high containsString:setting],
                    @"graphics presets must preserve unrelated preferences and GPU compression safeguards");
            }
        }
        for (NSString *graphics in @[
            @"[graphics]\ntexture-compression-level=high-quality\ngpu-accelerated-compression=true\ngpu-accelerated-mipmap-compression=true\n[interface]\ncustom-ui-scale=1.25\n",
            @"[graphics]\n texture-compression-level = high-quality \nhigh-quality-animations=false\n[interface]\ncustom-ui-scale=1.25\n",
            @"[graphics]\nhigh-quality-animations=false\n[interface]\ncustom-ui-scale=1.25\n",
            @"[interface]\ncustom-ui-scale=1.25\n"
        ]) {
            NSString *safe = FactorioApplyConfigSection(graphics, @"[graphics]",
                @[@"texture-compression-level=none", @"gpu-accelerated-compression=false",
                  @"gpu-accelerated-mipmap-compression=false"], YES, YES);
            NSCAssert([safe containsString:@"texture-compression-level=none"] &&
                [safe containsString:@"gpu-accelerated-compression=false"] &&
                [safe containsString:@"gpu-accelerated-mipmap-compression=false"] &&
                ![safe containsString:@"texture-compression-level=high-quality"] &&
                ![safe containsString:@"texture-compression-level = high-quality"] &&
                ![safe containsString:@"gpu-accelerated-compression=true"] &&
                ![safe containsString:@"gpu-accelerated-mipmap-compression=true"],
                @"unsupported GPUs must disable compression in existing and new configurations");
            NSCAssert([safe containsString:@"custom-ui-scale=1.25"], @"the GPU fallback must preserve unrelated preferences");
            NSCAssert([FactorioApplyConfigSection(safe, @"[graphics]",
                @[@"texture-compression-level=none", @"gpu-accelerated-compression=false",
                  @"gpu-accelerated-mipmap-compression=false"], YES, YES) isEqualToString:safe], @"the fallback must survive repeated launches");
        }
        NSArray<NSString *> *examples = @[
            @"[path]\nread-data=/old\nwrite-data=/old-write\n[graphics]\nquality=high\n",
            @"[path]\n read-data = /old \n[graphics]\nquality=high\n",
            @"[graphics]\nquality=high\n",
            @"[graphics]\nquality=high\n[path]\n"
        ];
        for (NSString *example in examples) {
            NSString *updated = FactorioUpdateConfigPaths(example, @"/new/read", @"/new/write");
            NSCAssert([updated containsString:@"read-data=/new/read"], @"read-data must move with the app");
            NSCAssert([updated containsString:@"write-data=/new/write"], @"write-data must move with the sandbox");
            NSCAssert([updated containsString:@"quality=high"], @"game configuration must survive");
            NSCAssert(![updated containsString:@"/old"], @"obsolete paths must be removed");
            NSCAssert([FactorioUpdateConfigPaths(updated, @"/new/read", @"/new/write") isEqualToString:updated],
                @"repeated launches must not change the configuration");
        }
        puts("Factorio configuration tests passed.");
    }
    return 0;
}
