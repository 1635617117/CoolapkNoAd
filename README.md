# CoolapkNoAd — 酷安去广告 dylib 插件

TrollStore + TrollFools 注入用，基于酷安 iOS 15.8.2 逆向分析。

## 逆向分析结果

### App 基本信息
- Bundle ID: `com.coolapk.market`
- App 名: `CoolMarket.app`（实际上是 Coolapk）
- 版本: 15.8.2

### 接入的广告 SDK
| SDK | 用途 | 识别特征 |
|-----|------|----------|
| **穿山甲 (CSJ / Pangle)** | 信息流+开屏 | `CSJAdSDK`, `BU_*` |
| **广点通 (GDT)** | Banner+插屏 | `GDTMobSDK` |
| **TopOn (AnyThink)** | 聚合广告平台 | `AnyThinkSDK`, `AT*` |
| **快手联盟** | 信息流 | `kuaiShou_*` |
| **Mintegral** | 信息流+开屏 | `mintegral_*` |
| **Sigmob** | 开屏 | `sigmob_*` |

### 关键自定义广告类

**信息流广告 —— 核心拦截点：**
```
FeedAdvertisementManager        ← 广告管理器（推荐 hook【顶层】）
FeedAdvertisementLoadTask       ← 广告加载任务
FeedAdvertisementLoader         ← 广告加载器（含 _Official, _Topon, _GMSelfDraw）
FeedAdvertisementCellBaseV4     ← 广告 Cell（信息流里展示）
FeedAdModel                     ← 广告数据模型
FeedAdLoader                    ← 广告加载器
FeedAdClick                     ← 广告点击处理
FeedadvertisementCoupon         ← 优惠券广告
FeedAdvertisementDownloadView   ← 下载类广告
FeedAdvertisementLiveRoom       ← 直播间广告
```

**开屏广告 —— 核心拦截点：**
```
AdSplashManager / AdSplashManagerCSg  ← 开屏管理
CoolapkGMCustomSplashLoader           ← 自定义开屏加载器
CoolapkGMSplashView                   ← 开屏 View
AdSplashModule                        ← 开屏模块
AdSplashView                          ← 开屏 View
```

### 编译 & 注入

**在 Mac 上编译：**
```bash
# 1. 确保 Theos 已安装
export THEOS=~/theos

# 2. 编译
cd CoolapkNoAd
make clean
make package

# 3. 产物在 .theos/obj/debug/CoolapkNoAd.dylib
```

**注入到酷安（在 iPhone 上）：**
1. 把 `.dylib` 传到 iPhone
2. 打开 **TrollFools**
3. 选择酷安 → 注入 dylib
4. 重启酷安

### Frida 快速验证

如果不确定类名是否正确，先用 Frida probe：
```bash
# 查看酷安中所有含 "Ad" 的类
frida -U com.coolapk.market -e "ObjC.enumerateLoadedClasses({onMatch: function(name){if(name.includes('Ad'))console.log(name)}})"
```

### 免责声明
仅供学习研究使用。