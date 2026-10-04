#define FACTORIO_CONFIG_TEST 1
#include "../FactorioPad/FactorioLoader.mm"
#include <sys/wait.h>

static NSString *WaitForLog(NSString *path, NSString *message)
{
    for (int attempt = 0; attempt < 200; attempt++) {
        NSString *log = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if ([log containsString:message]) { return log; }
        usleep(10000);
    }
    NSCAssert(NO, @"log output must reach the file promptly");
    return nil;
}

int main(void)
{
    @autoreleasepool {
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [@"Factorio log test " stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSCAssert([files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil],
            @"create a game folder");
        NSString *path = [folder stringByAppendingPathComponent:@"FactorioPad.log"];
        NSString *oldLog = [[@"old launch\n" stringByPaddingToLength:6 * 1024 * 1024 withString:@"x" startingAtIndex:0]
            stringByAppendingString:@"\nrecent old launch\n"];
        [oldLog writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        pid_t child = fork();
        NSCAssert(child >= 0, @"create a separate process for output redirection");
        if (child == 0) {
            NSError *error = nil;
            NSCAssert(FactorioStartLogging(folder, &error), @"logging must start in the selected game folder");
            printf("game output\n");
            fprintf(stderr, "game error\n");
            FactorioReportError(@"early loader error");
            NSString *log = WaitForLog(path, @"early loader error");
            NSCAssert([log containsString:@"game output"] && [log containsString:@"game error"] &&
                [log containsString:@"early loader error"], @"all output must reach the file before the game exits");
            NSCAssert([log containsString:@"old launch"], @"reopening must retain the failed launch log");
            NSCAssert([log containsString:@"recent old launch"] && log.length < FactorioLogLimit,
                @"an oversized old log must retain its first failure and recent output");
            NSString *dataFolder = [folder stringByAppendingPathComponent:@"FactorioData"];
            [files createDirectoryAtPath:dataFolder withIntermediateDirectories:YES attributes:nil error:nil];
            NSURL *source = [NSURL fileURLWithPath:path];
            NSURL *destination = [NSURL fileURLWithPath:dataFolder];
            NSCAssert(FactorioCopyStartupLog(source, destination, &error), @"publish early output before the game starts");
            NSString *copy = [dataFolder stringByAppendingPathComponent:@"FactorioPad.log"];
            NSCAssert([[files contentsAtPath:copy] isEqual:[files contentsAtPath:path]], @"published logs must include early output");
            printf("output while the game is stalled\n");
            WaitForLog(path, @"output while the game is stalled");
            NSCAssert(FactorioCopyStartupLog(source, destination, &error), @"refresh output while the game is running");
            NSCAssert([[files contentsAtPath:copy] isEqual:[files contentsAtPath:path]], @"publication must replace stale output");
            char flood[8192];
            memset(flood, 'x', sizeof(flood));
            for (int i = 0; i < 1024; i++) {
                NSCAssert(FactorioWriteLogBytes(STDERR_FILENO, flood, sizeof(flood)),
                    @"output must keep draining after the log reaches its limit");
            }
            WaitForLog(path, @"Log limit reached");
            NSCAssert([files attributesOfItemAtPath:path error:nil].fileSize <= FactorioLogLimit,
                @"a crash loop must not grow the file beyond 4 MiB");
            NSCAssert(FactorioCopyStartupLog(source, destination, &error) &&
                [files attributesOfItemAtPath:copy error:nil].fileSize <= FactorioLogLimit,
                @"the shared log must stay within the same limit");
            NSCAssert(FactorioStartLogging(folder, &error), @"logging must survive reopening");
            printf("next app launch\n");
            log = WaitForLog(path, @"next app launch");
            NSCAssert([log containsString:@"early loader error"] && [log containsString:@"Log limit reached"],
                @"a restart must retain the first failure and the limit marker");
            for (int session = 0; session < 2; session++) {
                FactorioLog([NSString stringWithFormat:@"recent startup failure %d", session]);
                for (int i = 0; i < 1024; i++) {
                    NSCAssert(FactorioWriteLogBytes(STDOUT_FILENO, flood, sizeof(flood)), @"stdout must also stay bounded");
                }
                NSCAssert(FactorioStartLogging(folder, &error), @"repeated failed launches must remain shareable");
            }
            printf("launch after several failures\n");
            log = WaitForLog(path, @"launch after several failures");
            NSCAssert([log containsString:@"recent startup failure 1"] &&
                [files attributesOfItemAtPath:path error:nil].fileSize <= FactorioLogLimit,
                @"history trimming must preserve the most recent failure and leave room for a new launch");
            close(STDOUT_FILENO);
            close(STDERR_FILENO);
            NSCAssert(dispatch_semaphore_wait(FactorioLogWriterDone,
                dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0, @"the writer must finish when output closes");
            _exit(0);
        }
        int status = 0;
        NSCAssert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0,
            @"logging in the child process must succeed");
        NSError *error = nil;
        NSCAssert(!FactorioStartLogging([folder stringByAppendingPathComponent:@"missing"], &error) && error,
            @"an inaccessible game folder must report an error without redirecting output");
        NSString *protectedFile = [folder stringByAppendingPathComponent:@"protected.txt"];
        [@"keep this" writeToFile:protectedFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [files removeItemAtPath:path error:nil];
        NSCAssert([files createSymbolicLinkAtPath:path withDestinationPath:protectedFile error:nil],
            @"create a log symlink");
        NSCAssert(!FactorioStartLogging(folder, &error), @"logging must not overwrite a symlink target");
        NSCAssert([[NSString stringWithContentsOfFile:protectedFile encoding:NSUTF8StringEncoding error:nil]
            isEqualToString:@"keep this"], @"a rejected log path must leave the target intact");
        NSString *publishedPath = [folder stringByAppendingPathComponent:@"FactorioData/FactorioPad.log"];
        [files removeItemAtPath:publishedPath error:nil];
        NSCAssert([files createSymbolicLinkAtPath:publishedPath withDestinationPath:protectedFile error:nil],
            @"create a publication symlink");
        error = nil;
        NSCAssert(!FactorioCopyStartupLog([NSURL fileURLWithPath:protectedFile],
            [NSURL fileURLWithPath:publishedPath.stringByDeletingLastPathComponent], &error) && error,
            @"publication must report a symlink error without overwriting its target");
        [files removeItemAtPath:folder error:nil];
        puts("Factorio startup logging tests passed.");
    }
    return 0;
}
