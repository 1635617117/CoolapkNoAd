/*
 * Coolapk (CoolMarket) No-Ad Tweak v3.1
 * Strategy: NSURLProtocol network blocking + ad view placeholder removal
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

// ============================================================
// 广告域名黑名单
// ============================================================

static NSString *adBlockDomains[] = {
    @"pangolin-sdk-toutiao.com", @"i.snssdk.com", @"pangle.com",
    @"pangolin.snssdk.com", @"dm.applog.snssdk.com",
    @"sf3-fe-tos.pglstatp-toutiao.com", @"is.snssdk.com",
    @"tanx.com", @"tanx.cn", @"etao.com", @"tanx.alibaba.com",
    @"gdt.qq.com", @"e.qq.com", @"adnet.qq.com", @"lu.qq.com",
    @"toponad.com", @"toponad-sdk.com",
    @"inmobi.com", @"w.inmobi.com",
    @"mintegral.com", @"sg.mintegral.com",
    @"adservice", @"sdk.ad", @"adx", @"adsdk",
};

static const int adBlockDomainCount = sizeof(adBlockDomains) / sizeof(adBlockDomains[0]);

static NSString *adBlockPathPrefixes[] = {
    @"/ad/", @"/ads/", @"/splash/", @"/sdk/",
    @"/feed/ad", @"/advert",
};

static const int adBlockPathCount = sizeof(adBlockPathPrefixes) / sizeof(adBlockPathPrefixes[0]);

// ============================================================
// AdBlockProtocol
// ============================================================

@interface AdBlockProtocol : NSURLProtocol @end

@implementation AdBlockProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *urlStr = request.URL.absoluteString.lowercaseString;
    if (!urlStr) return NO;
    NSString *host = request.URL.host.lowercaseString;
    if (host) {
        for (int i = 0; i < adBlockDomainCount; i++) {
            if ([host containsString:adBlockDomains[i]]) return YES;
        }
    }
    NSString *path = request.URL.path.lowercaseString;
    if (path) {
        for (int i = 0; i < adBlockPathCount; i++) {
            if ([path containsString:adBlockPathPrefixes[i]]) return YES;
        }
    }
    return NO;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)r { return r; }
- (void)startLoading {
    id c = self.client;
    NSURLResponse *resp = [[NSURLResponse alloc] initWithURL:self.request.URL MIMEType:@"text/plain" expectedContentLength:0 textEncodingName:nil];
    [c URLProtocol:self didReceiveResponse:resp cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [c URLProtocol:self didLoadData:[NSData data]];
    [c URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

// ============================================================
// %hook: 广告 Cell 返回零高度
// ============================================================

%hook FeedAdvertisementCellBaseV4
- (CGFloat)cellHeight { return 0.0; }
- (CGSize)sizeThatFits:(CGSize)s { return CGSizeZero; }
- (void)layoutSubviews {
    %orig;
    [(UIView *)self setHidden:YES];
    [(UIView *)self setFrame:CGRectZero];
    [(UIView *)self removeFromSuperview];
}
%end

// ============================================================
// 前向声明
// ============================================================
static void removeSplashWindows(void);
static void removeAllAdViews(void);
static void scanViewForAds(UIView *view, int depth);
static BOOL isAdViewClass(NSString *cls);

// ============================================================
// %ctor 初始化
// ============================================================

%ctor {
    @autoreleasepool {
        NSLog(@"🦐 Coolapk No-Ad v3.1 loaded!");

        // 注册网络拦截器
        [NSURLProtocol registerClass:[AdBlockProtocol class]];

        // 启动后移除开屏
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ removeSplashWindows(); });

        // 定时清扫（更频繁：每1.5秒）
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [NSThread sleepForTimeInterval:1.0];
            while (true) {
                @autoreleasepool {
                    dispatch_async(dispatch_get_main_queue(), ^{ removeAllAdViews(); });
                }
                [NSThread sleepForTimeInterval:1.5];
            }
        });
    }
}

// ============================================================
// 广告视图检测（严格模式 — 匹配更广）
// ============================================================

static BOOL isAdViewClass(NSString *cls) {
    if (!cls) return NO;
    NSString *lc = [cls lowercaseString];

    // 精准匹配已知 CoolMarket 广告类
    // 检查类名中是否包含广告关键词（不区分大小写）
    if ([lc containsString:@"feedadvertisement"]) return YES;
    if ([lc containsString:@"feedad"]) return YES; // FeedAdLoader etc.
    if ([lc containsString:@"advertisement"]) return YES;
    if ([lc containsString:@"adsplash"]) return YES;
    if ([lc containsString:@"gmcust"]) return YES;    // GMCustom*
    if ([lc containsString:@"txad"]) return YES;     // Tanx TXAd*
    if ([lc containsString:@"tanx"]) return YES;     // Tanx*
    if ([lc containsString:@"abusplash"]) return YES; // ABU (AnyThink)
    if ([lc containsString:@"abunative"]) return YES;
    if ([lc containsString:@"sponsorprize"]) return YES;
    if ([lc containsString:@"sponsorcard"]) return YES;
    if ([lc containsString:@"gmadsdk"]) return YES;  // GMAdSDKManager
    if ([lc containsString:@"adview"]) return YES;
    if ([lc containsString:@"adload"]) return YES;   // AdLoader
    if ([lc containsString:@"admodel"]) return YES;  // AdModel
    if ([lc containsString:@"adclick"]) return YES;  // AdClick
    return NO;
}

// ============================================================
// 视图扫描
// ============================================================

static void removeSplashWindows(void) {
    @try {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            if (isAdViewClass(NSStringFromClass([window class]))) {
                [window setHidden:YES];
                [window setWindowLevel:UIWindowLevelNormal - 100];
                [window removeFromSuperview];
                NSLog(@"🦐 Removed splash window");
            }
            scanViewForAds(window, 0);
        }
    } @catch (NSException *e) {}
}

static void removeAllAdViews(void) {
    @try {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            scanViewForAds(window, 0);
        }
    } @catch (NSException *e) {}
}

static void scanViewForAds(UIView *view, int depth) {
    if (!view || depth > 30) return;
    @try {
        NSString *cls = NSStringFromClass([view class]);
        if (isAdViewClass(cls)) {
            [view setHidden:YES];
            [view removeFromSuperview];
            NSLog(@"🦐 Removed ad view: %@", cls);
            return;
        }
        for (UIView *sv in [view subviews]) {
            scanViewForAds(sv, depth + 1);
        }
    } @catch (NSException *e) {}
}