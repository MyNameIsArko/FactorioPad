#import "FactorioLoader.h"

#import "FactorioControllerBridge.h"
#import "FactorioKeyboardBridge.h"

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>
#include <unistd.h>

static NSString *const FactorioDataDirectoryName = @"FactorioPad";
static NSURL *FactorioStartupLog;
static NSURL *FactorioSharedLogFolder;
static BOOL FactorioSharedLogAccess;
static dispatch_queue_t FactorioLogQueue;
static dispatch_source_t FactorioLogTimer;
static unsigned long long FactorioCopiedLogSize;

static void FactorioLog(NSString *message)
{
    fprintf(stderr, "[FactorioPad] %s\n", message.UTF8String);
    fflush(stderr);
}

static BOOL FactorioStartLogging(NSString *dataPath, NSError **error)
{
    NSString *path = [dataPath stringByAppendingPathComponent:@"FactorioPad.log"];
    // ponytail: one append-only diagnostic log; add rotation if field logs become too large.
    int log = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0600);
    if (log < 0) {
        if (error) { *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]; }
        return NO;
    }
    fflush(stdout);
    fflush(stderr);
    int originalOut = dup(STDOUT_FILENO);
    int originalErr = dup(STDERR_FILENO);
    BOOL ready = originalOut >= 0 && originalErr >= 0 &&
        dup2(log, STDOUT_FILENO) >= 0 && dup2(log, STDERR_FILENO) >= 0;
    int failure = errno;
    if (!ready) {
        if (originalOut >= 0) { dup2(originalOut, STDOUT_FILENO); }
        if (originalErr >= 0) { dup2(originalErr, STDERR_FILENO); }
        if (error) { *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:failure userInfo:nil]; }
    } else {
        setvbuf(stdout, NULL, _IONBF, 0);
        setvbuf(stderr, NULL, _IONBF, 0);
    }
    if (originalOut >= 0) { close(originalOut); }
    if (originalErr >= 0) { close(originalErr); }
    close(log);
    return ready;
}

static void FactorioReportError(NSString *message)
{
    FactorioLog(message);
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:@"FactorioStopped"
            object:nil userInfo:@{@"message": message}];
    });
}

static void FactorioConfigureEnvironment(void)
{
    setenv("SDL_JOYSTICK_MFI", "1", 1);
    setenv("SDL_JOYSTICK_IOKIT", "0", 1);
    setenv("SDL_JOYSTICK_HIDAPI", "0", 1);
}

static NSString *FactorioWritableRoot(void)
{
    NSURL *applicationSupport = [NSFileManager.defaultManager
        URLsForDirectory:NSApplicationSupportDirectory
        inDomains:NSUserDomainMask].firstObject;

    return [applicationSupport.path
        stringByAppendingPathComponent:FactorioDataDirectoryName];
}

static BOOL FactorioCopyStartupLog(NSURL *source, NSURL *folder, NSError **error)
{
    NSURL *destination = [folder URLByAppendingPathComponent:@"FactorioPad.log"];
    NSNumber *link = nil;
    [destination getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:nil];
    if (link.boolValue) {
        if (error) { *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInvalidFileNameError
            userInfo:@{NSLocalizedDescriptionKey: @"The log destination is a symbolic link."}]; }
        return NO;
    }
    NSData *data = [NSData dataWithContentsOfURL:source options:0 error:error];
    if (!data) { return NO; }
    __block BOOL written = NO;
    __block NSError *failure = nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter:nil] coordinateWritingItemAtURL:destination
        options:NSFileCoordinatorWritingForReplacing error:&failure byAccessor:^(NSURL *url) {
            written = [data writeToURL:url options:NSDataWritingAtomic error:&failure];
        }];
    if (failure && error) { *error = failure; }
    return written;
}

#ifndef FACTORIO_CONFIG_TEST
__attribute__((constructor)) static void FactorioBeginStartupLogging(void)
{
    @autoreleasepool {
        NSString *root = FactorioWritableRoot();
        NSError *error = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES
            attributes:nil error:&error] || !FactorioStartLogging(root, &error)) {
            FactorioLog([NSString stringWithFormat:@"Cannot start logging: %@", error.localizedDescription]);
            return;
        }
        FactorioStartupLog = [NSURL fileURLWithPath:[root stringByAppendingPathComponent:@"FactorioPad.log"]];
        struct utsname device = {};
        uname(&device);
        FactorioLog([NSString stringWithFormat:@"Startup %@; FactorioPad %@ (%@)", NSDate.date,
            NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],
            NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]]);
        FactorioLog([NSString stringWithFormat:@"Device: %s; OS: %@; Memory: %llu bytes",
            device.machine, NSProcessInfo.processInfo.operatingSystemVersionString,
            NSProcessInfo.processInfo.physicalMemory]);
        FactorioLog(@"Logging started before UIApplicationMain");
    }
}
#endif

static NSArray<NSString *> *FactorioControllerBindings(void)
{
    return @[
        @"pick-items=SHIFT + E", @"drop-cursor=SHIFT + Q", @"show-info=CONTROL + SPACE",
        @"toggle-driving=CONTROL + E", @"copy=CONTROL + Q", @"cut=CONTROL + SHIFT + Q",
        @"paste=CONTROL + R", @"undo=CONTROL + SHIFT + R", @"redo=CONTROL + SHIFT + SPACE",
        @"open-technology-gui=SHIFT + M", @"production-statistics=CONTROL + M",
        @"toggle-blueprint-library=CONTROL + SHIFT + M"
    ];
}

static NSString *FactorioDefaultConfig(
    NSString *readDataPath,
    NSString *writeDataPath
)
{
    return [NSString stringWithFormat:
        // Older configuration headers trigger settings conversion.
        @"; version=13\n"
         "[path]\n"
         "read-data=%@\n"
         "write-data=%@\n"
         "\n"
         "[graphics]\n"
         "render-in-native-resolution=true\n"
         "high-quality-animations=true\n"
         "texture-compression-level=high-quality\n"
         "\n"
         "[interface]\n"
         "ui-scale-mode=manual-pixels\n"
         "custom-ui-scale=1.5\n"
         "pick-ghost-cursor=true\n"
         "tooltip-delay=0.1\n"
         "active-quick-bars=1\n"
         "\n"
         "[input]\n"
         "input-method=keyboard-and-mouse\n"
         "heading-vehicle-driving=true\n"
         "\n"
         "[controller]\n"
         "icons=xbox\n"
         "button-layout=western\n",
        readDataPath,
        writeDataPath];
}

static NSString *FactorioUpdateConfigPaths(
    NSString *config,
    NSString *readDataPath,
    NSString *writeDataPath
)
{
    NSArray<NSString *> *lines = [config componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:lines.count + 3];
    __block BOOL inPathSection = NO;
    __block BOOL foundPathSection = NO;
    __block BOOL foundReadPath = NO;
    __block BOOL foundWritePath = NO;

    void (^appendMissingPaths)(void) = ^{
        if (!foundReadPath) {
            [result addObject:[@"read-data=" stringByAppendingString:readDataPath]];
            foundReadPath = YES;
        }
        if (!foundWritePath) {
            [result addObject:[@"write-data=" stringByAppendingString:writeDataPath]];
            foundWritePath = YES;
        }
    };

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceCharacterSet];

        if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) {
            if (inPathSection) {
                appendMissingPaths();
            }
            inPathSection = [trimmed caseInsensitiveCompare:@"[path]"] == NSOrderedSame;
            foundPathSection = foundPathSection || inPathSection;
        }

        NSRange equals = [trimmed rangeOfString:@"="];
        NSString *key = equals.location == NSNotFound ? @"" : [[trimmed substringToIndex:equals.location]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (inPathSection && [key isEqualToString:@"read-data"]) {
            [result addObject:[@"read-data=" stringByAppendingString:readDataPath]];
            foundReadPath = YES;
        } else if (inPathSection && [key isEqualToString:@"write-data"]) {
            [result addObject:[@"write-data=" stringByAppendingString:writeDataPath]];
            foundWritePath = YES;
        } else {
            [result addObject:line];
        }
    }

    if (inPathSection) {
        appendMissingPaths();
    } else if (!foundPathSection) {
        [result addObjectsFromArray:@[
            @"[path]",
            [@"read-data=" stringByAppendingString:readDataPath],
            [@"write-data=" stringByAppendingString:writeDataPath]
        ]];
    }

    return [result componentsJoinedByString:@"\n"];
}

static NSString *FactorioApplyControlSection(
    NSString *config,
    NSString *section,
    NSArray<NSString *> *bindings,
    BOOL enabled
)
{
    NSArray<NSString *> *lines = [config componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:lines.count + bindings.count];
    NSMutableSet<NSString *> *present = [NSMutableSet set];
    __block BOOL inSection = NO;
    BOOL foundSection = NO;
    void (^appendMissing)(void) = ^{
        if (!enabled || !inSection) return;
        for (NSString *binding in bindings) {
            NSString *key = [[binding componentsSeparatedByString:@"="] firstObject];
            if (![present containsObject:key]) [result addObject:binding];
        }
    };

    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([trimmed hasPrefix:@"["] && [trimmed hasSuffix:@"]"]) {
            appendMissing();
            inSection = [trimmed caseInsensitiveCompare:section] == NSOrderedSame;
            foundSection = foundSection || inSection;
            [present removeAllObjects];
        }
        BOOL removeLine = NO;
        if (inSection) {
            NSRange equals = [trimmed rangeOfString:@"="];
            NSString *key = equals.location == NSNotFound ? @"" : [[trimmed substringToIndex:equals.location]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            for (NSString *binding in bindings) {
                if ([binding hasPrefix:[key stringByAppendingString:@"="]]) {
                    [present addObject:key];
                    removeLine = !enabled && [trimmed isEqualToString:binding];
                    break;
                }
            }
        }
        if (!removeLine) [result addObject:line];
    }
    appendMissing();
    if (enabled && !foundSection) {
        [result addObject:section];
        [result addObjectsFromArray:bindings];
    }
    return [result componentsJoinedByString:@"\n"];
}

#if DEBUG
static void FactorioCheckConfigUpdater(void)
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *updated = FactorioUpdateConfigPaths(
            @"[path]\nread-data=/old\n[graphics]\nfoo=bar\n",
            @"/new/read",
            @"/new/write"
        );

        NSCAssert([updated containsString:@"read-data=/new/read"], @"read-data was not updated");
        NSCAssert([updated containsString:@"write-data=/new/write"], @"write-data was not added");
        NSCAssert([updated containsString:@"foo=bar"], @"existing settings were not preserved");
    });
}
#endif

static NSString *FactorioDataProblem(NSString *path, NSString *guestVersion)
{
    NSFileManager *files = NSFileManager.defaultManager;
    NSData *infoData = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"base/info.json"]];
    id info = infoData ? [NSJSONSerialization JSONObjectWithData:infoData options:0 error:nil] : nil;
    NSString *version = [info isKindOfClass:NSDictionary.class] ? info[@"version"] : nil;
    if (![version isKindOfClass:NSString.class] ||
        ![files fileExistsAtPath:[path stringByAppendingPathComponent:@"core/info.json"]] ||
        ![files fileExistsAtPath:[path stringByAppendingPathComponent:@"cacert.pem"]]) {
        return @"Choose the FactorioData folder that contains base, core, and cacert.pem.";
    }
    if (!guestVersion.length || ![version isEqualToString:guestVersion]) {
        return @"The game data and app executable use different Factorio versions. Package your matching Mac game files into a new IPA, then sideload it.";
    }
    return nil;
}

static NSString *FactorioReadDataPath(NSString *bundleRoot, NSString *documentsRoot,
    NSString *guestVersion, NSString **message)
{
    NSString *path = [documentsRoot stringByAppendingPathComponent:@"FactorioData"];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        path = [bundleRoot stringByAppendingPathComponent:@"FactorioData"];
    }
    *message = FactorioDataProblem(path, guestVersion);
    return *message ? nil : path;
}

static NSError *FactorioGameDataError(NSString *message)
{
    return [NSError errorWithDomain:@"FactorioGameData" code:1
        userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *const FactorioGameFolderBookmark = @"FactorioGameFolderBookmark";

static BOOL FactorioSelectGameData(NSURL *source, NSUserDefaults *preferences, NSString *version, NSError **error)
{
    BOOL access = [source startAccessingSecurityScopedResource];
    __block NSError *failure = nil;
    __block NSData *bookmark = nil;
    @try {
        NSError *coordinationError = nil;
        [[[NSFileCoordinator alloc] initWithFilePresenter:nil] coordinateReadingItemAtURL:source
            options:0 error:&coordinationError byAccessor:^(NSURL *url) {
                NSString *problem = FactorioDataProblem(url.path, version);
                if (problem) { failure = FactorioGameDataError(problem); return; }
                NSDirectoryEnumerator *entries = [NSFileManager.defaultManager enumeratorAtURL:url
                    includingPropertiesForKeys:@[NSURLIsSymbolicLinkKey] options:0
                    errorHandler:^BOOL(NSURL *item, NSError *readError) { failure = readError; return NO; }];
                for (NSURL *item in entries) {
                    NSNumber *link = nil;
                    if (![item getResourceValue:&link forKey:NSURLIsSymbolicLinkKey error:&failure]) { return; }
                    if (link.boolValue) {
                        failure = FactorioGameDataError(@"Choose a game data folder without symbolic links.");
                        return;
                    }
                }
                if (!failure) {
                    bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                        includingResourceValuesForKeys:nil relativeToURL:nil error:&failure];
                }
            }];
        if (!failure) { failure = coordinationError; }
        if (!bookmark || failure) { return NO; }
        [preferences setObject:bookmark forKey:FactorioGameFolderBookmark];
        return YES;
    } @finally {
        if (access) { [source stopAccessingSecurityScopedResource]; }
        if (failure && error) { *error = failure; }
    }
}

// The caller holds folder access until the game finishes reading its files.
static NSURL *FactorioOpenGameData(NSUserDefaults *preferences, NSString *bundleRoot,
    NSString *documentsRoot, NSString *version, BOOL *access, NSError **error)
{
    *access = NO;
    NSData *bookmark = [preferences dataForKey:FactorioGameFolderBookmark];
    if (!bookmark) {
        NSString *message = nil;
        NSString *path = FactorioReadDataPath(bundleRoot, documentsRoot, version, &message);
        if (!path) { if (error) { *error = FactorioGameDataError(message); } return nil; }
        return [NSURL fileURLWithPath:path isDirectory:YES];
    }
    BOOL stale = NO;
    NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil
        bookmarkDataIsStale:&stale error:error];
    if (!url) { return nil; }
    BOOL opened = [url startAccessingSecurityScopedResource];
    BOOL ready = NO;
    @try {
        NSString *problem = FactorioDataProblem(url.path, version);
        if (problem) { if (error) { *error = FactorioGameDataError(problem); } return nil; }
        if (stale) {
            NSData *updated = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                includingResourceValuesForKeys:nil relativeToURL:nil error:error];
            if (!updated) { return nil; }
            [preferences setObject:updated forKey:FactorioGameFolderBookmark];
        }
        ready = YES;
        *access = opened;
        return url;
    } @finally {
        if (opened && !ready) { [url stopAccessingSecurityScopedResource]; }
    }
}

#ifndef FACTORIO_CONFIG_TEST
static NSString *FactorioPrepareWritableData(NSString *readDataPath)
{
#if DEBUG
    FactorioCheckConfigUpdater();
#endif

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSString *root = FactorioWritableRoot();
    NSArray<NSString *> *directories = @[
        root,
        [root stringByAppendingPathComponent:@"config"],
        [root stringByAppendingPathComponent:@"mods"],
        [root stringByAppendingPathComponent:@"saves"],
        [root stringByAppendingPathComponent:@"scenarios"],
        [root stringByAppendingPathComponent:@"temp"],
        [root stringByAppendingPathComponent:@"script-output"]
    ];

    for (NSString *directory in directories) {
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:directory
                    withIntermediateDirectories:YES
                                     attributes:@{NSFileProtectionKey: NSFileProtectionCompleteUntilFirstUserAuthentication}
                                          error:&error]) {
            FactorioReportError(@"Factorio cannot create its data folder.");
            return nil;
        }
    }

    NSString *configPath = [root stringByAppendingPathComponent:@"config/config.ini"];
    NSError *error = nil;
    NSString *config = [NSString stringWithContentsOfFile:configPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];

    if (!config && [fileManager fileExistsAtPath:configPath]) {
        FactorioReportError(@"Factorio cannot read its configuration. The app did not replace it.");
        return nil;
    }
    if (!config) {
        config = FactorioDefaultConfig(readDataPath, root);
    } else {
        config = FactorioUpdateConfigPaths(config, readDataPath, root);
        config = FactorioApplyControlSection(config, @"[input]",
            @[@"heading-vehicle-driving=true"], YES);
        config = FactorioApplyControlSection(config, @"[controls]",
            FactorioControllerBindings(), NO);
    }

    if (![config writeToFile:configPath
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:&error]) {
        FactorioReportError(@"Factorio cannot save its configuration.");
        return nil;
    }

    return configPath;
}

static void *FactorioOpenFramework(NSString *name, int flags)
{
    NSString *path = [NSBundle.mainBundle.privateFrameworksPath
        stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.framework/%@", name, name]];

    dlerror();
    void *handle = dlopen(path.fileSystemRepresentation, flags);
    if (!handle) {
        FactorioLog([NSString stringWithFormat:@"Cannot load %@: %s", name, dlerror()]);
        FactorioReportError([NSString stringWithFormat:@"Factorio cannot load %@. Close and reopen the app.", name]);
    }
    return handle;
}

@implementation FactorioLoader

+ (NSString *)guestVersion
{
    NSString *path = [NSBundle.mainBundle.privateFrameworksPath
        stringByAppendingPathComponent:@"FactorioGuest.framework/Info.plist"];
    return [NSDictionary dictionaryWithContentsOfFile:path][@"CFBundleShortVersionString"];
}

+ (NSURL *)documentsFolder
{
    return [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
}

+ (NSURL *)startupLogURL
{
    return FactorioStartupLog;
}

+ (void)logMessage:(NSString *)message
{
    FactorioLog(message);
}

+ (void)shareStartupLogWithFolder:(NSURL *)folder
{
    if (!FactorioStartupLog) { return; }
    static dispatch_once_t once;
    dispatch_once(&once, ^{ FactorioLogQueue = dispatch_queue_create("pl.adrian.FactorioPad.logs", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(FactorioLogQueue, ^{
        if ([FactorioSharedLogFolder isEqual:folder]) { return; }
        if (FactorioSharedLogAccess) { [FactorioSharedLogFolder stopAccessingSecurityScopedResource]; }
        FactorioSharedLogFolder = folder;
        FactorioSharedLogAccess = [folder startAccessingSecurityScopedResource];
        FactorioCopiedLogSize = 0;
        NSError *error = nil;
        if (!FactorioCopyStartupLog(FactorioStartupLog, folder, &error)) {
            FactorioLog([NSString stringWithFormat:@"Cannot copy the log to FactorioData: %@. Use Share log in the app.", error]);
        }
        if (!FactorioLogTimer) {
            FactorioLogTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, FactorioLogQueue);
            dispatch_source_set_timer(FactorioLogTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                NSEC_PER_SEC, NSEC_PER_SEC / 10);
            dispatch_source_set_event_handler(FactorioLogTimer, ^{
                unsigned long long size = [NSFileManager.defaultManager attributesOfItemAtPath:FactorioStartupLog.path error:nil].fileSize;
                if (size != FactorioCopiedLogSize && FactorioCopyStartupLog(FactorioStartupLog, FactorioSharedLogFolder, nil)) {
                    FactorioCopiedLogSize = size;
                }
            });
            dispatch_resume(FactorioLogTimer);
        }
    });
}

+ (void)restoreStartupLogFolder
{
    FactorioLog(@"Restoring the selected game folder for logging");
    NSData *bookmark = [NSUserDefaults.standardUserDefaults dataForKey:FactorioGameFolderBookmark];
    if (!bookmark) { return; }
    NSError *error = nil;
    NSURL *folder = [NSURL URLByResolvingBookmarkData:bookmark options:0 relativeToURL:nil
        bookmarkDataIsStale:nil error:&error];
    if (folder) { [self shareStartupLogWithFolder:folder]; }
    else { FactorioLog([NSString stringWithFormat:@"Cannot restore the log folder: %@", error.localizedDescription]); }
}

+ (NSString *)gameDataProblem
{
    NSString *version = [self guestVersion];
    if (!version.length) {
        return @"This app template needs your Factorio executable. Use the packaging tool on your computer, then sideload the resulting IPA.";
    }
    // Preserve older imports now that Documents is hidden from Files.
    if (![NSUserDefaults.standardUserDefaults dataForKey:FactorioGameFolderBookmark]) {
        NSURL *legacy = [[self documentsFolder] URLByAppendingPathComponent:@"FactorioData" isDirectory:YES];
        if ([NSFileManager.defaultManager fileExistsAtPath:legacy.path]) {
            NSError *error = nil;
            if (![self selectGameDataFromURL:legacy error:&error]) { return error.localizedDescription; }
        }
    }
    NSError *error = nil;
    BOOL access = NO;
    NSURL *url = FactorioOpenGameData(NSUserDefaults.standardUserDefaults,
        NSBundle.mainBundle.bundlePath, [self documentsFolder].path, version, &access, &error);
    if (access) { [url stopAccessingSecurityScopedResource]; }
    return error.localizedDescription;
}

+ (BOOL)selectGameDataFromURL:(NSURL *)url error:(NSError **)error
{
    FactorioLog(@"Selecting the game folder");
    BOOL selected = FactorioSelectGameData(url, NSUserDefaults.standardUserDefaults, [self guestVersion], error);
    if (selected) { [self shareStartupLogWithFolder:url]; }
    else if (error && *error) { FactorioLog((*error).localizedDescription); }
    return selected;
}

+ (void)startWithWindowSize:(CGSize)windowSize
{
    FactorioLog(@"Starting the game loader");
    FactorioConfigureEnvironment();

    NSString *guestVersion = [self guestVersion];
    if (!guestVersion.length) {
        FactorioReportError(@"This app template needs your Factorio executable. Use the packaging script on your computer, then sideload the resulting IPA.");
        return;
    }
    NSError *dataError = nil;
    BOOL access = NO;
    NSURL *dataURL = FactorioOpenGameData(NSUserDefaults.standardUserDefaults,
        NSBundle.mainBundle.bundlePath, [self documentsFolder].path, guestVersion, &access, &dataError);
    if (!dataURL) {
        FactorioReportError(dataError.localizedDescription);
        return;
    }
    BOOL threadStarted = NO;
    @try {
        NSString *readDataPath = dataURL.path;
        FactorioLog([NSString stringWithFormat:@"Factorio %@; Viewport: %.0fx%.0f",
            guestVersion, windowSize.width, windowSize.height]);
        FactorioLog(@"Preparing game configuration");
        NSString *configPath = FactorioPrepareWritableData(readDataPath);
        if (!configPath) {
            return;
        }

        NSString *writeRoot = configPath.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent;
        NSString *modsPath = [writeRoot stringByAppendingPathComponent:@"mods"];

        FactorioLog(@"Loading FactorioCompat");
        void *compat = FactorioOpenFramework(@"FactorioCompat", RTLD_NOW | RTLD_GLOBAL);
        if (!compat) {
            return;
        }

        FactorioLog(@"Loading FactorioGuest");
        void *guest = FactorioOpenFramework(@"FactorioGuest", RTLD_NOW | RTLD_LOCAL);
        if (!guest) {
            return;
        }

        FactorioLog(@"Preparing input");
        if (!FactorioKeyboardBridgeSetGuestHandle(guest)) {
            FactorioReportError(@"This Factorio game file does not provide compatible input functions.");
            return;
        }
        FactorioControllerBridgeStart();
        FactorioControllerBridgeSetViewportSize(windowSize.width, windowSize.height);

        typedef int (*FactorioMainFunction)(int, char **);
        dlerror();
        FactorioMainFunction factorioMain = (FactorioMainFunction)dlsym(guest, "main");
        if (!factorioMain) {
            FactorioLog([NSString stringWithFormat:@"Factorio main is missing: %s", dlerror()]);
            FactorioReportError(@"The Factorio game file is not compatible with this app.");
            return;
        }

        CGFloat width = MAX(windowSize.width, 1.0);
        CGFloat height = MAX(windowSize.height, 1.0);
        NSString *windowSizeArgument = [NSString stringWithFormat:@"%ldx%ld",
            lround(width), lround(height)];

        NSArray<NSString *> *arguments = @[
            @"factorio",
            @"--config", configPath,
            @"--mod-directory", modsPath,
            @"--no-log-rotation",
            @"--force-metal",
            @"--fullscreen=false",
            @"--window-size", windowSizeArgument,
            @"--nogamepad",
            @"--single-thread-loading"
        ];

        NSThread *thread = [[NSThread alloc] initWithBlock:^{
            @autoreleasepool {
                @try {
                    if (chdir(readDataPath.fileSystemRepresentation) != 0) {
                        int savedErrno = errno;
                        FactorioLog([NSString stringWithFormat:@"Cannot set the working directory: %s", strerror(savedErrno)]);
                        FactorioReportError(@"Factorio cannot open its game folder.");
                        return;
                    }

                    int argumentCount = (int)arguments.count;
                    char **argumentValues = (char **)calloc((size_t)argumentCount + 1, sizeof(char *));
                    if (!argumentValues) {
                        FactorioReportError(@"Factorio does not have enough memory to start.");
                        return;
                    }

                    for (int index = 0; index < argumentCount; index++) {
                        argumentValues[index] = strdup(arguments[(NSUInteger)index].fileSystemRepresentation);
                        if (!argumentValues[index]) {
                            for (int previous = 0; previous < index; previous++) {
                                free(argumentValues[previous]);
                            }
                            free(argumentValues);
                            FactorioReportError(@"Factorio does not have enough memory to start.");
                            return;
                        }
                    }

                    FactorioLog(@"Starting Factorio main");
                    int result = factorioMain(argumentCount, argumentValues);

                    for (int index = 0; index < argumentCount; index++) {
                        free(argumentValues[index]);
                    }
                    free(argumentValues);

                    FactorioLog([NSString stringWithFormat:@"Factorio stopped with status %d", result]);
                    FactorioControllerBridgeSetActive(NO);
                    FactorioReportError(result == 0 ? @"Factorio stopped. Close and reopen the app to play again."
                        : @"Factorio stopped because of an error. Close and reopen the app to try again.");
                } @finally {
                    if (access) { [dataURL stopAccessingSecurityScopedResource]; }
                }
            }
        }];

        thread.name = @"FactorioMainThread";
        thread.stackSize = 8 * 1024 * 1024;
        [thread start];
        threadStarted = YES;
    } @finally {
        if (access && !threadStarted) { [dataURL stopAccessingSecurityScopedResource]; }
    }
}

@end
#endif
