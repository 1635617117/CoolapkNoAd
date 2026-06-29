/*
 * Coolapk (CoolMarket) No-Ad Tweak v3.0
 * Target: CoolMarket.app v15.8.2
 * Strategy: Network-level ad blocking via NSURLProtocol
 *
 * 方案说明：
 * - 完全不依赖 ObjC/Swift 类名
 * - 拦截广告 SDK 的网络请求（按域名/URL特征）
 * - 开屏广告由定时扫描+移除处理
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ============================================================
// 广告域名黑名单
// ============================================================

static NSString *adBlockDomains[] = {
    // 穿山甲 / Pangle (ByteDance)
    @"pangolin-sdk-toutiao.com",
    @"i.snssdk.com",
    @"pangle.com",
    @"pangolin.snssdk.com",
    @"dm.applog.snssdk.com",
    @"sf3-fe-tos.pglstatp-toutiao.com",
    @"is.snssdk.com",

    // Tanx (Alibaba)
    @"tanx.com",
    @"tanx.cn",
    @"etao.com",
    @"tanx.alibaba.com",

    // 腾讯 GDT / 优量汇
    @"gdt.qq.com",
    @"e.qq.com",
    @"adnet.qq.com",
    @"lu.qq.com",

    // TopOn
    @"toponad.com",
    @"toponad-sdk.com",

    // Inmobi
    @"inmobi.com",
    @"w.inmobi.com",

    // Mintegral
    @"mintegral.com",
    @"sg.mintegral.com",

    // 通用广告特征
    @"adservice",
    @"sdk.ad",
    @"adx",
    @"adsdk",
};

static const int adBlockDomainCount = sizeof(adBlockDomains) / sizeof(adBlockDomains[0]);

// ============================================================
// 广告 URL 路径特征
// ============================================================

static NSString *adBlockPathPrefixes[] = {
    @"/ad/", @"/ads/", @"/splash/", @"/sdk/",
    @"/feed/ad", @"/advert",
};

static const int adBlockPathCount = sizeof(adBlockPathPrefixes) / sizeof(adBlockPathPrefixes[0]);

// ============================================================
// 自定义 NSURLProtocol — 拦截广告请求
// ============================================================

@interface AdBlockProtocol : NSURLProtocol
@end

@implementation AdBlockProtocol

// 判断是否应该拦截
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *urlStr = request.URL.absoluteString.lowercaseString;
    if (!urlStr) return NO;

    // 检查域名黑名单
    NSString *host = request.URL.host.lowercaseString;
    if (host) {
        for (int i = 0; i < adBlockDomainCount; i++) {
            if ([host containsString:adBlockDomains[i]]) {
                NSLog(@"🦐 Blocked ad request: %@", urlStr);
                return YES;
            }
        }
    }

    // 检查 URL 路径特征
    NSString *path = request.URL.path.lowercaseString;
    if (path) {
        for (int i = 0; i < adBlockPathCount; i++) {
            if ([path containsString:adBlockPathPrefixes[i]]) {
                NSLog(@"🦐 Blocked ad request (path): %@", urlStr);
                return YES;
            }
        }
    }

    return NO;
}

// 返回自定义的请求（返回 nil 来阻止请求）
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

// 开始加载 — 直接返回空数据，不发起实际请求
- (void)startLoading {
    id<NSURLProtocolClient> client = self.client;
    NSURLResponse *response = [[NSURLResponse alloc] initWithURL:self.request.URL
                                                        MIMEType:@"text/plain"
                                           expectedContentLength:0
                                                textEncodingName:nil];
    [client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [client URLProtocol:self didLoadData:[NSData data]];
    [client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
    // 啥也不做
}

@end

// ============================================================
// 构造函数
// ============================================================

%ctor {
    @autoreleasepool {
        NSLog(@"🦐 Coolapk No-Ad v3.0 loaded!");

        // === 注册网络拦截器 ===
        [NSURLProtocol registerClass:[AdBlockProtocol class]];
        NSLog(@"🦐 AdBlockProtocol registered!");

        // === 启动后清理开屏广告 ===
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            removeSplashWindows();
        });

        // === 定时扫描 + 移除广告视图（每3秒一次）===
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            [NSThread sleepForTimeInterval:1.0];
            while (true) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    removeAdViews();
                });
                [NSThread sleepForTimeInterval:3.0];
            }
        });
    }
}

// 移除开屏窗口
static void removeSplashWindows(void) {
    @try {
        for (UIWindow *window in [UIApplication sharedApplication].windows) {
            NSString *cls = NSStringFromClass([window class]);
            if ([cls containsString:@"Splash"] ||
                [cls containsString:@"GMAd"] ||
                [cls containsString:@"AdSplash"] ||
                [cls containsString:@"TXAd"]) {
                [window setHidden:YES];
                [window setWindowLevel:UIWindowLevelNormal - 100];
                [window removeFromSuperview];
                NSLog(@"🦐 Removed splash window: %@", cls);
            }
        }
    } @catch (NSException *e) {}
}

// 扫描视图层级，隐藏广告视图
static void removeAdViews(void) {
    @try {
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) return;
        scanViewForAds(keyWindow, 0);
    } @catch (NSException *e) {}
}

static void scanViewForAds(UIView *view, int depth) {
    if (!view || depth > 20) return;

    NSString *cls = NSStringFromClass([view class]);
    BOOL isAdView = NO;

    // 检查类名
    if ([cls containsString:@"Splash"] ||
        [cls containsString:@"FeedAd"] ||
        [cls containsString:@"GMAd"] ||
        [cls containsString:@"GMCustomFeed"] ||
        [cls containsString:@"GMCustomSplash"] ||
        [cls containsString:@"Sponsor"] ||
        [cls containsString:@"TXAd"]) {
        isAdView = YES;
    }

    // 检查是否展示广告图
    if (!isAdView && [cls containsString:@"AdView"]) {
        isAdView = YES;
    }

    if (isAdView) {
        [view setHidden:YES];
        [view removeFromSuperview];
        NSLog(@"🦐 Removed ad view: %@", cls);
        return;
    }

    for (UIView *sv in view.subviews) {
        scanViewForAds(sv, depth + 1);
    }
}