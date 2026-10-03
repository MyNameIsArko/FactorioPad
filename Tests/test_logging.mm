#define FACTORIO_CONFIG_TEST 1
#include "../FactorioPad/FactorioLoader.mm"
#include <sys/wait.h>

int main(void)
{
    @autoreleasepool {
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *folder = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [@"Factorio log test " stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSCAssert([files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil],
            @"create a game folder");
        NSString *path = [folder stringByAppendingPathComponent:@"FactorioPad.log"];
        [@"old launch" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        pid_t child = fork();
        NSCAssert(child >= 0, @"create a separate process for output redirection");
        if (child == 0) {
            NSError *error = nil;
            NSCAssert(FactorioStartLogging(folder, &error), @"logging must start in the selected game folder");
            printf("game output\n");
            fprintf(stderr, "game error\n");
            FactorioReportError(@"early loader error");
            NSString *log = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
            NSCAssert([log containsString:@"game output"] && [log containsString:@"game error"] &&
                [log containsString:@"early loader error"], @"all output must reach the file before the game exits");
            NSCAssert([log containsString:@"old launch"], @"reopening must retain the failed launch log");
            NSString *dataFolder = [folder stringByAppendingPathComponent:@"FactorioData"];
            [files createDirectoryAtPath:dataFolder withIntermediateDirectories:YES attributes:nil error:nil];
            NSURL *source = [NSURL fileURLWithPath:path];
            NSURL *destination = [NSURL fileURLWithPath:dataFolder];
            NSCAssert(FactorioCopyStartupLog(source, destination, &error), @"publish early output before the game starts");
            NSString *copy = [dataFolder stringByAppendingPathComponent:@"FactorioPad.log"];
            NSCAssert([[files contentsAtPath:copy] isEqual:[files contentsAtPath:path]], @"published logs must include early output");
            printf("output while the game is stalled\n");
            NSCAssert(FactorioCopyStartupLog(source, destination, &error), @"refresh output while the game is running");
            NSCAssert([[files contentsAtPath:copy] isEqual:[files contentsAtPath:path]], @"publication must replace stale output");
            NSCAssert(FactorioStartLogging(folder, &error), @"logging must survive reopening");
            printf("next app launch\n");
            NSCAssert([[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]
                containsString:@"output while the game is stalled"], @"a restart must retain game output for sharing");
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
