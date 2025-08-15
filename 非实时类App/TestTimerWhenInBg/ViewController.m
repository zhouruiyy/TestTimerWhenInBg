//
//  ViewController.m
//  TestTimerWhenInBg
//
//  Created by ZhouRui on 2025/8/12.
//

#import "ViewController.h"
#import "AppDelegate.h"
#import "PlainGCDTimerRunner.h"
#import "PlainNoBGTimerRunner.h"

@interface ViewController ()
@property (nonatomic, strong) PlainGCDTimerRunner *plainRunner;
@property (nonatomic, strong) PlainNoBGTimerRunner *plainNoBGrunner;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"Schedule BG 40ms Test" forState:UIControlStateNormal];
    button.frame = CGRectMake(40, 120, 260, 44);
    [button addTarget:self action:@selector(onSchedule) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(40, 180, self.view.bounds.size.width - 80, 60)];
    label.numberOfLines = 0;
    label.text = @"后台触发后，BGProcessing 日志: Documents/bg_timer_log.csv";
    [self.view addSubview:label];

    UIButton *plainBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [plainBtn setTitle:@"Flag Plain GCD (start on background)" forState:UIControlStateNormal];
    plainBtn.frame = CGRectMake(40, 260, 300, 44);
    [plainBtn addTarget:self action:@selector(onFlagPlainGCD) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:plainBtn];

    UILabel *label2 = [[UILabel alloc] initWithFrame:CGRectMake(40, 320, self.view.bounds.size.width - 80, 60)];
    label2.numberOfLines = 0;
    label2.text = @"Plain GCD（进入后台后启动）: Documents/plain_timer_log.csv";
    [self.view addSubview:label2];

    UIButton *noBgBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [noBgBtn setTitle:@"Flag Plain NO-BG (start on background)" forState:UIControlStateNormal];
    noBgBtn.frame = CGRectMake(40, 380, 300, 44);
    [noBgBtn addTarget:self action:@selector(onFlagPlainNoBG) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:noBgBtn];

    UILabel *label3 = [[UILabel alloc] initWithFrame:CGRectMake(40, 440, self.view.bounds.size.width - 80, 60)];
    label3.numberOfLines = 0;
    label3.text = @"Plain NO-BG（进入后台后启动）: Documents/plain_nobg_timer_log.csv";
    [self.view addSubview:label3];
}

- (void)onSchedule {
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    [app scheduleProcessingTaskAfter:5];
}

- (void)onFlagPlainGCD {
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if ([app respondsToSelector:@selector(requestStartPlainGCDOnBackground)]) {
        [app requestStartPlainGCDOnBackground];
    }
}

- (void)onFlagPlainNoBG {
    AppDelegate *app = (AppDelegate *)UIApplication.sharedApplication.delegate;
    if ([app respondsToSelector:@selector(requestStartPlainNoBGOnBackground)]) {
        [app requestStartPlainNoBGOnBackground];
    }
}

@end
