#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface FactorioLoader : NSObject

+ (nullable NSString *)gameDataProblem;
+ (nullable NSURL *)startupLogURL;
+ (void)restoreStartupLogFolder;
+ (void)logMessage:(NSString *)message;
+ (BOOL)selectGameDataFromURL:(NSURL *)url error:(NSError **)error;
+ (void)startWithWindowSize:(CGSize)windowSize;

@end

NS_ASSUME_NONNULL_END
