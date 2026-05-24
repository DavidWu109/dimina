# 2026-05-23 Session Changes

> 本次 session 内 Dimina iOS 端的所有改动，按主题归类。**⚠️ 标记的是不确定 / 仅部分修复 / 待后续研究的项。**

## I. 统一日志门面 `DMPLog`

新文件：`iOS/dimina/DiminaKit/Utils/DMPLog.swift`

- 基于 `os.Logger`/`os_log`，subsystem = `com.echo.dimina`
- 6 个 channel：`app / render / bridge / bundle / pool / scheme`
- 4 级别：`debug / info / warn / error`
- 双写：`os_log` + `Documents/dimina.log`（`DMPApp.launch` 时 reset）
- 详细使用见 `Debugging-Infrastructure.md`

替换了散落的 `print()` / `debugLog()` / 3 份独立 `writeToLogFile` 在：
- `App/DMPApp.swift`（launch 全流程）
- `Render/DMPRender.swift`（webViewDidFinish/FailLoad + bridge）
- `Render/DMPWebview.swift`（loadPageFrame + navigation delegates + 新增 didFailProvisionalNavigation）
- `Render/DiminaURLSchemeHandler.swift`（资源解析，砍掉 100+ 行噪音）
- `Render/DifileURLSchemeHandler.swift`（同上）
- `Render/DMPWebViewPool.swift`（acquire/release/recycle/warmUp/clearPool + 新增 `poolSnapshot()` helper）
- `Container/DMPContainer.swift`（loadResourceService/Render）
- `Container/Api/DMPContainerApi.swift`（API 注册）
- `Container/DMPChannelProxy.swift`（messageHandler 派发 + resourceLoaded 协议跟踪）

## II. Error 序列化修复

`Service/DMPEngineLog.swift::formatJSValue`

之前对 JS Error 走 `value.toDictionary()` 路径，Error 的 `message/name/stack` 是 non-enumerable 拿不到 → 输出空 `{}`。现在显式取 `.name / .message / .stack`，可以直接看到 mini-app 的 TypeError 信息。

## III. WebView DOM 诊断

`Render/DMPRender.swift::scheduleDOMDiagnostics`

WebView ready 后 3s 和 10s 各 dump 一次 DOM 状态到 `DMPLog.render.info`（落到 `dimina.log`）：
- `htmlFontSize / htmlRect / bodyRect / bodyHTMLLen`
- `bodyChildren[]`（每个直接子节点的 tag/cls/size/display/visibility/opacity/childCount）
- 全局错误列表 / 网络错误列表 / URL

白屏排查首选数据源。

## IV. TabBar 架构（新增）

mini-app 之前没法正常渲染 tabBar。Dimina 没有这套实现。本次自己写：

| 文件 | 作用 |
|---|---|
| `Bundle/DMPBundleAppConfig.swift` | 新增 `tabBar` 字段解析（`DMPTabBarConfig` + `DMPTabBarItem`） |
| `Container/UI/DMPTabBarView.swift` | 底部 tabBar UIKit 组件（icon + label，支持 setTabBarStyle/Item） |
| `Container/UI/DMPTabBarContainerController.swift` | **自定义容器 VC（非 UITabBarController）**，持有 N 个 tab DMPPageController 作为 child VCs |
| `Container/Api/UI/TabBarAPI.swift` | wx tabBar 8 个 API：setTabBarStyle / setTabBarItem / show\|hideTabBar / setTabBarBadge / removeTabBarBadge / show\|hideTabBarRedDot |
| `Container/Api/Route/RouteAPI.swift` | 新增 `switchTab` 方法（@BridgeMethod） |
| `Navigator/DMPNavigator.swift` | `launch(to:)` 检测 tab 页 → 创建容器；新增 `switchTab(to:)`、`appendPageRecord(_:)` |

### TabBar 容器关键设计

- **Lazy 创建**：初始 tab 立即创建，其他 tab 切到时才创建。原因：eager 4 个并发 `loadResource` 破坏 mini-app service worker「一次只激活一个 page」假设
- **标准 UIKit 内存管理（attach/detach）**：每个 tab 的 `DMPPageController` 首次访问时 `addChild` 进容器并永久持有；切 tab 时只用 `view.removeFromSuperview()` / `addSubview(...)` 切视图层级，**永不 `removeFromParent`**（避免触发 `viewDidDisappear` 里 `isMovingFromParent` → `destroyWebView` 的销毁路径）。等价于 `UINavigationController.pushViewController` 之后旧 VC 的 view 被 detach 的机制——WebKit 进入定义良好的 `window=nil` suspend 状态，reattach 时干净 resume
- **navigationItem 同步**：容器自身的 `navigationItem` 跟随当前 child 的 pagePath 配置（标题/颜色/back button/胶囊每 tab 不同）
- **switchTo 行为**：不动 host nav 栈，只切 child view 的 attach/detach → tab 实例和 WebView 状态完整保留

### ⚠️ 历史：alpha=0 方案被替换

初版用 `alpha=0` 切显隐（避开 `isHidden=true` 的 WebKit throttle）。实测快速点 tab 时新 tab 的 `pageFrame.js` 还没跑到 `invoke({type:'renderResourceLoaded'})` 就被切走，从此 `loadStatusMap` 永远停在 `.serviceLoaded` → 永久白屏。`alpha=0` 是半节流的暧昧状态，失败不可观测、不可恢复。

改成 attach/detach 后这条路径的失败模式变成「WebContent process 被 OS 回收」——可以靠 `DMPWebview.webViewWebContentProcessDidTerminate` 兜底重 `loadPageFrame()` 恢复。完整对比表 + 快速点击 4 条路径分析 + 评估过但暂不上的方案见 [TabBar-Memory-Model.md](./TabBar-Memory-Model.md)。

## V. NavigationBar 真正生效

`Container/DMPPageController.swift`

之前 `setupNavigationBar` 强制 `setNavigationBarHidden(true)` 等同于 nav bar 永远不显示，业务配的 `navigationBarTitleText / navigationBarBackgroundColor / navigationBarTextStyle` 都是 dead config。

修法：
- 重命名 `setupNavigationBar` → `applyNavigationStyleToSelfNavigationItem()`（**public**，让 `DMPTabBarContainerController` 取一次 child 配置复制到容器 navigationItem）
- 读 `navigationStyle`：`default`（显示 nav bar）/ `custom`（沉浸式隐藏）
- WebView top constraint 改成根据 navigationStyle：`safeAreaLayoutGuide.topAnchor`（default） vs `view.topAnchor`（custom）
- 去掉无条件 `edgesForExtendedLayout = .all` + `safeAreaRegions = []` 那套沉浸式 hack（只在 custom 模式启用）

### 胶囊（Dimina capsule）位置修复

之前在每个 DMPPageController 里把 capsule 加为 `self.view` 子 view 浮在 safeArea.top，default 模式下会跑到 nav bar 下方（错位）。

修法：
- default 模式：胶囊用 `navigationItem.rightBarButtonItem = UIBarButtonItem(customView: overlay)`，真正绘制在 nav bar 上
- custom 模式（沉浸式）：保留原 subview 方式，浮在 view.safeArea.top

容器同步：`DMPTabBarContainerController.syncNavigationItemFromCurrentChild` 把 child 的 `navigationItem.rightBarButtonItem` 复制到自己，保证胶囊一直跟随当前 tab。

## VI. API 缺失补齐

### `TabBarAPI`（新增，见 IV）

### `LoginAPI`（新增）

`Container/Api/Base/LoginAPI.swift` + 协议 `DMPLoginProvider`

```swift
public protocol DMPLoginProvider: AnyObject {
    func login(appId: String, completion: @escaping (Result<[String: Any], Error>) -> Void)
}
```

`DMPApp.loginProvider` 是 **strong**（不是 weak）—— 宿主一般创建临时 adapter 实例，weak 会立刻释放。

宿主侧：参见 `EchoWebKit/docs/Architecture-MiniApp-Launch.md` 里 `DiminaLoginProvider` 实现。

### `NavigationBarAPI`（之前是 dead code）

`@BridgeMethod` 标注的 API 只有被实例化才会注册到 `bridgeHandlerMap`。`NavigationBarAPI` 之前没在 `DMPContainerApi.create()` 里实例化，等于 `setNavigationBarTitle / setNavigationBarColor` 全部是 dead code。本次补上：

```swift
_ = NavigationBarAPI()
_ = TabBarAPI()
_ = LoginAPI()
```

### `RouteAPI.switchTab`（新增）

`@BridgeMethod("switchTab")`：校验 path 是 tabBar.list 里的页面后，调 `navigator.switchTab(to: path)` 切容器 selectedIndex（不动 host nav 栈、不重建 webview）。

## VII. wx API JS polyfill

`App/DMPApp.swift::loadBundle()`

mini-app 的 `Taro.setTabBarStyle` 报 `TypeError: ... is not a function`，但 Dimina 的 service.js 内置 wx API 没这个方法。打 polyfill：

```js
// 1. service-sdk 加载后立即给 wx 命名空间补 tabBar 方法
wx.setTabBarStyle = function(opts) { DiminaServiceBridge.invoke({type:'setTabBarStyle', body: opts}); ... }
// 同 setTabBarItem / show|hideTabBar / setTabBarBadge / removeTabBarBadge / show|hideTabBarRedDot
```

**Taro 不是直接代理 wx**，它在 mini-app 自己打包的 `/taro` 模块里维护一份 API 白名单。必须二次 polyfill：

```js
// app logic.js 加载完后：通过 modRequire('/taro') 拿到 mini-app 的 Taro 模块
// 把缺失的方法从 wx 复制到 Taro
var taroMod = modRequire('/taro');
methods.forEach(m => { if (!Taro[m] && wx[m]) Taro[m] = wx[m]; });
```

⚠️ `Taro.getAppBaseInfo` / `getWindowInfo` 在 mini-app 还是抛 TypeError（但 mini-app 用 try/catch 包了不致命）。**待补**：把它们也加进 polyfill 列表。

## VIII. 防御性修复

### `setPagePath` 剥 query

`Render/DMPWebview.swift::setPagePath`

mini-app render 端 JS 把 pagePath 拼成文件名：`pages_xxx_index.js` / `.css`。如果 pagePath 带 `?id=3`，会拼出 `pages_xxx_index?id=3.css` → 404 → 白屏。

修法：`setPagePath` 防御性剥 `?` 后面的内容，query 通过 `setQuery` 单独存。

## IX. 待研究 / 不确定

### 9.1 navigateTo 出非 tab 页有时白屏（已修三层，待验证）

session 末尾稳定复现 `pages/activity-detail/index` push 白屏。逐层调试发现两个**上游 didi/dimina 原本就有**的设计点叠加，构成 race：

1. `DMPWebViewOptimizer` 让所有 WebView 共用 `DMPWebViewPool.sharedProcessPool`。pool inUse 到 iOS 限制后新 WebView 复用旧 process，可能命中坏 process → render pipeline 卡死但 didFinishLoad 照报。
2. `config.suppressesIncrementalRendering = true`：render 一卡 → 永久纯白没有任何中间态。

修复（按代价从低到高三层）：

- **L1**: `DMPWebViewOptimizer` 把 `suppressesIncrementalRendering` 从 true 改 false（**故意偏离上游**）。最差情况从"永久纯白"降级到"渐进显示"。
- **L1.5**: `DMPPageController` 加 `hasLoadedPageFrame` 标志 + viewDidAppear `bounds.height==0` guard + 300ms 救援。仅 `isRoot=false` 把 `loadPageFrame()` 从 init 延迟到 viewDidAppear。
- **L2**: `DMPPageController.loadPageFrameAndWatchdog()` 兜底 "didFinishLoad 来了但 render 没跟上"：3s 没 allLoaded → reload，6s 还不行 → error 终止。

完整调研、根因分析、上游 diff 对比、被否决的 L3（push 用独立 WKProcessPool）方案见 [Push-Page-Memory-Model.md](./Push-Page-Memory-Model.md)。

9.4 (bridgeId 11/12) 已确认与 9.1 同源，本次一并修。

### ⚠️ 9.2 tabBar 切换没发完整 page lifecycle 协议

`DMPNavigator.switchTab` 调了 `pageLifecycle.onShow/onHide`（发 `type:pageShow / pageHide` bridge msg），但 mini-app 的 Taro Router 可能不认这种"非真正切栈"的事件。需要进一步研究 Dimina + Taro adapter 的对接细节，看是否需要补 `type:"switchTab"` 信号。

### ⚠️ 9.3 WebView pool 复用 ID 跳号

log 里 webview id 跳号严重（`2, 4, 6, 7, 9, 11`，跳过 `3, 5, 8, 10`）。可能是 `regenerateWebViewId()` 在 acquireWebView 时无脑递增。具体规律不明，未深入。不影响功能。

### 9.4 bridgeId 11 / 12 现象（与 9.1 合并）

确认与 9.1 同源——都是 push 进非 tab 页时 WebView 的 zero-frame race。9.1 的修复同时覆盖这条。

## X. 文件清单（本次改动）

```
dimina/
├── docs/
│   ├── Debugging-Infrastructure.md          (上次 session 创建)
│   ├── Session-Changes-2026-05-23.md        (本文档)
│   ├── TabBar-Memory-Model.md               [新] tabBar attach/detach 设计与替代方案分析
│   └── Push-Page-Memory-Model.md            [新] navigateTo push 的 zero-frame race 调研与延迟方案
├── iOS/dimina/DiminaKit/
│   ├── App/
│   │   └── DMPApp.swift                     [改] launch 全流程改 DMPLog；wx polyfill 注入；loginProvider/pageOverlayProvider 属性
│   ├── Bundle/
│   │   └── DMPBundleAppConfig.swift         [改] 解析 tabBar 字段
│   ├── Container/
│   │   ├── DMPChannelProxy.swift            [改] messageHandler 改 DMPLog
│   │   ├── DMPContainer.swift               [改] loadResourceService/Render 加日志 + 防 nil app
│   │   ├── DMPPageController.swift          [大改] 去沉浸式 hack；navigationStyle；胶囊改 rightBarButtonItem；!isRoot 延迟 loadPageFrame 到 viewDidAppear + 0-height guard + renderResourceLoaded watchdog（修 IX.9.1）
│   │   ├── UI/
│   │   │   ├── DMPTabBarContainerController.swift  [新] tabBar 容器（attach/detach 内存管理）
│   │   │   └── DMPTabBarView.swift                 [新] tabBar UI 组件
│   │   └── Api/
│   │       ├── DMPContainerApi.swift        [改] create() 注册 NavigationBarAPI / TabBarAPI / LoginAPI
│   │       ├── Base/
│   │       │   └── LoginAPI.swift           [新] wx.login → DMPLoginProvider
│   │       ├── Route/
│   │       │   └── RouteAPI.swift           [改] 新增 switchTab
│   │       └── UI/
│   │           └── TabBarAPI.swift          [新] 8 个 tabBar API
│   ├── Navigator/
│   │   └── DMPNavigator.swift               [改] launch 检测 tab 页 → 容器；switchTab；appendPageRecord
│   ├── Render/
│   │   ├── DMPRender.swift                  [改] DMPLog；scheduleDOMDiagnostics
│   │   ├── DMPWebview.swift                 [改] DMPLog；setPagePath 剥 query；didFailProvisionalNavigation；webContentProcessDidTerminate 兜底
│   │   ├── DMPWebViewOptimizer.swift        [改] suppressesIncrementalRendering=false（故意偏离上游，配合 L2 watchdog 兜底）
│   │   ├── DMPWebViewPool.swift             [改] DMPLog；poolSnapshot helper
│   │   ├── DiminaURLSchemeHandler.swift     [大改] 用 DMPLog 替换百行噪音 print
│   │   └── DifileURLSchemeHandler.swift     [大改] 同上
│   ├── Service/
│   │   └── DMPEngineLog.swift               [改] formatJSValue Error 序列化修复
│   └── Utils/
│       └── DMPLog.swift                     [新] 统一日志门面
```
