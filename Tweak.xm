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

// 替换实例方法
static void ReplaceMethod(Class cls, SEL sel, IMP newImp, IMP *_oldImp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        *_oldImp = method_setImplementation(m, newImp);
        NSLog(@"🦐 Swizzled %@.%@", NSStringFromClass(cls), NSStringFromSelector(sel));
    } else {
        // 方法不存在，动态添加
        class_addMethod(cls, sel, newImp, "@@:@");
        NSLog(@"🦐 Added method %@.%@", NSStringFromClass(cls), NSStringFromSelector(sel));
    }
}

// 替换类方法
static void ReplaceClassMethod(Class cls, SEL sel, IMP newImp, IMP *_oldImp) {
    Method m = class_getClassMethod(cls, sel);
    if (m) {
        *_oldImp = method_setImplementation(m, newImp);
    } else {
        class_addMethod(object_getClass(cls), sel, newImp, "@@:@");
    }
}

// v1: 返回 nil 的空实现
static id ReturnNil(id self, SEL _cmd, ...) {
    return nil;
}

// v2: 返回 @[] 的空实现
static id ReturnEmptyArray(id self, SEL _cmd, ...) {
    return @[];
}

// v3: 什么也不做的 void 实现
static void DoNothing(id self, SEL _cmd, ...) {
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

// 遍历运行时所有类，自动寻找并 swizzle
static void AutoSwizzleAdClasses(void) {
    int classCount = objc_getClassList(NULL, 0);
    Class *classes = (Class *)malloc(sizeof(Class) * classCount);
    objc_getClassList(classes, classCount);
    
    for (int i = 0; i < classCount; i++) {
        NSString *name = NSStringFromClass(classes[i]);
        if (!name) continue;
        
        // 只处理 CoolMarket 前缀或明显的广告类
        if ([name hasPrefix:@"CoolMarket."] && IsAdClassName(name)) {
            NSLog(@"🦐 Auto-found: %@", name);
            
            // 尝试 swizzle 常用的加载方法
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
                    NSLog(@"🦐   Disabled %@.%@", name, NSStringFromSelector(loadSels[j]));
                }
            }
        }
    }
    free(classes);
}

// ============================================================
// 方案一：精确 %hook（仅对纯 ObjC 类有效）
// ============================================================

%hook FeedAdvertisementManager
- (void)requestAds:(id)request { /* 不请求 */ }
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

// CSJ (穿山甲) SDK 禁止初始化
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
            // 信息流广告
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
            @"ABUInterstitialAdLoader",
            @"ABUFullscreenVideoAdLoader",
            @"ABUInterstitialProAdLoader",
        ];
        
        for (NSString *name in adClassesToKill) {
            Class cls = FindAdClass(name);
            if (!cls) continue;
            
            // 尝试 swizzle 所有常见方法
            IMP impNil = (IMP)ReturnNil;
            IMP impVoid = (IMP)DoNothing;
            IMP impEmptyArray = (IMP)ReturnEmptyArray;
            (void)impEmptyArray; // 保留备用
            
            // 获取该类所有方法
            unsigned int mc = 0;
            Method *methods = class_copyMethodList(cls, &mc);
            for (unsigned int j = 0; j < mc; j++) {
                SEL sel = method_getName(methods[j]);
                NSString *selName = NSStringFromSelector(sel);
                const char *type = method_getTypeEncoding(methods[j]);
                
                // 根据返回类型决定替换策略
                if ([selName hasPrefix:@"init"] || [selName hasPrefix:@"shared"]) {
                    // init 或 singleton 返回 nil
                    if (type && type[0] == '@') {
                        method_setImplementation(methods[j], impNil);
                    }
                }
                else if ([selName containsString:@"load"] ||
                         [selName containsString:@"start"] ||
                         [selName containsString:@"request"] ||
                         [selName containsString:@"setAppId"] ||
                         [selName containsString:@"show"] ||
                         [selName containsString:@"render"] ||
                         [selName containsString:@"process"]) {
                    // 加载/启动方法 → 空实现
                    method_setImplementation(methods[j], impVoid);
                }
                else if ([selName containsString:@"Ad"] ||
                         [selName containsString:@"ad"] ||
                         [selName containsString:@"model"] ||
                         [selName containsString:@"Model"]) {
                    // 返回广告/模型的方法 → nil 或空数组
                    if (type && type[0] == '@') {
                        method_setImplementation(methods[j], impNil);
                    }
                }
            }
            free(methods);
            
            // 也处理同名的类方法
            Class meta = object_getClass(cls);
            unsigned int cmc = 0;
            Method *cmethods = class_copyMethodList(meta, &cmc);
            for (unsigned int j = 0; j < cmc; j++) {
                SEL sel = method_getName(cmethods[j]);
                NSString *selName = NSStringFromSelector(sel);
                const char *type = method_getTypeEncoding(cmethods[j]);
                
                if ([selName hasPrefix:@"shared"] ||
                    [selName hasPrefix:@"start"] ||
                    [selName containsString:@"init"] ||
                    [selName containsString:@"load"]) {
                    if (type && type[0] == '@') {
                        method_setImplementation(cmethods[j], impNil);
                    } else {
                        method_setImplementation(cmethods[j], impVoid);
                    }
                }
            }
            free(cmethods);
        }
        
        // === 2. 自动扫描发现漏网之鱼 ===
        AutoSwizzleAdClasses();
        
        // === 3. 拦截 UIView 广告检测器 ===
        // 拦截 didMoveToWindow，检查是否是广告类
        static IMP orig_didMoveToWindow = NULL;
        IMP new_didMoveToWindow = imp_implementationWithBlock(^(UIView *view) {
            // 先调原始
            if (orig_didMoveToWindow) {
                ((void(*)(id, SEL))orig_didMoveToWindow)(view, @selector(didMoveToWindow));
            }
            
            // 检查是否广告类
            NSString *vclass = NSStringFromClass([view class]);
            if (IsAdClassName(vclass)) {
                [view setHidden:YES];
                [view setFrame:CGRectZero];
                [view removeFromSuperview];
                NSLog(@"🦐 Blocked ad view: %@", vclass);
            }
        });
        
        Class uiViewClass = [UIView class];
        Method dmwMethod = class_getInstanceMethod(uiViewClass, @selector(didMoveToWindow));
        if (dmwMethod) {
            orig_didMoveToWindow = method_setImplementation(dmwMethod, new_didMoveToWindow);
            NSLog(@"🦐 Installed UIView ad filter");
        }
        
        // === 4. 启动后延迟移除开屏 ===
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            // 遍历所有 window，查找并移除开屏视图
            for (UIWindow *window in [UIApplication sharedApplication].windows) {
                removeSplashViewsFromView(window);
            }
            NSLog(@"🦐 Post-launch splash cleanup done");
        });
    }
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
