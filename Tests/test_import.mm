#define FACTORIO_CONFIG_TEST 1
#include "../FactorioPad/FactorioLoader.mm"

static void MakeGameData(NSString *path)
{
    NSDictionary *contents = @{
        @"base/info.json": @"{\"version\":\"2.0.77\"}",
        @"core/info.json": @"{}",
        @"cacert.pem": @"certificate",
        @"core/prototypes/utility-sprites.lua": @"white_mask = { flags = { \"alpha-mask\", \"always-compressed\" }, width = 1, height = 1 }",
        @"core/graphics/white-square.png": @"white mask pixels",
        @"core/graphics/icons/mip/feedback.png": @"feedback pixels",
        @"core/graphics/missing-preview.png": @"preview pixels",
        @"base/sound/ambient/main-menu.ogg": @"main menu sound"
    };
    for (NSString *relative in contents) {
        NSString *file = [path stringByAppendingPathComponent:relative];
        NSCAssert([NSFileManager.defaultManager createDirectoryAtPath:file.stringByDeletingLastPathComponent
            withIntermediateDirectories:YES attributes:nil error:nil], @"create test data");
        NSCAssert([contents[relative] writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil], @"write test data");
    }
}

int main(void)
{
    @autoreleasepool {
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *root = [temporary stringByAppendingPathComponent:@"Documents"];
        NSCAssert([FactorioWritableRoot() isEqualToString:[files URLsForDirectory:NSDocumentDirectory
            inDomains:NSUserDomainMask].firstObject.path], @"the app must store files directly in Documents");
        NSString *oldRoot = [temporary stringByAppendingPathComponent:@"Library/Application Support/FactorioPad"];
        MakeGameData(FactorioImportedDataPath(oldRoot));
        NSString *oldSave = [oldRoot stringByAppendingPathComponent:@"saves/old.zip"];
        [files createDirectoryAtPath:oldSave.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [@"old save" writeToFile:oldSave atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *sourcePath = [temporary stringByAppendingPathComponent:@"Inbox/FactorioData"];
        NSString *destination = FactorioImportedDataPath(root);
        NSURL *source = [NSURL fileURLWithPath:sourcePath isDirectory:YES];
        MakeGameData(sourcePath);
        NSString *save = [root stringByAppendingPathComponent:@"saves/existing.zip"];
        [files createDirectoryAtPath:save.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [@"keep my save" writeToFile:save atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"old large log" writeToFile:[sourcePath stringByAppendingPathComponent:@"FactorioPad.log"]
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
        __block double lastProgress = -1;
        __block NSUInteger reports = 0;
        FactorioImportProgress progress = ^(double fraction) {
            NSCAssert(fraction >= lastProgress && fraction >= 0 && fraction <= 1, @"progress must increase within its range");
            if (!reports) { NSCAssert(fraction == 0, @"import starts at zero"); }
            if (fraction == 1) { NSCAssert(!FactorioDataProblem(destination, @"2.0.77"), @"100 percent means a complete published import"); }
            lastProgress = fraction;
            reports++;
        };
        NSError *error = nil;
        NSCAssert(!FactorioRestoreGameData(root, @"/missing", @"2.0.77", ^(double) {}, &error) && error,
            @"old Application Support data must not satisfy a fresh Documents installation");
        NSCAssert(![files fileExistsAtPath:destination] &&
            ![files fileExistsAtPath:[root stringByAppendingPathComponent:@"saves/old.zip"]] &&
            [[NSString stringWithContentsOfFile:oldSave encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"old save"] &&
            !FactorioDataProblem(FactorioImportedDataPath(oldRoot), @"2.0.77"),
            @"v2.1 must leave old assets and saves intact without copying them");
        error = nil;
        NSCAssert(FactorioImportGameData(source, root, @"2.0.77", progress, &error),
            @"a manual import must create a permanent Documents copy");
        NSCAssert(lastProgress == 1 && reports > 2, @"copy progress must include intermediate updates");
        NSCAssert([[files contentsAtPath:[destination stringByAppendingPathComponent:@"base/sound/ambient/main-menu.ogg"]]
            isEqual:[files contentsAtPath:[sourcePath stringByAppendingPathComponent:@"base/sound/ambient/main-menu.ogg"]]],
            @"audio and nested files must copy without changing their contents");
        NSCAssert(![files fileExistsAtPath:[destination stringByAppendingPathComponent:@"FactorioPad.log"]], @"do not import old diagnostic logs");
        NSString *spritePath = [destination stringByAppendingPathComponent:@"core/prototypes/utility-sprites.lua"];
        NSString *safe = [NSString stringWithContentsOfFile:spritePath encoding:NSUTF8StringEncoding error:nil];
        NSCAssert([[files contentsAtPath:[destination stringByAppendingPathComponent:@"core/prototypes/utility-sprites.lua"]]
            isEqual:[files contentsAtPath:[sourcePath stringByAppendingPathComponent:@"core/prototypes/utility-sprites.lua"]]],
            @"import must preserve sprite prototypes because the binary patch handles mask formats");
        [files removeItemAtURL:source error:nil];
        NSCAssert(FactorioRestoreGameData(root, @"/missing", @"2.0.77", ^(double) {
            NSCAssert(NO, @"later launches must not copy the old folder");
        }, &error), @"launch must work after the Inbox folder disappears");
        NSCAssert(FactorioOpenImportedData(root, @"2.0.77", &error), @"gameplay must use the private copy");
        error = nil;
        NSCAssert(!FactorioOpenImportedData(root, @"2.0.78", &error) && error, @"mismatched data must stop startup");
        MakeGameData(sourcePath);
        lastProgress = -1;
        reports = 0;
        error = nil;
        NSCAssert(!FactorioImportGameData(source, root, @"2.0.78", progress, &error) && error, @"reject mismatched imports");
        NSString *link = [sourcePath stringByAppendingPathComponent:@"outside-link"];
        [files createSymbolicLinkAtPath:link withDestinationPath:@"/tmp" error:nil];
        NSCAssert(!FactorioImportGameData(source, root, @"2.0.77", ^(double) {}, &error), @"reject symlinks");
        [files removeItemAtPath:link error:nil];
        NSString *missing = [sourcePath stringByAppendingPathComponent:@"core/graphics/missing-preview.png"];
        [files removeItemAtPath:missing error:nil];
        NSCAssert(!FactorioImportGameData(source, root, @"2.0.77", ^(double) {}, &error) &&
            [error.localizedDescription containsString:@"missing-preview.png"], @"reject missing assets before replacing working data");
        MakeGameData(sourcePath);
        __block BOOL interrupted = NO;
        NSCAssert(!FactorioImportGameData(source, root, @"2.0.77", ^(double fraction) {
            if (fraction > 0 && fraction < 1 && !interrupted) {
                interrupted = YES;
                [files removeItemAtURL:source error:nil];
            }
        }, &error) && interrupted, @"an interrupted copy must fail");
        NSCAssert(!FactorioDataProblem(destination, @"2.0.77") &&
            [[NSString stringWithContentsOfFile:spritePath encoding:NSUTF8StringEncoding error:nil] isEqualToString:safe],
            @"a failed replacement must preserve all previously imported files");
        NSCAssert(![files fileExistsAtPath:[root stringByAppendingPathComponent:@"FactorioData.importing"]], @"failed imports must remove partial copies");
        MakeGameData(sourcePath);
        [files createDirectoryAtPath:[root stringByAppendingPathComponent:@"FactorioData.importing"]
            withIntermediateDirectories:YES attributes:nil error:nil];
        NSCAssert(FactorioImportGameData(source, root, @"2.0.77", ^(double) {}, &error), @"a retry must replace abandoned staging data: %@", error);
        NSString *previous = [root stringByAppendingPathComponent:@"FactorioData.previous"];
        [files moveItemAtPath:destination toPath:previous error:nil];
        NSCAssert(FactorioOpenImportedData(root, @"2.0.77", &error), @"recover the previous import if the app closes during replacement");
        NSCAssert([[NSString stringWithContentsOfFile:save encoding:NSUTF8StringEncoding error:nil] isEqualToString:@"keep my save"],
            @"imports and recovery must leave existing saves intact");
        NSCAssert(FactorioRestoreGameData([temporary stringByAppendingPathComponent:@"DevelopmentDocuments"],
            sourcePath.stringByDeletingLastPathComponent, @"2.0.77", ^(double) {}, &error), @"development builds must import their bundled data");
        [files removeItemAtPath:temporary error:nil];
        puts("Factorio data import tests passed.");
    }
    return 0;
}
