#define FACTORIO_CONFIG_TEST 1
#include "../FactorioPad/FactorioLoader.mm"

int main(void)
{
    @autoreleasepool {
        NSString *defaults = FactorioDefaultConfig(@"/new/read", @"/new/write");
        NSCAssert([defaults hasPrefix:@"; version=13\n"],
            @"Factorio 2.0.77 must read the defaults as current-format configuration");
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
        NSString *oldControllerConfig = [defaults stringByAppendingFormat:@"\n[controls]\n%@\ncopy=ALT + C\n",
            [FactorioControllerBindings() componentsJoinedByString:@"\n"]];
        NSString *upgrade = FactorioApplyControlSection(oldControllerConfig, @"[controls]",
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
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *bundle = [temporary stringByAppendingPathComponent:@"bundle"];
        NSString *documents = [temporary stringByAppendingPathComponent:@"documents"];
        NSString *bundledData = [bundle stringByAppendingPathComponent:@"FactorioData"];
        NSString *copiedData = [documents stringByAppendingPathComponent:@"FactorioData"];
        NSString *message = nil;
        NSFileManager *files = NSFileManager.defaultManager;
        NSCAssert(!FactorioReadDataPath(bundle, documents, @"2.0.77", &message), @"missing data must stop startup");
        for (NSString *root in @[bundledData, copiedData]) {
            for (NSString *folder in @[@"base", @"core"]) {
                NSCAssert([files createDirectoryAtPath:[root stringByAppendingPathComponent:folder]
                    withIntermediateDirectories:YES attributes:nil error:nil], @"create test folder");
            }
            [@"{\"version\":\"2.0.77\"}" writeToFile:[root stringByAppendingPathComponent:@"base/info.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [@"{}" writeToFile:[root stringByAppendingPathComponent:@"core/info.json"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
            [@"certificate" writeToFile:[root stringByAppendingPathComponent:@"cacert.pem"]
                atomically:YES encoding:NSUTF8StringEncoding error:nil];
            NSCAssert([FactorioReadDataPath(bundle, documents, @"2.0.77", &message) isEqualToString:root],
                @"copied data must take priority over bundled data");
        }
        NSCAssert(!FactorioReadDataPath(bundle, documents, @"2.0.78", &message), @"mismatched data must stop startup");
        [@"[]" writeToFile:[copiedData stringByAppendingPathComponent:@"base/info.json"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSCAssert(!FactorioReadDataPath(bundle, documents, @"2.0.77", &message),
            @"invalid copied data must not silently fall back to bundled data");
        NSURL *documentsURL = [NSURL fileURLWithPath:documents isDirectory:YES];
        NSError *importError = nil;
        NSCAssert(FactorioPrepareSharedFolder(documentsURL, &importError), @"shared folder setup must succeed");
        NSCAssert([files fileExistsAtPath:[documents stringByAppendingPathComponent:@"README.txt"]],
            @"Documents must contain a file on first launch");
        NSCAssert(FactorioPrepareSharedFolder(documentsURL, &importError), @"repeated setup must succeed");
        NSString *suite = [@"FactorioGameFolderTests-" stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSURL *source = [NSURL fileURLWithPath:bundledData isDirectory:YES];
        NSCAssert(FactorioSelectGameData(source, preferences, @"2.0.77", &importError),
            @"a valid game folder must be remembered without copying");
        NSData *savedBookmark = [preferences dataForKey:FactorioGameFolderBookmark];
        NSCAssert(savedBookmark.length, @"selection must save a bookmark");
        BOOL access = NO;
        NSURL *opened = FactorioOpenGameData([[NSUserDefaults alloc] initWithSuiteName:suite],
            bundle, documents, @"2.0.77", &access, &importError);
        NSCAssert([opened.path.stringByResolvingSymlinksInPath isEqualToString:bundledData.stringByResolvingSymlinksInPath], @"startup must use the selected folder in place");
        if (access) { [opened stopAccessingSecurityScopedResource]; }
        NSCAssert(FactorioDataProblem(copiedData, @"2.0.77"), @"selection must not replace old copied data");
        NSCAssert([files contentsOfDirectoryAtPath:documents error:nil].count == 2,
            @"selection must not create copies or temporary folders");
        NSCAssert(!FactorioSelectGameData(source, preferences, @"2.0.78", &importError),
            @"a mismatched selection must fail");
        NSCAssert([[preferences dataForKey:FactorioGameFolderBookmark] isEqual:savedBookmark],
            @"failed selections must retain the previous bookmark");
        NSString *link = [bundledData stringByAppendingPathComponent:@"outside-link"];
        NSCAssert([files createSymbolicLinkAtPath:link withDestinationPath:@"/tmp" error:nil], @"create a test link");
        NSCAssert(!FactorioSelectGameData(source, preferences, @"2.0.77", &importError),
            @"selections must reject symbolic links");
        NSCAssert([[preferences dataForKey:FactorioGameFolderBookmark] isEqual:savedBookmark],
            @"rejected selections must retain the previous bookmark");
        [files removeItemAtPath:link error:nil];
        [@"{}" writeToFile:[bundledData stringByAppendingPathComponent:@"base/info.json"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSCAssert(!FactorioOpenGameData(preferences, bundle, documents, @"2.0.77", &access, &importError),
            @"invalid selected data must stop startup");
        [@"{\"version\":\"2.0.77\"}" writeToFile:[copiedData stringByAppendingPathComponent:@"base/info.json"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [files removeItemAtURL:source error:nil];
        NSCAssert(!FactorioOpenGameData(preferences, bundle, documents, @"2.0.77", &access, &importError),
            @"a missing selected folder must not fall back to an old copy");
        [preferences setObject:[@"invalid bookmark" dataUsingEncoding:NSUTF8StringEncoding]
            forKey:FactorioGameFolderBookmark];
        NSCAssert(!FactorioOpenGameData(preferences, bundle, documents, @"2.0.77", &access, &importError),
            @"a damaged bookmark must report an error");
        [preferences removePersistentDomainForName:suite];
        [files removeItemAtPath:temporary error:nil];
        puts("Factorio external data tests passed.");
    }
    return 0;
}
