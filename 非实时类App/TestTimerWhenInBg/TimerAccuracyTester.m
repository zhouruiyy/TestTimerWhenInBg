#import "TimerAccuracyTester.h"
#import <os/lock.h>
#import <mach/mach_time.h>

@interface TimerAccuracyTester () {
    dispatch_source_t _timer;
    dispatch_queue_t _queue;
    BOOL _running;
    uint64_t _startMach;
    uint64_t _lastMach;
    NSMutableData *_logData;
    os_unfair_lock _lock;
}
@property (nonatomic, copy) NSString *label;
@property (nonatomic) double intervalMs;
@property (nonatomic) NSTimeInterval durationSeconds;
@property (nonatomic, strong) NSURL *fileURL;
@end

@implementation TimerAccuracyTester

- (instancetype)initWithLabel:(NSString *)label
                   intervalMs:(double)intervalMs
              durationSeconds:(NSTimeInterval)durationSeconds
                     fileURL:(NSURL *)fileURL {
    if (self = [super init]) {
        _label = [label copy];
        _intervalMs = intervalMs;
        _durationSeconds = durationSeconds;
        _fileURL = fileURL;
        _queue = dispatch_queue_create("com.demo.timerAccuracy", DISPATCH_QUEUE_SERIAL);
        _lock = OS_UNFAIR_LOCK_INIT;
        _logData = [NSMutableData data];
    }
    return self;
}

static inline uint64_t now_mach(void) { return mach_continuous_time(); }

static inline double mach_to_ms(uint64_t dt) {
    static mach_timebase_info_data_t info;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ mach_timebase_info(&info); });
    long double nanos = (long double)dt * info.numer / info.denom;
    return (double)(nanos / 1e6);
}

- (void)start {
    if (_running) return;
    _running = YES;

    // Prepare file header
    NSString *header = [NSString stringWithFormat:@"label=%@ intervalMs=%.3f duration=%.3fs\n",
                         self.label, self.intervalMs, self.durationSeconds];
    [_logData appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [_logData appendData:[@"t(ms),dt(ms)\n" dataUsingEncoding:NSUTF8StringEncoding]];

    double intervalSec = self.intervalMs / 1000.0;
    uint64_t start = now_mach();
    _startMach = start;
    _lastMach = start;

    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    uint64_t startNs = (uint64_t)(intervalSec * NSEC_PER_SEC);

    dispatch_source_set_timer(_timer,
                              dispatch_time(DISPATCH_TIME_NOW, startNs),
                              (uint64_t)(intervalSec * NSEC_PER_SEC),
                              0);

    __unsafe_unretained typeof(self) unretainedSelf = self;
    dispatch_source_set_event_handler(_timer, ^{
        if (!unretainedSelf || !unretainedSelf->_running) return;

        uint64_t now = now_mach();
        double tMs = mach_to_ms(now - unretainedSelf->_startMach);
        double dtMs = mach_to_ms(now - unretainedSelf->_lastMach);
        unretainedSelf->_lastMach = now;

        NSString *line = [NSString stringWithFormat:@"%.3f,%.3f\n", tMs, dtMs];
        os_unfair_lock_lock(&unretainedSelf->_lock);
        [unretainedSelf->_logData appendData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        os_unfair_lock_unlock(&unretainedSelf->_lock);

        if (tMs >= unretainedSelf.durationSeconds * 1000.0) {
            [unretainedSelf stop];
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

    // Persist to file atomically
    os_unfair_lock_lock(&_lock);
    NSData *dataToWrite = [_logData copy];
    [_logData setLength:0];
    os_unfair_lock_unlock(&_lock);

    NSError *err = nil;
    [dataToWrite writeToURL:self.fileURL options:NSDataWritingAtomic error:&err];
    if (err) {
        NSLog(@"TimerAccuracyTester write error: %@", err);
    } else {
        NSLog(@"TimerAccuracyTester wrote log to: %@", self.fileURL.path);
    }

    if (self.completionHandler) {
        self.completionHandler();
    }
}

@end 