/*
 * Coolapk (CoolMarket) No-Ad Tweak v2.1
 * Target: CoolMarket.app v15.8.2
 * Strategy: Safe runtime swizzle + targeted method hooks
 *
 * 安全原则：
 * - 每个方法用 imp_implementationWithBlock 精确匹配签名（避免泛型 C 函数 calling convention 问题）
 * - init 方法不返回 nil（避免空指针崩溃）
 * - 每个 swizzle 单独 try-catch
 * - 不 hook UIView（不影响全局）
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

// ============================================================
// 安全 swizzle 辅助函数
// ============================================================

static Class SafeClass(NSString *name) {
    Class c = NSClassFromString(name);
    if (!c) c = NSClassFromString([@"CoolMarket." stringByAppendingString:name]);
    return c;
}

static void SafeSwizzle(Class cls, SEL sel, IMP newImp) {
    if (!cls || !sel || !newImp) return;
    @try {
        Method m = class_getInstanceMethod(cls, sel);
        if (m) {
            method_setImplementation(m, newImp);
            NSLog(@"🦐 Hooked %@.%@", NSStringFromClass(cls), NSStringFromSelector(sel));
        }
    } @catch (NSException *e) {}
}

static void SafeClassSwizzle(Class cls, SEL sel, IMP newImp) {
    if (!cls || !sel || !newImp) return;
    @try {
        Method m = class_getClassMethod(cls, sel);
        if (m) {
            method_setImplementation(m, newImp);
        }
    } @catch (NSException *e) {}
}

// 递归清理广告视图（前向声明供 %ctor 使用）
static void cleanupSplashViews(UIView *view) {
    if (!view) return;
    NSString *vclass = NSStringFromClass([view class]);
    if ([vclass containsString:@"Splash"] || [vclass containsString:@"GMCustomSplash"]) {
        [view setHidden:YES];
        [view removeFromSuperview];
    }
    for (UIView *sv in view.subviews) {
        cleanupSplashViews(sv);
    }
}

// ============================================================
// %hook 编译时 hook（安全的 ObjC 类）
// ============================================================

%hook FeedAdvertisementManager
- (void)requestAds:(id)request { }
- (id)nextAdModel { return nil; }
%end

%hook FeedAdvertisementCellBaseV4
- (CGFloat)cellHeight { return 0.0; }
- (void)layoutSubviews {
    %orig;
    [(UIView *)self setHidden:YES];
    [(UIView *)self setFrame:CGRectZero];
}
- (void)setAdModel:(id)model {
    [(UIView *)self setHidden:YES];
    [(UIView *)self removeFromSuperview];
}
%end

%hook FeedAdvertisementSponsorTypeInfo
+ (id)shared { return nil; }
%end

%hook CSJAdSDKManager
+ (void)setAppId:(id)appId { }
%end

// ============================================================
// %ctor 运行时 swizzle
// ============================================================

%ctor {
    @autoreleasepool {
        NSLog(@"🦐 Coolapk No-Ad v2.1 loaded!");

        // === 1. 信息流广告 Loaders ===
        for (NSString *cn in @[
            @"FeedAdvertisementLoader", @"FeedAdvertisementLoader_Official",
            @"FeedAdvertisementLoader_Topon", @"FeedAdvertisementLoader_GMSelfDraw",
            @"FeedAdLoader",
            @"GeneralEntityListFeedAdvertisementLoader_Official",
            @"GeneralEntityListFeedAdvertisementLoader_Topon",
            @"GeneralEntityListFeedAdvertisementLoader_GMSelfDraw",
            @"EntityListFeedAdvertisementLoader_Unsupported",
        ]) {
            Class cls = SafeClass(cn);
            if (!cls) continue;
            SafeSwizzle(cls, @selector(loadFeedAdvertisement),
                imp_implementationWithBlock(^(id _self) {}));
            SafeSwizzle(cls, @selector(loadAd),
                imp_implementationWithBlock(^(id _self) {}));
            SafeSwizzle(cls, @selector(loadAds),
                imp_implementationWithBlock(^(id _self) {}));
        }

        // === 2. 广告管理器 ===
        Class adMgr = SafeClass(@"FeedAdvertisementManager");
        if (adMgr) {
            SafeSwizzle(adMgr, @selector(loadAdWithCount:),
                imp_implementationWithBlock(^(id _self, NSInteger c) {}));
        }

        Class genMgr = SafeClass(@"GeneralEntityListFeedAdvertisementManager");
        if (genMgr) {
            SafeSwizzle(genMgr, @selector(loadAds),
                imp_implementationWithBlock(^(id _self) {}));
        }

        // === 3. 开屏广告 ===
        for (NSString *cn in @[@"AdSplashManager", @"AdSplashModule",
            @"CoolapkGMCustomSplashLoader", @"TanxGMCustomSplashLoader"]) {
            Class cls = SafeClass(cn);
            if (!cls) continue;
            SafeSwizzle(cls, @selector(loadSplashAd),
                imp_implementationWithBlock(^(id _self) {}));
            SafeSwizzle(cls, @selector(showSplashAdInWindow:),
                imp_implementationWithBlock(^(id _self, id w) {}));
            SafeSwizzle(cls, @selector(startSplashRequest),
                imp_implementationWithBlock(^(id _self) {}));
            SafeSwizzle(cls, @selector(showSplashAd),
                imp_implementationWithBlock(^(id _self) {}));
        }

        // === 4. Tanx 广告系统 ===
        Class tanxLoader = SafeClass(@"TanxGMCustomFeedLoader");
        if (tanxLoader) {
            SafeSwizzle(tanxLoader, @selector(loadAd),
                imp_implementationWithBlock(^(id _self) {}));
        }
        Class tanxMgr = SafeClass(@"TanxSDKManager");
        if (tanxMgr) {
            SafeClassSwizzle(tanxMgr, @selector(startWithAppId:),
                imp_implementationWithBlock(^(id _self, id a) {}));
        }

        // === 5. GM 广告 ===
        Class gmMgr = SafeClass(@"GMAdSDKManager");
        if (gmMgr) {
            SafeClassSwizzle(gmMgr, @selector(startWithAppId:),
                imp_implementationWithBlock(^(id _self, id a) {}));
        }
        Class gmFeedView = SafeClass(@"CoolapkGMCustomFeedAdView");
        if (gmFeedView) {
            SafeSwizzle(gmFeedView, @selector(renderWithAdData:),
                imp_implementationWithBlock(^(id _self, id d) {}));
        }

        // === 6. 评论区广告事件处理器 ===
        for (NSString *cn in @[@"EntityListFeedReplyEventProcessor",
            @"EntityListFeedTopEventProcessor", @"EntityListFeedEventProcessor",
            @"EventSponsorPrizeCell",
            @"EntityListEventLocalDataProcessor_AdminManagement",
            @"EntityListRequestRemoteDataProcessor_SponsorCardProcess"]) {
            Class cls = SafeClass(cn);
            if (!cls) continue;
            SafeSwizzle(cls, @selector(processEvent:),
                imp_implementationWithBlock(^(id _self, id e) {}));
        }

        // === 7. AnyThink 聚合 SDK ===
        for (NSString *cn in @[@"ABUAdSDKManager", @"ABUAdLoader",
            @"ABUNativeAdLoader", @"ABUBannerAdLoader",
            @"ABUSplashAdLoader", @"ABUDrawAdLoader"]) {
            Class cls = SafeClass(cn);
            if (!cls) continue;
            SafeSwizzle(cls, @selector(loadAd),
                imp_implementationWithBlock(^(id _self) {}));
        }
        Class abuMgr = SafeClass(@"ABUAdSDKManager");
        if (abuMgr) {
            SafeClassSwizzle(abuMgr, @selector(startWithCompletionBlock:),
                imp_implementationWithBlock(^(id _self, id b) {}));
        }

        // === 8. FeedAdModel ===
        Class adModel = SafeClass(@"FeedAdModel");
        if (adModel) {
            SafeSwizzle(adModel, @selector(initWithDictionary:),
                imp_implementationWithBlock(^id(id _self, NSDictionary *d) {
                    return nil;
                }));
        }

        // === 9. FeedAdClick ===
        Class adClick = SafeClass(@"FeedAdClick");
        if (adClick) {
            SafeSwizzle(adClick, @selector(handleClick),
                imp_implementationWithBlock(^(id _self) {}));
        }

        // === 10. 启动后清理开屏残留 ===
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                for (UIWindow *window in [UIApplication sharedApplication].windows) {
                    cleanupSplashViews(window);
                }
            } @catch (NSException *e) {}
        });

        NSLog(@"🦐 Coolapk No-Ad v2.1 init done!");
    }
}