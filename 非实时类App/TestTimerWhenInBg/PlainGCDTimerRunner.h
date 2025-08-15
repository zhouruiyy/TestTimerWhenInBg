#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PlainGCDTimerRunner : NSObject

- (instancetype)initWithIntervalMs:(double)intervalMs
                    durationSeconds:(NSTimeInterval)durationSeconds
                            fileURL:(NSURL *)fileURL;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END 