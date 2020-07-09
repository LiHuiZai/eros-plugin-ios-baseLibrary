//
//  BMWebViewController.m
//  BM-JYT
//
//  Created by XHY on 2017/2/28.
//  Copyright © 2017年 XHY. All rights reserved.
//

#import "BMWebViewController.h"
#import "JYTTitleLabel.h"
#import <Masonry/Masonry.h>
#import "NSTimer+Addition.h"
#import "BMMediatorManager.h"
#import <UINavigationController+FDFullscreenPopGesture.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import "BMUserInfoModel.h"
#import "BMNative.h"
#import "UIColor+Util.h"
#import "WKWebView+BMExtend.h"
#import "<WebKit/WebKit.h>"
@interface BMWebViewController () <WKUIDelegate,WKNavigationDelegate, JSExport>
{
    BOOL _showProgress;
}

@property (nonatomic, strong) JSContext *jsContext;
@property (nonatomic, strong) WKWebView *webView;

/** 伪进度条 */
@property (nonatomic, strong) CAShapeLayer *progressLayer;
/** 进度条定时器 */
@property (nonatomic, strong) NSTimer *timer;

/** 要打开的url */
@property (nonatomic, copy) NSString *urlStr;

@end

@implementation BMWebViewController

- (void)dealloc
{
    NSLog(@"dealloc >>>>>>>>>>>>> BMWebViewController");
    if (_jsContext) {
        _jsContext[@"bmnative"] = nil;
        _jsContext = nil;
    }
}

- (instancetype)initWithRouterModel:(BMWebViewRouterModel *)model
{
    if (self = [super init])
    {
        self.routerInfo = model;
        [self subInit];
    }
    return self;
}

- (void)subInit
{
    CGFloat height = K_SCREEN_HEIGHT - K_STATUSBAR_HEIGHT - K_NAVBAR_HEIGHT;
    if (!self.routerInfo.navShow) {
        height = K_SCREEN_HEIGHT;
    }

    // 减去 Indicator 高度
    height -= K_TOUCHBAR_HEIGHT;

    self.webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, K_SCREEN_WIDTH, height)];
    self.webView.backgroundColor = self.routerInfo.backgroundColor? [UIColor colorWithHexString:self.routerInfo.backgroundColor]: K_BACKGROUND_COLOR;
    self.webView.scrollView.bounces = NO;
    self.webView.UIDelegate = self;
    self.webView.navigationDelegate=self;

    self.view.backgroundColor = self.routerInfo.backgroundColor? [UIColor colorWithHexString:self.routerInfo.backgroundColor]: K_BACKGROUND_COLOR;

    self.urlStr = self.routerInfo.url;
    [self reloadURL];
    
    /* 获取js的运行环境 */
    self.jsContext = [self.webView valueForKeyPath:@"documentView.webView.mainFrame.javaScriptContext"];
    [self injectionJsMethod];
}

- (CAShapeLayer *)progressLayer
{
    if (!_progressLayer) {
        
        UIBezierPath *path = [[UIBezierPath alloc] init];
        [path moveToPoint:CGPointMake(0, self.navigationController.navigationBar.height - 2)];
        [path addLineToPoint:CGPointMake(K_SCREEN_WIDTH, self.navigationController.navigationBar.height - 2)];
        _progressLayer = [CAShapeLayer layer];
        _progressLayer.path = path.CGPath;
        _progressLayer.strokeColor = [UIColor lightGrayColor].CGColor;
        _progressLayer.fillColor = K_CLEAR_COLOR.CGColor;
        _progressLayer.lineWidth = 2;
        
        _progressLayer.strokeStart = 0.0f;
        _progressLayer.strokeEnd = 0.0f;
        
        [self.navigationController.navigationBar.layer addSublayer:_progressLayer];
    }
    return _progressLayer;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [[BMMediatorManager shareInstance] setCurrentViewController:self];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    if (_timer) {
        [_timer invalidate];
        _timer = nil;
    }
    
    if (_progressLayer) {
        [_progressLayer removeFromSuperlayer];
        _progressLayer = nil;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    /* 解析 router 数据 */
    self.navigationItem.title = self.routerInfo.title;
    
    self.view.backgroundColor = K_BACKGROUND_COLOR;
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.edgesForExtendedLayout = UIRectEdgeNone;
    
    /* 判断是否需要隐藏导航栏 并设置weex页面高度
     注：使用FDFullscreenPopGesture方法设置，自定义pop返回动画
     */
    if (!self.routerInfo.navShow) {
        self.fd_prefersNavigationBarHidden = YES;
    } else {
        self.fd_prefersNavigationBarHidden = NO;
    }
    
    /* 返回按钮 */
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"NavBar_BackItemIcon"] style:UIBarButtonItemStylePlain target:self action:@selector(backItemClicked)];
    self.navigationItem.leftBarButtonItem = backItem;

    [self.view addSubview:self.webView];
    
    _showProgress = YES;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)backItemClicked
{
    if ([self.webView canGoBack]) {
        
        _showProgress = NO;
        [self.webView goBack];
        
        if ([self.webView canGoBack] && [self.navigationItem.leftBarButtonItems count] < 2) {
            //
            //  barbuttonitems
            //
            UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"NavBar_BackItemIcon"] style:UIBarButtonItemStylePlain target:self action:@selector(backItemClicked)];
            UIBarButtonItem *closeItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(closeItemClicked)];
            self.navigationItem.leftBarButtonItems = @[backItem, closeItem];
        }
        
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

- (void)closeItemClicked
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.navigationController popViewControllerAnimated:YES];
    });
}

- (void)reloadURL
{
    if ([self.urlStr isHasChinese]) {
        self.urlStr = [self.urlStr stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    }
    NSString *loadURL = [NSString stringWithFormat:@"%@",self.urlStr];
    NSURL *url = [NSURL URLWithString:loadURL];
    url = [url.scheme isEqualToString:BM_LOCAL] ? TK_RewriteBMLocalURL(loadURL) : url;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [self.webView loadRequest:request];
}

// 当内容开始返回时调用
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation;{
    if (!self.timer) {
           self.timer = [NSTimer scheduledTimerWithTimeInterval:0.15 target:self selector:@selector(progressAnimation:) userInfo:nil repeats:YES];
       }
       
       if (_showProgress) {
           
           [self.timer resumeTimer];
           
       }
       
       _showProgress = YES;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation{
}

// 页面加载完成之后调用
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation{
    [self.webView checkCurrentFontSize];
    NSString *docTitle;
    [webView evaluateJavaScript:@"document.title" completionHandler:^(id _Nullable title, NSError * _Nullable error) {
         if ([title length]>0) {
             self.navigationItem.title = title;
             
         }
    }];
    if (_timer != nil) {
        [_timer pauseTimer];
    }
    
    if (_progressLayer) {
        _progressLayer.strokeEnd = 1.0f;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [_progressLayer removeFromSuperlayer];
            _progressLayer = nil;
        });
    }

}

- (void)webView:(WKWebView *)webView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(NSError *)error{
    if (_timer != nil) {
        [_timer pauseTimer];
    }
    
    if (_progressLayer) {
        [_progressLayer removeFromSuperlayer];
        _progressLayer = nil;
    }
    
}
- (void)progressAnimation:(NSTimer *)timer
{
    self.progressLayer.strokeEnd += 0.005f;
    
    NSLog(@"%f",self.progressLayer.strokeEnd);
    
    if (self.progressLayer.strokeEnd >= 0.9f) {
        [_timer pauseTimer];
    }
}


/**
 注入 js 方法
 */
- (void)injectionJsMethod
{
    /* 注入一个关闭当前页面的方法 */
    BMNative *bmnative = [[BMNative alloc] init];
    self.jsContext[@"bmnative"] = bmnative;
}

@end
