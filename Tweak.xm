/*
 * Coolapk (CoolMarket) No-Ad Tweak v2.0
 * Target: CoolMarket.app v15.8.2
 * Strategy: Runtime swizzle + generic ad view filter
 *
 * 方案说明：
 * - 方案一：%hook 编译时 hook（只对纯 ObjC 类生效）
 * - 方案二：运行时 swizzle（处理 Swift 类名带模块前缀的问题）
 * - 方案三：UIView 广告检测器（兜底，按类名关键词隐藏广告视图）
 * - 方案四：启动后移除开屏广告窗口
 */

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

// ============================================================
// 工具函数：运行时 swizzle
// ============================================================

// 带 fallback 的类查找：尝试纯名、CoolMarket.前缀
static Class FindAdClass(NSString *name) {
    Class cls = NSClassFromString(name);
    if (cls) {
        NSLog(@"🦐 Found class: %@", name);
        return cls;
    }
    NSString *qualified = [@"CoolMarket." stringByAppendingString:name];
    cls = NSClassFromString(qualified);
    if (cls) {
        NSLog(@"🦐 Found class (prefixed): %@", qualified);
        return cls;
    }
    return nil;
}

// v1: 返回 nil 的空实现
static id ReturnNil(__unused id self, __unused SEL _cmd, ...) {
    return nil;
}

// v2: 返回 @[] 的空实现
static id ReturnEmptyArray(__unused id self, __unused SEL _cmd, ...) {
    return @[];
}

// v3: 什么也不做的 void 实现
static void DoNothing(__unused id self, __unused SEL _cmd, ...) {
}

// 尝试从类名判断是否是广告视图
static BOOL IsAdClassName(NSString *className) {
    if (!className) return NO;
    NSArray *keywords = @[
        @"Splash", @"Ad", @"ad", @"Sponsor", @"sponsor",
        @"FeedAd", @"Advertisement", @"GMCustomFeed", @"GMCustomSplash",
        @"Tanx", @"GMFeedAd"
    ];
    for (NSString *kw in keywords) {
        if ([className containsString:kw]) return YES;
    }
    return NO;
}

// 递归查找并移除开屏相关视图
static void removeSplashViewsFromView(UIView *view) {
    NSString *vclass = NSStringFromClass([view class]);
    if ([vclass containsString:@"Splash"] ||
        [vclass containsString:@"GMAd"] ||
        [vclass containsString:@"AdContainer"]) {
        [view setHidden:YES];
        [view removeFromSuperview];
        NSLog(@"🦐 Removed splash view: %@", vclass);
        return;
    }
    for (UIView *subview in view.subviews) {
        removeSplashViewsFromView(subview);
    }
}

// 遍历运行时所有类，自动寻找并 swizzle
static void AutoSwizzleAdClasses(void) {
    int classCount = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * classCount);
    objc_getClassList(classes, classCount);

    for (int i = 0; i < classCount; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if (!name) continue;

        if ([name hasPrefix:@"CoolMarket."] && IsAdClassName(name)) {
            NSLog(@"🦐 Auto-found: %@", name);

            SEL loadSels[] = {
                @selector(loadAd), @selector(loadAds),
                @selector(loadSplashAd), @selector(loadFeedAdvertisement),
                @selector(start), @selector(startWithCompletionBlock:),
                @selector(initWithFrame:), @selector(initWithCoder:)
            };

            for (int j = 0; j < sizeof(loadSels)/sizeof(SEL); j++) {
                Method m = class_getInstanceMethod(classes[i], loadSels[j]);
                if (m) {
                    method_setImplementation(m, (IMP)DoNothing);
                }
            }
        }
    }
    free(classes);
}

// ============================================================
// 方案一：%hook 编译时 hook（仅对纯 ObjC 类有效）
// ============================================================

%hook FeedAdvertisementManager
- (void)requestAds:(id)request { }
- (id)nextAdModel { return nil; }
%end

%hook FeedAdvertisementCellBaseV4
- (void)layoutSubviews {
    [(UIView *)self setHidden:YES];
    [(UIView *)self setFrame:CGRectZero];
}
%end

%hook FeedAdvertisementSponsorTypeInfo
+ (id)shared { return nil; }
%end

%hook CSJAdSDKManager
+ (void)setAppId:(id)appId { }
%end

// ============================================================
// 方案二/三/四：%ctor 运行时执行
// ============================================================

%ctor {
    @autoreleasepool {
        NSLog(@"🦐 Coolapk No-Ad v2.0 loaded!");

        // === 1. 精确查找已知广告类 ===
        NSArray *adClassesToKill = @[
            @"FeedAdvertisementManager",
            @"FeedAdvertisementLoadTask",
            @"FeedAdvertisementLoader",
            @"FeedAdvertisementLoader_Official",
            @"FeedAdvertisementLoader_Topon",
            @"FeedAdvertisementLoader_GMSelfDraw",
            @"FeedAdLoader",
            @"FeedAdModel",
            @"FeedAdClick",
            @"FeedAdvertisementSponsorTypeInfo",

            // 开屏广告
            @"AdSplashManager",
            @"AdSplashModule",
            @"CoolapkGMCustomSplashLoader",
            @"CoolapkGMSplashView",
            @"TanxGMCustomSplashLoader",

            // GM 广告
            @"CoolapkGMCustomFeedLoader",
            @"CoolapkGMCustomFeedAdView",
            @"GMAdSDKManager",
            @"GeneralEntityListFeedAdvertisementManager",
            @"GeneralEntityListFeedAdvertisementLoader_Official",
            @"GeneralEntityListFeedAdvertisementLoader_Topon",
            @"GeneralEntityListFeedAdvertisementLoader_GMSelfDraw",
            @"EntityListFeedAdvertisementLoader_Unsupported",

            // Tanx 广告
            @"TanxGMCustomFeedLoader",
            @"TanxGMCustomFeedViewCreater",
            @"TanxGMCustomInit",
            @"TanxSDKManager",

            // 评论区/事件处理
            @"EntityListFeedReplyEventProcessor",
            @"EntityListFeedTopEventProcessor",
            @"EntityListFeedEventProcessor",
            @"EventSponsorPrizeCell",
            @"EntityListEventLocalDataProcessor_AdminManagement",
            @"EntityListRequestRemoteDataProcessor_SponsorCardProcess",

            // AnyThink 聚合
            @"ABUAdSDKManager",
            @"ABUAdLoader",
            @"ABUNativeAdLoader",
            @"ABUBannerAdLoader",
            @"ABUSplashAdLoader",
            @"ABUDrawAdLoader",
        ];

        for (NSString *name in adClassesToKill) {
            Class cls = FindAdClass(name);
            if (!cls) continue;

            // 获取该类所有方法
            unsigned int mc = 0;
            Method *methods = class_copyMethodList(cls, &mc);
            for (unsigned int j = 0; j < mc; j++) {
                SEL sel = method_getName(methods[j]);
                NSString *selName = NSStringFromSelector(sel);
                const char *type = method_getTypeEncoding(methods[j]);

                if ([selName hasPrefix:@"init"] || [selName hasPrefix:@"shared"]) {
                    if (type && type[0] == '@') {
                        method_setImplementation(methods[j], (IMP)ReturnNil);
                    }
                }
                else if ([selName containsString:@"load"] ||
                         [selName containsString:@"start"] ||
                         [selName containsString:@"request"] ||
                         [selName containsString:@"setAppId"] ||
                         [selName containsString:@"show"] ||
                         [selName containsString:@"render"] ||
                         [selName containsString:@"process"]) {
                    method_setImplementation(methods[j], (IMP)DoNothing);
                }
                else if ([selName containsString:@"Ad"] ||
                         [selName containsString:@"ad"] ||
                         [selName containsString:@"model"] ||
                         [selName containsString:@"Model"]) {
                    if (type && type[0] == '@') {
                        method_setImplementation(methods[j], (IMP)ReturnNil);
                    }
                }
            }
            free(methods);

            // 也处理类方法
            Class meta = object_getClass(cls);
            unsigned int cmc = 0;
            Method *cmethods = class_copyMethodList(meta, &cmc);
            for (unsigned int j = 0; j < cmc; j++) {
                SEL sel = method_getName(cmethods[j]);
                NSString *selName = NSStringFromSelector(sel);
                const char *type = method_getTypeEncoding(cmethods[j]);

                if ([selName hasPrefix:@"shared"] || [selName hasPrefix:@"start"] ||
                    [selName containsString:@"init"] || [selName containsString:@"load"]) {
                    if (type && type[0] == '@') {
                        method_setImplementation(cmethods[j], (IMP)ReturnNil);
                    } else {
                        method_setImplementation(cmethods[j], (IMP)DoNothing);
                    }
                }
            }
            free(cmethods);
        }

        // === 2. 自动扫描发现漏网之鱼 ===
        AutoSwizzleAdClasses();

        // === 3. 拦截 UIView 广告检测器 ===
        static IMP orig_didMoveToWindow = NULL;
        IMP new_didMoveToWindow = imp_implementationWithBlock(^(UIView *view) {
            if (orig_didMoveToWindow) {
                ((void(*)(id, SEL))orig_didMoveToWindow)(view, @selector(didMoveToWindow));
            }
            NSString *vclass = NSStringFromClass([view class]);
            if (IsAdClassName(vclass)) {
                [view setHidden:YES];
                [view removeFromSuperview];
            }
        });

        Method dmwMethod = class_getInstanceMethod([UIView class], @selector(didMoveToWindow));
        if (dmwMethod) {
            orig_didMoveToWindow = method_setImplementation(dmwMethod, new_didMoveToWindow);
            NSLog(@"🦐 Installed UIView ad filter");
        }

        // === 4. 启动后延迟移除开屏 ===
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                removeSplashViewsFromView(window);
            }
            NSLog(@"🦐 Post-launch splash cleanup done");
        });
    }
}