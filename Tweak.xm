/*
 * Coolapk (CoolMarket) No-Ad Tweak v3.1
 * Strategy: NSURLProtocol network blocking + ad view placeholder removal
 * + Card-Secret verification (HMAC device-bound license)
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sys/sysctl.h>

// ============================================================
// 🔐 Card-Secret 验证（需要 /var/mobile/Documents/.coocapk_license 文件）
// ============================================================

#define LICENSE_FILE_PATH  @"/var/mobile/Documents/.coocapk_license"
#define DEVICE_ID_FLAG     @"/var/mobile/Documents/.coocapk_dumpid"
#define SECRET             @"C00lApkN0Ad-S3cr3t!2024"

static NSString *getDeviceId(void) {
    NSString *vendorId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
    if (!vendorId) {
        size_t size = 64;
        char hw_uuid[64] = {0};
        sysctlbyname("kern.uuid", hw_uuid, &size, NULL, 0);
        vendorId = [NSString stringWithUTF8String:hw_uuid];
    }
    return [[vendorId stringByReplacingOccurrencesOfString:@"-" withString:@""] uppercaseString];
}

static NSString *getDeviceIdPrefix(void) {
    NSString *deviceId = getDeviceId();
    return (deviceId.length >= 4) ? [[deviceId substringToIndex:4] uppercaseString] : @"XXXX";
}

static NSString *hmacSha256(NSString *data) {
    if (!data) return @"";
    const char *cKey = [SECRET UTF8String];
    const char *cData = [data UTF8String];
    unsigned char hmac[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, cKey, strlen(cKey), cData, strlen(cData), hmac);
    return [NSString stringWithFormat:@"%02x%02x%02x%02x",
        hmac[0], hmac[1], hmac[2], hmac[3]];
}

static BOOL isValidLicenseKey(NSString *key) {
    if (!key || key.length < 8) return NO;
    NSString *clean = [[key stringByReplacingOccurrencesOfString:@"-" withString:@""]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clean.length != 16) return NO;
    NSString *devicePrefix = [clean substringToIndex:4];
    NSString *payload      = [clean substringWithRange:NSMakeRange(4, 8)];
    NSString *expectedSig  = [clean substringFromIndex:12];
    // 设备绑定检查
    if (![devicePrefix isEqualToString:getDeviceIdPrefix()]) return NO;
    // HMAC 签名验证
    NSString *message = [devicePrefix stringByAppendingString:payload];
    return [expectedSig.uppercaseString isEqualToString:hmacSha256(message).uppercaseString];
}

static NSString *readLicenseFile(void) {
    if ([[NSFileManager defaultManager] fileExistsAtPath:LICENSE_FILE_PATH]) {
        return [[NSString stringWithContentsOfFile:LICENSE_FILE_PATH
                                         encoding:NSUTF8StringEncoding error:nil]
                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return nil;
}

static void writeDeviceIdDump(void) {
    NSString *content = [NSString stringWithFormat:
        @"Device ID (full): %@\n"
        @"Device ID (prefix 4 chars): %@\n\n"
        @"Send the 4-char prefix above to get your license key.\n"
        @"Then save the key to: %@\n"
        @"Then delete this file and .coocapk_dumpid.\n",
        getDeviceId(), getDeviceIdPrefix(), LICENSE_FILE_PATH];
    [content writeToFile:@"/var/mobile/Documents/.coocapk_device_id.txt"
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

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
// AdBlockProtocol (NSURLProtocol)
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
    NSURLResponse *resp = [[NSURLResponse alloc] initWithURL:self.request.URL
                                                   MIMEType:@"text/plain"
                                      expectedContentLength:0 textEncodingName:nil];
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
        // === 第一步：设备 ID 导出模式 ===
        if ([[NSFileManager defaultManager] fileExistsAtPath:DEVICE_ID_FLAG]) {
            writeDeviceIdDump();
            NSLog(@"🦐 Device ID dumped. Remove the flag file and re-inject.");
            return; // 不继续执行广告拦截
        }

        // === 第二步：卡密验证 ===
        NSString *key = readLicenseFile();
        if (!isValidLicenseKey(key)) {
            NSLog(@"🦐 ❌ Invalid or missing license key! App will crash.");
            // 延迟后闪退
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"🦐 Coolapk NoAd"
                                     message:@"授权验证失败\n请检查卡密文件"
                              preferredStyle:UIAlertControllerStyleAlert];
                UIWindow *win = [UIApplication sharedApplication].keyWindow;
                [win.rootViewController presentViewController:alert animated:YES completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{ __builtin_trap(); });
                }];
            });
            // 不要退出，等 crash 触发
        }

        // === 第三步：启动广告拦截 ===
        NSLog(@"🦐 Coolapk No-Ad v3.1 loaded! Device: %@", getDeviceIdPrefix());

        [NSURLProtocol registerClass:[AdBlockProtocol class]];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ removeSplashWindows(); });

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
// 广告视图检测
// ============================================================

static BOOL isAdViewClass(NSString *cls) {
    if (!cls) return NO;
    NSString *lc = [cls lowercaseString];
    if ([lc containsString:@"feedadvertisement"]) return YES;
    if ([lc containsString:@"feedad"]) return YES;
    if ([lc containsString:@"advertisement"]) return YES;
    if ([lc containsString:@"adsplash"]) return YES;
    if ([lc containsString:@"gmcust"]) return YES;
    if ([lc containsString:@"txad"]) return YES;
    if ([lc containsString:@"tanx"]) return YES;
    if ([lc containsString:@"abusplash"]) return YES;
    if ([lc containsString:@"abunative"]) return YES;
    if ([lc containsString:@"sponsorprize"]) return YES;
    if ([lc containsString:@"sponsorcard"]) return YES;
    if ([lc containsString:@"gmadsdk"]) return YES;
    if ([lc containsString:@"adview"]) return YES;
    if ([lc containsString:@"adload"]) return YES;
    if ([lc containsString:@"admodel"]) return YES;
    if ([lc containsString:@"adclick"]) return YES;
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