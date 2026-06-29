/*
 * Coolapk (CoolMarket) No-Ad Tweak v4.1
 * Strategy: NSURLProtocol network blocking + ad view placeholder removal
 * + Card-Secret verification via alert input (no Filza needed!)
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <CommonCrypto/CommonCrypto.h>
#import <sys/sysctl.h>

// ============================================================
// 🔐 Card-Secret 验证（弹窗输入 + NSUserDefaults 持久化）
// ============================================================

#define DEVICE_ID_FLAG     @"/var/mobile/Documents/.coocapk_dumpid"
#define SECRET             @"C00lApkN0Ad-S3cr3t!2024"
#define USERDEFAULTS_KEY   @"CoocapkNoAd_LicenseKey"

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
    if (![devicePrefix isEqualToString:getDeviceIdPrefix()]) return NO;
    NSString *message = [devicePrefix stringByAppendingString:payload];
    return [expectedSig.uppercaseString isEqualToString:hmacSha256(message).uppercaseString];
}

// ============================================================
// Device ID 导出弹窗（替代 Filza 文件写入）
// ============================================================

static void showDeviceIdAlert(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 等待 App UI 就绪
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            NSString *prefix = getDeviceIdPrefix();
            NSString *msg = [NSString stringWithFormat:
                @"设备前缀: %@\n\n"
                @"请将此4位前缀发给开发者获取卡密。\n\n"
                @"收到卡密后，删除 .coocapk_dumpid 文件，\n"
                @"然后重启 App 即可输入卡密。",
                prefix];
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"🦐 Coolapk NoAd - 设备信息"
                                 message:msg
                          preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"复制前缀"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *action) {
                [UIPasteboard generalPasteboard].string = prefix;
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:@"关闭"
                                                      style:UIAlertActionStyleCancel
                                                    handler:nil]];
            UIWindow *win = [UIApplication sharedApplication].keyWindow;
            [win.rootViewController presentViewController:alert animated:YES completion:nil];
        });
    });
}

// ============================================================
// 卡密输入弹窗
// ============================================================

static BOOL g_licensePromptShown = NO;

static void showLicenseInputAlert(void) {
    if (g_licensePromptShown) return;
    g_licensePromptShown = YES;

    dispatch_async(dispatch_get_main_queue(), ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"🦐 Coolapk NoAd - 授权验证"
                                 message:@"请输入卡密（复制后粘贴到输入框）"
                          preferredStyle:UIAlertControllerStyleAlert];

            [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
                tf.placeholder = @"XXXX-XXXX-XXXX-XXXX";
                tf.keyboardType = UIKeyboardTypeASCIICapable;
                tf.autocorrectionType = UITextAutocorrectionTypeNo;
            }];

            [alert addAction:[UIAlertAction actionWithTitle:@"验证"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *action) {
                NSString *key = [alert.textFields.firstObject.text
                                   stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (isValidLicenseKey(key)) {
                    // 保存到 NSUserDefaults
                    [[NSUserDefaults standardUserDefaults] setObject:key forKey:USERDEFAULTS_KEY];
                    [[NSUserDefaults standardUserDefaults] synchronize];

                    UIAlertController *ok = [UIAlertController
                        alertControllerWithTitle:@"验证成功 ✅"
                                         message:@"卡密有效！请重启 App 使广告拦截生效。"
                                  preferredStyle:UIAlertControllerStyleAlert];
                    [ok addAction:[UIAlertAction actionWithTitle:@"确定"
                                                          style:UIAlertActionStyleDefault
                                                        handler:nil]];
                    UIWindow *win = [UIApplication sharedApplication].keyWindow;
                    [win.rootViewController presentViewController:ok animated:YES completion:nil];
                } else {
                    g_licensePromptShown = NO; // 允许重新弹出
                    UIAlertController *fail = [UIAlertController
                        alertControllerWithTitle:@"验证失败 ❌"
                                         message:@"卡密无效或不匹配此设备，请检查后重试。"
                                  preferredStyle:UIAlertControllerStyleAlert];
                    [fail addAction:[UIAlertAction actionWithTitle:@"重试"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *a) {
                        showLicenseInputAlert();
                    }]];
                    [fail addAction:[UIAlertAction actionWithTitle:@"取消"
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil]];
                    UIWindow *win = [UIApplication sharedApplication].keyWindow;
                    [win.rootViewController presentViewController:fail animated:YES completion:nil];
                }
            }]];

            [alert addAction:[UIAlertAction actionWithTitle:@"取消应用"
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(UIAlertAction *action) {
                __builtin_trap();
            }]];

            UIWindow *win = [UIApplication sharedApplication].keyWindow;
            [win.rootViewController presentViewController:alert animated:YES completion:nil];
        });
    });
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
        // === 第一步：设备 ID 导出模式（Filza 标记文件） ===
        if ([[NSFileManager defaultManager] fileExistsAtPath:DEVICE_ID_FLAG]) {
            showDeviceIdAlert();
            NSLog(@"🦐 Device ID dump mode active");
            return; // 不继续执行
        }

        // === 第二步：从 NSUserDefaults 读取已存储的卡密 ===
        NSString *storedKey = [[NSUserDefaults standardUserDefaults] stringForKey:USERDEFAULTS_KEY];

        if (storedKey && isValidLicenseKey(storedKey)) {
            // 验证通过 → 启动广告拦截
            NSLog(@"🦐 License verified! Device: %@", getDeviceIdPrefix());
        } else if (storedKey) {
            // 卡密存在但无效（设备更换或篡改）→ 闪退
            NSLog(@"🦐 ❌ Invalid license key! Crashing...");
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"🦐 授权验证失败"
                                     message:@"卡密无效或不匹配此设备。"
                              preferredStyle:UIAlertControllerStyleAlert];
                UIWindow *win = [UIApplication sharedApplication].keyWindow;
                [win.rootViewController presentViewController:alert animated:YES completion:^{
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{ __builtin_trap(); });
                }];
            });
            return; // 等 crash
        } else {
            // 没有卡密 → 弹出输入框
            NSLog(@"🦐 No license key found, showing input prompt");
            showLicenseInputAlert();
            return; // 不启动广告拦截，等用户输入后重启
        }

        // === 第三步：启动广告拦截（仅验证通过后执行） ===
        NSLog(@"🦐 Coolapk No-Ad v4.1 loaded!");

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