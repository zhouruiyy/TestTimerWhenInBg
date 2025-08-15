#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TimerAccuracyTester : NSObject

@property (nonatomic, copy, nullable) void (^completionHandler)(void);

- (instancetype)initWithLabel:(NSString *)label
                   intervalMs:(double)intervalMs
              durationSeconds:(NSTimeInterval)durationSeconds
                     fileURL:(NSURL *)fileURL;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END 