//
//  AppDelegate.h
//  TestTimerWhenInBg
//
//  Created by ZhouRui on 2025/8/12.
//

#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>

- (void)scheduleProcessingTaskAfter:(NSTimeInterval)delaySeconds;

- (void)requestStartPlainGCDOnBackground;
- (void)requestStartPlainNoBGOnBackground;
- (void)startRequestedRunnersOnBackground;

@end

