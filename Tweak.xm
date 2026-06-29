/* 
 * Coolapk (CoolMarket) No-Ad Tweak
 * Target: CoolMarket.app v15.8.2
 * Method: TrollStore + TrollFools dylib injection
 */

#import <UIKit/UIKit.h>

// ============================================================
// 1. 拦截信息流广告加载（核心！）
// ============================================================

%hook FeedAdvertisementManager

// 不让管理加载任何广告
- (void)loadAdWithCount:(NSInteger)count {
    %log;  // 只打日志，不加载
    // 啥也不干 — 跳过广告加载
}

- (id)loadTask {
    return nil;  // 不创建加载任务
}

- (NSArray *)ads {
    return @[];  // 返回空广告列表
}

- (void)registerAd:(id)ad {
    // 不注册任何广告
    %log;
}

%end

%hook FeedAdvertisementLoadTask

- (instancetype)init {
    return nil;  // 不创建加载任务
}

- (void)start {
    // 不开始加载
    %log;
}

%end

%hook FeedAdvertisementLoader

- (void)loadFeedAdvertisement {
    // 不加载广告
    %log;
}

- (id)loadFeedAdvertisements:(NSArray *)params {
    return nil;
}

%end

%hook FeedAdvertisementLoader_Official
- (void)loadFeedAdvertisement {
    // 官方渠道也不加载
}
%end

%hook FeedAdvertisementLoader_Topon
- (void)loadFeedAdvertisement {
    // TopOn聚合渠道不加载
}
%end

%hook FeedAdvertisementLoader_GMSelfDraw
- (void)loadFeedAdvertisement {
    // GM自渲染不加载
}
%end

// ============================================================
// 2. 拦截信息流广告 Cell 展示
// ============================================================

%hook FeedAdvertisementCellBaseV4

// 不让 cell 获取高度
- (CGFloat)cellHeight {
    return 0.0;  // 高度压零
}

- (CGSize)sizeThatFits:(CGSize)size {
    return CGSizeZero;
}

- (void)layoutSubviews {
    // 啥也不画
    [(UIView *)self setHidden:YES];
    [(UIView *)self setFrame:CGRectZero];
}

- (void)setAdModel:(id)model {
    // 不设置广告数据
    [(UIView *)self setHidden:YES];
    [(UIView *)self removeFromSuperview];
}

%end

%hook FeedAdModel

// 广告数据模型返回空
- (instancetype)initWithDictionary:(NSDictionary *)dict {
    return nil;
}

+ (instancetype)modelWithDictionary:(NSDictionary *)dict {
    return nil;
}

%end

// ============================================================
// 3. 拦截开屏广告
// ============================================================

%hook AdSplashManager

- (void)loadSplashAd {
    %log;
    // 不加载开屏广告
}

- (void)showSplashAdInWindow:(UIWindow *)window {
    // 不展示
    %log;
}

- (void)startSplashRequest {
    // 不发起请求
}

%end

%hook CoolapkGMCustomSplashLoader

- (void)loadSplashAd {
    %log;
    // 不加载
}

- (void)showSplashViewInWindow:(UIWindow *)window {
    // 不展示
}

%end

%hook CoolapkGMSplashView

- (instancetype)initWithFrame:(CGRect)frame {
    return nil;  // 不创建开屏 View
}

- (void)showInWindow:(UIWindow *)window {
    // 不展示
}

%end

%hook AdSplashModule

- (void)showSplashAd {
    // 不展示
}

%end

// ============================================================
// 4. 拦截广告 SDK 初始化（可选，建议先试上面）
//   让 SDK 初始化但无广告可展示最安全，不 init 可能报错
// ============================================================

%hook CSJAdSDKManager

// 如果上面不够干净，取消注释
// - (void)startWithConfiguration:(id)config {
//     %log;
//     // 不让 SDK 启动
// }

%end

// ============================================================
// 5. 拦截 GM（Gromore）自定义 Feed 广告
// ============================================================

%hook CoolapkGMCustomFeedLoader

- (void)loadAd {
    %log;
    // 不加载 GM 广告
}

- (id)feedAdView {
    return nil;
}

%end

%hook CoolapkGMCustomFeedAdView

- (instancetype)initWithFrame:(CGRect)frame {
    return nil;  // 不创建广告 View
}

- (void)renderWithAdData:(id)data {
    // 不渲染任何广告数据
    [(UIView *)self setHidden:YES];
}

%end

// ============================================================
// 6. 拦截 Feed Proportion / Sponsor 广告
// ============================================================

%hook FeedAdLoader

- (void)loadAd {
    %log;
    // 不加载
}

- (id)adModel {
    return nil;
}

%end

%hook FeedAdClick

- (void)handleClick {
    // 拦截点击事件，什么都不做
    %log;
}

%end

// ============================================================
// 7. 拦截 Tanx（阿里 Tanx 广告系统）— 评论区广告的元凶
// ============================================================

%hook TanxGMCustomFeedLoader

- (void)loadAd {
    // 不加载 Tanx 广告
    %log;
}

- (id)feedAdView {
    return nil;
}

%end

%hook TanxGMCustomFeedViewCreater

- (id)createFeedAdViewWithFrame:(CGRect)frame {
    return nil;
}

%end

%hook TanxGMCustomInit

- (instancetype)init {
    return nil;
}

%end

%hook TanxSDKManager

+ (void)startWithAppId:(id)appId {
    // 不让 Tanx SDK 启动
}

%end

%hook TanxGMCustomSplashLoader

- (void)loadSplashAd {
    // 不加载 Tanx 开屏
}

%end

// ============================================================
// 8. 拦截评论区广告事件处理器
// ============================================================

%hook EntityListFeedReplyEventProcessor

- (void)processEvent:(id)event {
    // 不处理广告相关事件
    %log;
}

%end

%hook EventSponsorPrizeCell

- (void)didMoveToWindow {
    [(UIView *)self setHidden:YES];
    [(UIView *)self removeFromSuperview];
}

%end

// ============================================================
// 9. 兜底拦截：通用广告管理器和未分类 Loader
// ============================================================

%hook GeneralEntityListFeedAdvertisementManager

- (void)loadAds {
    // 不加载任何广告
}

- (NSArray *)ads {
    return @[];
}

%end

%hook EntityListFeedAdvertisementLoader_Unsupported

- (void)loadFeedAdvertisement {
    // 未知类型也不加载
}

%end

%hook EntityListFeedTopEventProcessor

- (void)processEvent:(id)event {
    // 不处理置顶广告
    %log;
}

%end

%hook GMAdSDKManager

+ (void)startWithAppId:(id)appId {
    // 不让 GM SDK 启动
}

%end

// ============================================================
// 10. 拦截 AnyThink 聚合 SDK
// ============================================================

%hook ABUAdSDKManager

+ (void)startWithCompletionBlock:(id)block {
    // 不让聚合 SDK 启动
}

%end

%hook ABUAdLoader

- (void)loadAd {
    // 不加载广告
}

%end

%hook ABUNativeAdLoader

- (void)loadAd {
    // 不加载原生广告
}

%end

// ============================================================
// 11. 拦截 FeedAdvertisementSponsorTypeInfo（赞助商类型广告）
// ============================================================

%hook FeedAdvertisementSponsorTypeInfo

- (instancetype)init {
    return nil;
}

+ (instancetype)shared {
    return nil;
}

%end

// ============================================================
// 8. 构造函数拦截器
// ============================================================

%ctor {
    NSLog(@"🦐 Coolapk No-Ad Tweak loaded successfully!");

    // 可选：禁用广告 SDK 的更多初始化
    // 可以根据需要添加更多 hook
}