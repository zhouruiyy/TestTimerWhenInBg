#import "PlainGCDTimerRunner.h"
#import <mach/mach_time.h>
#import <os/lock.h>
#import <UIKit/UIKit.h>

@interface PlainGCDTimerRunner () {
    dispatch_source_t _timer;
    dispatch_queue_t _queue;
    BOOL _running;
    uint64_t _startMach;
    uint64_t _lastMach;
    NSMutableData *_logData;
    os_unfair_lock _lock;
    UIBackgroundTaskIdentifier _bgTaskId;
}
@property (nonatomic) double intervalMs;
@property (nonatomic) NSTimeInterval durationSeconds;
@property (nonatomic, strong) NSURL *fileURL;
@end

@implementation PlainGCDTimerRunner

- (instancetype)initWithIntervalMs:(double)intervalMs
                    durationSeconds:(NSTimeInterval)durationSeconds
                            fileURL:(NSURL *)fileURL {
    if (self = [super init]) {
        self.intervalMs = intervalMs;
        self.durationSeconds = durationSeconds;
        self.fileURL = fileURL;
        _lock = OS_UNFAIR_LOCK_INIT;
        _logData = [NSMutableData data];
        // 高优先级队列（User Initiated 相当于 QoS_UserInitiated）
        _queue = dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0);
        _bgTaskId = UIBackgroundTaskInvalid;
    }
    return self;
}

static inline uint64_t now_mach_pg(void) { return mach_continuous_time(); }
static inline double mach_to_ms_pg(uint64_t dt) {
    static mach_timebase_info_data_t info;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ mach_timebase_info(&info); });
    long double nanos = (long double)dt * info.numer / info.denom;
    return (double)(nanos / 1e6);
}

- (void)start {
    if (_running) return;
    _running = YES;

    NSString *header = [NSString stringWithFormat:@"plain GCD timer intervalMs=%.3f duration=%.3fs\n",
                        self.intervalMs, self.durationSeconds];
    [_logData appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [_logData appendData:[@"t(ms),dt(ms)\n" dataUsingEncoding:NSUTF8StringEncoding]];

    // 申请后台时间窗口（~30s），方便在后台观察触发间隔
    UIApplication *app = UIApplication.sharedApplication;
    __block __unsafe_unretained typeof(self) uSelf = self;
    _bgTaskId = [app beginBackgroundTaskWithName:@"PlainGCDTimerRunner" expirationHandler:^{
        [uSelf stop];
    }];

    double intervalSec = self.intervalMs / 1000.0;
    uint64_t start = now_mach_pg();
    _startMach = start;
    _lastMach = start;

    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_timer,
                              dispatch_time(DISPATCH_TIME_NOW, (uint64_t)(intervalSec * NSEC_PER_SEC)),
                              (uint64_t)(intervalSec * NSEC_PER_SEC),
                              0);

    dispatch_source_set_event_handler(_timer, ^{
        if (!uSelf || !uSelf->_running) return;
        uint64_t now = now_mach_pg();
        double tMs = mach_to_ms_pg(now - uSelf->_startMach);
        double dtMs = mach_to_ms_pg(now - uSelf->_lastMach);
        uSelf->_lastMach = now;
        NSString *line = [NSString stringWithFormat:@"%.3f,%.3f\n", tMs, dtMs];
        os_unfair_lock_lock(&uSelf->_lock);
        [uSelf->_logData appendData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        os_unfair_lock_unlock(&uSelf->_lock);
        if (tMs >= uSelf.durationSeconds * 1000.0) {
            [uSelf stop];
        }
    });
    dispatch_resume(_timer);
}

- (void)stop {
    if (!_running) return;
    _running = NO;
    if (_timer) {
        dispatch_source_cancel(_timer);
        _timer = nil;
    }

    os_unfair_lock_lock(&_lock);
    NSData *dataToWrite = [_logData copy];
    [_logData setLength:0];
    os_unfair_lock_unlock(&_lock);

    NSError *err = nil;
    [dataToWrite writeToURL:self.fileURL options:NSDataWritingAtomic error:&err];
    if (err) {
        NSLog(@"PlainGCDTimerRunner write error: %@", err);
    } else {
        NSLog(@"PlainGCDTimerRunner wrote log to: %@", self.fileURL.path);
    }

    if (_bgTaskId != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_bgTaskId];
        _bgTaskId = UIBackgroundTaskInvalid;
    }
}

@end 