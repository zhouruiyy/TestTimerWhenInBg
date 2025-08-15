//
//  AppDelegate.m
//  TestTimerWhenInBg
//
//  Created by ZhouRui on 2025/8/12.
//

#import "AppDelegate.h"
#import "TimerAccuracyTester.h"
#import <BackgroundTasks/BackgroundTasks.h>
#import "PlainGCDTimerRunner.h"
#import "PlainNoBGTimerRunner.h"

static NSString * const kBGTaskIdentifier = @"com.agora.TestTimerWhenInBg.timer40ms";

@interface AppDelegate ()
@property (nonatomic, strong) TimerAccuracyTester *tester;
@property (nonatomic, assign) BOOL shouldStartPlainGCDOnBackground;
@property (nonatomic, assign) BOOL shouldStartPlainNoBGOnBackground;
@property (nonatomic, strong) PlainGCDTimerRunner *plainRunner;
@property (nonatomic, strong) PlainNoBGTimerRunner *plainNoBGrunner;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self registerBackgroundTasks];
    return YES;
}

- (void)registerBackgroundTasks {
    [[BGTaskScheduler sharedScheduler] registerForTaskWithIdentifier:kBGTaskIdentifier usingQueue:nil launchHandler:^(__kindof BGTask * _Nonnull task) {
        if ([task isKindOfClass:[BGProcessingTask class]]) {
            [self handleProcessingTask:(BGProcessingTask *)task];
        } else {
            [task setTaskCompletedWithSuccess:NO];
        }
    }];
}

- (void)handleProcessingTask:(BGProcessingTask *)task {
    __block BOOL shouldContinue = YES;
    task.expirationHandler = ^{
        shouldContinue = NO;
        [self.tester stop];
    };

    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *fileURL = [docs URLByAppendingPathComponent:@"bg_timer_log.csv"];

    self.tester = [[TimerAccuracyTester alloc] initWithLabel:@"BGProcessing-40ms"
                                                  intervalMs:40.0
                                             durationSeconds:30.0
                                                    fileURL:fileURL];
    __unsafe_unretained typeof(self) unretainedSelf = self;
    self.tester.completionHandler = ^{
        [task setTaskCompletedWithSuccess:shouldContinue];
        unretainedSelf.tester = nil;
        [unretainedSelf scheduleProcessingTaskAfter:60];
    };
    [self.tester start];
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    [self scheduleProcessingTaskAfter:5];
}

- (void)scheduleProcessingTaskAfter:(NSTimeInterval)delaySeconds {
    BGProcessingTaskRequest *request = [[BGProcessingTaskRequest alloc] initWithIdentifier:kBGTaskIdentifier];
    request.requiresNetworkConnectivity = NO;
    request.requiresExternalPower = NO;
    request.earliestBeginDate = [NSDate dateWithTimeIntervalSinceNow:delaySeconds];
    NSError *error = nil;
    BOOL ok = [[BGTaskScheduler sharedScheduler] submitTaskRequest:request error:&error];
    if (!ok) {
        NSLog(@"Failed to submit BGProcessingTaskRequest: %@", error);
    } else {
        NSLog(@"Submitted BGProcessingTaskRequest, earliest in %.0fs", delaySeconds);
    }
}

#pragma mark - Plain timer start on background

- (void)requestStartPlainGCDOnBackground {
    self.shouldStartPlainGCDOnBackground = YES;
}

- (void)requestStartPlainNoBGOnBackground {
    self.shouldStartPlainNoBGOnBackground = YES;
}

- (void)startRequestedRunnersOnBackground {
    NSURL *docs = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];

    if (self.shouldStartPlainGCDOnBackground) {
        self.shouldStartPlainGCDOnBackground = NO;
        NSURL *fileURL = [docs URLByAppendingPathComponent:@"plain_timer_log.csv"];
        self.plainRunner = [[PlainGCDTimerRunner alloc] initWithIntervalMs:40.0 durationSeconds:30.0 fileURL:fileURL];
        [self.plainRunner start];
        NSLog(@"Started PlainGCDTimerRunner on background");
    }

    if (self.shouldStartPlainNoBGOnBackground) {
        self.shouldStartPlainNoBGOnBackground = NO;
        NSURL *fileURL2 = [docs URLByAppendingPathComponent:@"plain_nobg_timer_log.csv"];
        self.plainNoBGrunner = [[PlainNoBGTimerRunner alloc] initWithIntervalMs:40.0 durationSeconds:30.0 fileURL:fileURL2];
        [self.plainNoBGrunner start];
        NSLog(@"Started PlainNoBGTimerRunner on background");
    }
}

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
}

@end
