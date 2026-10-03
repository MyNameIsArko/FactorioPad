#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface FactorioLoader : NSObject

+ (nullable NSString *)gameDataProblem;
+ (BOOL)prepareSharedGameFolderWithError:(NSError **)error;
+ (BOOL)selectGameDataFromURL:(NSURL *)url error:(NSError **)error;
+ (void)startWithWindowSize:(CGSize)windowSize;

@end

NS_ASSUME_NONNULL_END
