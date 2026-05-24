# TabBar 内存模型与切换语义

> 决定 Dimina iOS 端 tabBar 容器的 view/WebView 复用策略；与上游 `didi/dimina`、`finclip` 这类业界惯例的差异，以及为什么。

## 目标

tab 之间切换时，每个 tab 的 `DMPPageController`（含其 WebView 与 JS 状态）必须**保留**——这是 mini-app 规范要求（switchTab 等价于 `onHide` / `onShow`，不重建页面）。

具体复用机制走**标准 UIKit 内存管理**：所有 tab 的 `DMPPageController` 一旦 lazy 创建就 `addChild` 进容器并永久持有，切 tab 时只通过 `view.removeFromSuperview()` / `addSubview()` 切换视图层级——和 `UINavigationController` push 之后旧 VC 的 view 被 detach 是同一套机制。

## 跟 push page 复用机制对齐

`DMPNavigator.navigateTo` 走 `navigationController.pushViewController(...)`。push 动画完成后，前一页的 view 被 UIKit 从视图层级里抽走（`window=nil`），WebKit 进入定义良好的 suspend 状态；prev `DMPPageController` 实例仍在 `viewControllers` 数组里活着，`parent` 仍指向 navController，`isMovingFromParent == false`，所以不会触发 `viewDidDisappear` 里 `destroyWebView` 分支。pop 回去时 view 重挂，WebKit 恢复，JS 从暂停处继续。

tabBar 切换照搬这套：
- `pageControllers[i]` 保持所有 tab 实例引用
- 每个 tab 首次访问时 `addChild(pc)` + `didMove(toParent: self)`，**永不 `removeFromParent`**（否则 `isMovingFromParent == true` → `destroyWebView` → WebView 还池子，tab 状态丢光）
- 切 tab = 旧 tab `view.removeFromSuperview()` + 新 tab `currentChildContainer.addSubview(...)`
- 容器自身被 pop 出 nav stack 时统一 deinit，children deinit 触发各 tab 的 `destroyWebView`，WebView 释放回池

## 为什么不走上游 / 业界主流的 alive-but-hidden

| | alive-but-hidden（`isHidden=true` 或 `alpha=0`） | attach/detach（本方案） |
|---|---|---|
| WebKit 节流强度 | `isHidden=true` 强 throttle；`alpha=0` 半节流（暧昧） | `window=nil` 干净 suspend |
| mid-load 被切走 | pageFrame.js 的 `invoke({type:'renderResourceLoaded'})` 可能在 throttle 状态下丢/不发，**永久 stuck** | suspend 后 reattach resume，JS 从暂停处继续，理论上能 fire |
| 失败模式 | 不可观测、不可恢复（loadStatusMap 永远停在 `.serviceLoaded`） | 可观测：WebContent process 被回收时 WebKit 发 `webViewWebContentProcessDidTerminate`，可在那个 callback 里 reload |
| 内存占用 | WebView 进程保活 | suspend 后 WebContent 进程占用更小，反而更友好 |

上游 `didi/dimina` 的 `DMPTabBarContainerController.updateVisibleTab` 用的是 `isHidden + alpha + bringSubviewToFront` 三件套：

```swift
// upstream didi/dimina
for (index, controller) in tabControllers {
    let isSelected = index == selectedIndex
    controller.view.isHidden = !isSelected
    controller.view.alpha = isSelected ? 1 : 0
    if isSelected {
        contentView.bringSubviewToFront(controller.view)
    }
}
```

FinClip / WeChat 这类闭源容器对外文档写的也是 "WebView for the previous page remains alive but hidden"。这条路在 prev tab **已完整加载** 时没问题，但对我们这种 mini-app 启动后用户立刻快速点 tab 的场景不够稳——具体见下面快速点击分析。

## 快速点击 4 种路径分析

设 4 个 tab（index 0/1/2/3），初始位于 tab0 且已 fully loaded。

### A. 单次切换 tab0 → tab1
- 创建 VC1/WebView1 → `loadPageFrame()` 启动加载
- `addChild(VC1)` + `didMove(toParent: self)`
- `attachChildView(VC1)`：`container.addSubview(VC1.view)` → 触发 `viewDidLoad` → hostingController 包好 WebView → window=window
- 旧 tab：`VC0.view.removeFromSuperview()` → tab0 WebView window=nil → suspend（tab0 早就 loaded，suspend 无伤）

**结论**：✓

### B. 快连两步 tab0→tab1→tab2（间隔 ~100ms，tab1 还在 load pageFrame.js）
- T=0 tap tab1：同 A
- T=100 tap tab2：创建 VC2/WebView2 → attach → 旧 tab=VC1 detach → tab1 window=nil → WebContent 进程 suspend，JS 暂停在某一行
- 理论：用户后续切回 tab1 → reattach → JS 恢复 → 那行 `invoke({type:'renderResourceLoaded'})` 终于执行 → bridge 收到 → `loadStatusMap[bridgeId]` 翻 `.allLoaded` → service `createInstance` → DOM 渲染
- 风险 1：tab1 suspend 太久 + 系统内存紧张，WebContent process 被 OS 回收。reattach 时 WebView 变空、pageFrame.js 状态全丢。**靠 `webViewWebContentProcessDidTerminate` 兜底重 loadPageFrame()**
- 风险 2：mid-suspend 时 `DiminaURLSchemeHandler` 还在为 pageFrame.html 等资源走 `urlScheme(_:start:)`，handler 自己的队列跟 WebContent process 独立，请求本身能跑完；数据塞回 WebView 时是否能正确进入 buffer 由 WebKit 自己处理（无文档化保证，需要观察）

### C. 极端来回 tab0→tab1→tab2→tab1（300ms 内）
- tab1 mid-load 被 detach 100ms 后又 reattach
- WebKit 的 suspend 状态机可能还没真正进入 suspended 就被 cancel，理论上等于没暂停过，最干净
- 没法不试就 100% 判断，纳入观察范围

### D. 内存层面
- 所有 4 个 DMPPageController + WebView 留在 `pageControllers[]`，跟 alpha=0 方案的引用图一致
- detach 后 WebContent 进程进 suspended，比 alive-but-hidden 占用更小

## 选定方案：裸 detach + process terminate 兜底

1. `switchTo(index:)` 切换 view 用 `removeFromSuperview` / `addSubview`，丢弃 alpha 操作
2. `ensurePageController(at:)` 创建时 `addChild`，**永不** `removeFromParent`
3. `DMPWebview` 注册 `WKNavigationDelegate.webViewWebContentProcessDidTerminate(_:)`：被 OS 杀掉 WebContent 时把 `poolState` 标 dirty，并在下一次 view 被 attach（`viewWillAppear` 或 `didMoveToWindow`）时重 `loadPageFrame()`

## 评估过但暂不上的替代

### Hybrid 延迟 detach
- 切到 isFirstVisit 的新 tab 时不立刻 detach 旧 tab，等新 tab fire `renderResourceLoaded` 或 2s 超时再 detach
- 从根上不去 detach mid-load 的 tab，理论最稳；但**违背 "标准内存管理" 的整洁性**，引入特殊状态机
- 决策：除非 process terminate 兜底仍不足以覆盖观察到的 race，否则不上

### pendingLoad guard
- tab 创建后到 fire `renderResourceLoaded` 之前记 `pendingLoad[i]=true`；切回该 tab 后 N 秒还未 fire → 主动重 `loadPageFrame()` 重启加载
- 兜底范围比 process terminate callback 更广（覆盖未知 WebKit corner case，不只是 process kill）
- 决策：先不上，靠 process terminate callback 观察实际行为；如果仍有 stuck 的复现 case，再补这一层

### 上游 alive-but-hidden 三件套
- `isHidden + alpha + bringSubviewToFront`
- 评估：失败模式不可恢复，调试成本高于本方案

## 不在本文档范围内

- tabBar UI 样式 / 配置解析（见 `DMPBundleAppConfig.swift` + `DMPTabBarView.swift`）
- service worker 的 "一次只激活一个 page" 假设（lazy 创建的根本原因，不在切换语义内）
- navigateTo / redirectTo / relaunch / switchTab API 的 JS 侧契约（见 Architecture-Lifecycle.md）

## 验证清单

实施后跑一遍：
- [ ] 启动落到 tab0，切到 tab1 / tab2 / tab3，每个能正常 firstRender
- [ ] tab1 加载未完时立刻点 tab2 → 切回 tab1，最终 DOM 正常
- [ ] 快速点击 tab1↔tab2 来回 5 次，无白屏
- [ ] tab1 切走后挂 10 分钟（触发 WebContent process reclaim 概率），切回时 reload 兜底生效
- [ ] navigateTo 进非 tab 页 → navigateBack → tab 还是切走前的状态
- [ ] tab1 内 `wx.navigateTo` 进二级页 → back → 二级页 destroyWebView 走通；tab1 状态不变
