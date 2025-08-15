#import "SignalPosixTimerRunner.h"
#import <mach/mach_time.h>
#import <os/lock.h>
#import <signal.h>
#import <time.h>
#import <TargetConditionals.h>
#import <pthread.h>

// Determine availability of POSIX timers; force off on iOS
#if defined(_POSIX_TIMERS) && (_POSIX_TIMERS > 0)
#define POSIX_TIMERS_CLAIMED 1
#else
#define POSIX_TIMERS_CLAIMED 0
#endif
#if TARGET_OS_IPHONE
#undef POSIX_TIMERS_CLAIMED
#define POSIX_TIMERS_CLAIMED 0
#endif

static void s_posix_timer_handler(int signum);
static void *s_timer_thread(void *arg);

@interface SignalPosixTimerRunner () {
    BOOL _running;
    NSMutableData *_logData;
    os_unfair_lock _lock;
    uint64_t _startMach;
    uint64_t _lastMach;
#if POSIX_TIMERS_CLAIMED
    timer_t _timerId;
#else
    pthread_t _thread;
#endif
}
@property (nonatomic) double intervalMs;
@property (nonatomic) NSTimeInterval durationSeconds;
@property (nonatomic, strong) NSURL *fileURL;
@end

@implementation SignalPosixTimerRunner

- (instancetype)initWithIntervalMs:(double)intervalMs
                    durationSeconds:(NSTimeInterval)durationSeconds
                            fileURL:(NSURL *)fileURL {
    if (self = [super init]) {
        _intervalMs = intervalMs;
        _durationSeconds = durationSeconds;
        _fileURL = fileURL;
        _lock = OS_UNFAIR_LOCK_INIT;
        _logData = [NSMutableData data];
#if POSIX_TIMERS_CLAIMED
        _timerId = (timer_t)0;
#else
        _thread = (pthread_t)0;
#endif
    }
    return self;
}

static inline uint64_t now_mach_sp(void) { return mach_continuous_time(); }
static inline double mach_to_ms_sp(uint64_t dt) {
    static mach_timebase_info_data_t info;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ mach_timebase_info(&info); });
    long double nanos = (long double)dt * info.numer / info.denom;
    return (double)(nanos / 1e6);
}
static inline uint64_t ns_to_mach(uint64_t ns) {
    static mach_timebase_info_data_t info;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ mach_timebase_info(&info); });
    // ticks = ns * denom / numer
    return (uint64_t)(((__uint128_t)ns * info.denom) / info.numer);
}

static __unsafe_unretained SignalPosixTimerRunner *g_runner = nil;
static void s_posix_timer_handler(int signum) {
    SignalPosixTimerRunner *runner = g_runner;
    if (!runner || !runner->_running) return;

    uint64_t now = now_mach_sp();
    double tMs = mach_to_ms_sp(now - runner->_startMach);
    double dtMs = mach_to_ms_sp(now - runner->_lastMach);
    runner->_lastMach = now;

    NSString *line = [NSString stringWithFormat:@"%.3f,%.3f\n", tMs, dtMs];
    os_unfair_lock_lock(&runner->_lock);
    [runner->_logData appendData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    os_unfair_lock_unlock(&runner->_lock);

    if (tMs >= runner->_durationSeconds * 1000.0) {
        [runner stop];
    }
}

- (void)start {
    if (_running) return;
    _running = YES;

    NSString *header = [NSString stringWithFormat:@"posix-like timer intervalMs=%.3f duration=%.3fs\n",
                        self.intervalMs, self.durationSeconds];
    [_logData appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [_logData appendData:[@"t(ms),dt(ms)\n" dataUsingEncoding:NSUTF8StringEncoding]];

    _startMach = now_mach_sp();
    _lastMach = _startMach;

#if POSIX_TIMERS_CLAIMED
    struct sigaction sa;
    sa.sa_handler = s_posix_timer_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGALRM, &sa, NULL);

    struct sigevent sev = {0};
    sev.sigev_notify = SIGEV_SIGNAL;
    sev.sigev_signo = SIGALRM;

    if (timer_create(CLOCK_MONOTONIC, &sev, &_timerId) != 0) {
        NSLog(@"SignalPosixTimerRunner timer_create failed");
        _running = NO;
        return;
    }

    struct itimerspec its;
    memset(&its, 0, sizeof(its));
    double intervalSec = self.intervalMs / 1000.0;
    its.it_value.tv_sec = (time_t)intervalSec;
    its.it_value.tv_nsec = (long)((intervalSec - its.it_value.tv_sec) * 1e9);
    its.it_interval = its.it_value;

    if (timer_settime(_timerId, 0, &its, NULL) != 0) {
        NSLog(@"SignalPosixTimerRunner timer_settime failed");
        timer_delete(_timerId);
        _timerId = (timer_t)0;
        _running = NO;
        return;
    }

    g_runner = self;
#else
    // Fallback on iOS: dedicated thread + mach_wait_until for periodic schedule
    g_runner = self;
    int rc = pthread_create(&_thread, NULL, s_timer_thread, (__bridge void *)self);
    if (rc != 0) {
        NSLog(@"SignalPosixTimerRunner pthread_create failed: %d", rc);
        _running = NO;
    }
#endif
}

- (void)stop {
    if (!_running) return;
    _running = NO;
#if POSIX_TIMERS_CLAIMED
    if (_timerId) {
        timer_delete(_timerId);
        _timerId = (timer_t)0;
    }
#else
    if (_thread) {
        pthread_join(_thread, NULL);
        _thread = (pthread_t)0;
    }
#endif

    os_unfair_lock_lock(&_lock);
    NSData *dataToWrite = [_logData copy];
    [_logData setLength:0];
    os_unfair_lock_unlock(&_lock);

    NSError *err = nil;
    [dataToWrite writeToURL:self.fileURL options:NSDataWritingAtomic error:&err];
    if (err) {
        NSLog(@"SignalPosixTimerRunner write error: %@", err);
    } else {
        NSLog(@"SignalPosixTimerRunner wrote log to: %@", self.fileURL.path);
    }
}

static void *s_timer_thread(void *arg) {
    SignalPosixTimerRunner *runner = (__bridge SignalPosixTimerRunner *)arg;
    double intervalSec = runner.intervalMs / 1000.0;
    uint64_t period_ticks = ns_to_mach((uint64_t)(intervalSec * 1e9));
    uint64_t next = now_mach_sp() + period_ticks;
    while (runner->_running) {
        mach_wait_until(next);
        s_posix_timer_handler(SIGALRM);
        next += period_ticks;
    }
    return NULL;
}

@end 