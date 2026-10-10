#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@interface FactorioLoader : NSObject

@property(class, nonatomic, readonly) BOOL usesNativeController;

+ (nullable NSURL *)startupLogURL;
+ (void)restoreStartupLogFolder;
+ (void)logMessage:(NSString *)message;
+ (BOOL)importSavedGameDataWithProgress:(void (^)(double fraction))progress error:(NSError **)error;
+ (BOOL)selectGameDataFromURL:(NSURL *)url progress:(void (^)(double fraction))progress error:(NSError **)error;
+ (void)startWithWindowSize:(CGSize)windowSize;

@end

NS_ASSUME_NONNULL_END
