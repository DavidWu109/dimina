# Push Page 加载时序与 zero-frame race

> 决定 Dimina iOS 端 `navigateTo` push 的 page 何时启动 `loadPageFrame()`；为什么对 `isRoot=true`（tab 容器子页和 launch 根页）继续 eager load，对 `isRoot=false`（push）延迟到 `viewDidAppear`。与 [[TabBar-Memory-Model]] 互为姊妹文档。

## 现象

调用栈：mini-app 内 `wx.navigateTo` → `DMPNavigator.navigateTo` → `navigationController.pushViewController(pageController, animated: true)`。

观察到 push 进 `pages/activity-detail/index` 等非 tab 页时**间歇性永久白屏**。复现 log（2026-05-23 17:56:37–48）：

```
17:56:37.831 loadPageFrame id=12
17:56:38.161 webViewDidFinishLoad id=12          ← pageFrame.html 加载完
17:56:38.161 serviceResourceLoaded bridgeId=12 allLoaded=false
                                                  ← renderResourceLoaded 永远没来
17:56:41.199 DOM diag id=12 t=3.0s  {"htmlRect":{"w":402,"h":0}, "bodyHTMLLen":0}
17:56:48.217 DOM diag id=12 t=10.0s {"htmlRect":{"w":402,"h":0}, "bodyHTMLLen":0}
```

关键：**document.documentElement.getBoundingClientRect().height = 0** 持续到 t=10s。同一 session 内更早的 push（id=10）反而 fire 了完整的 serviceResourceLoaded + renderResourceLoaded，allLoaded=true，正常显示。说明这是**概率性 timing race**，不是确定性 bug。

## 根因

iOS 15+ 已知问题：WKWebView 在被加入 view hierarchy **之前**（或在 push 动画 0-frame 期间）调用 `load*`，可能踩到下列任一种：

- WebContent process launch 要 >1s。如果 window 在 process 启动完前就 drawn，page 不会 render（[Apple Forums 65711](https://developer.apple.com/forums/thread/65711) / [740991](https://developer.apple.com/forums/thread/740991)）
- iOS 检测到 WebContent process 在背景（view 还没 onscreen），可能在 init 完成前 kill 它
- WKWebView 在 frame=0 时**不**初始化 layout / render pipeline；pageFrame.js 里依赖 layout 触发的 reflow 不发生，`invoke({type:'renderResourceLoaded'})` 那一行可能跑不到（或跑到了但消息被 WebKit 在异常状态下吞掉）

这跟 [[TabBar-Memory-Model]] 里讨论的 `alpha=0` 半节流是不同的失败模式：tabBar 是切走 mid-load 的 race，这里是 push 动画期间 WebView 自始至终就没拿到稳定 frame。

## 为什么 isRoot=true 不踩坑

`isRoot=true` 涵盖两条路径，都不走"push 动画期间 frame=0"这条路：

1. **tab 容器的 child page**：通过 `DMPTabBarContainerController.attachChildView(_:)` 直接 `addSubview` 到 `currentChildContainer`。容器自身 `viewDidLoad` 已经把 `currentChildContainer` 的 layout 跑完了，child 一上来就拿到非零 frame
2. **launch 根页**（直接 `launch(to:)` 进非 tab 页的情形）：作为整个 nav stack 的第一个 VC，set 进 navigationController 时虽然 animated=true，但**没有 from-VC**，UIKit 走的是 "set initial" 路径，没有 push transition container 那一套 0-frame 中间态

session 中 4 个 tab 全部 eager load 成功、id=2/4/6/8 都 allLoaded=true，验证了这个判断。

## 行业方案对比

| 方案 | 代价 | 我们的取舍 |
|---|---|---|
| **延迟 load 到 viewDidAppear** | navigateTo 多 ~300ms 等待，但是有 loading 状态的等待 | **选这个**。改动量小，语义清晰 |
| `loadHTMLString:baseURL:` 替代 `loadFileURL` | 改动 pageFrame.html 加载方式，需要内联或预读文件内容 | 不选。绕过 sandbox 路径但要重写加载逻辑 |
| `alwaysRunsAtForegroundPriority` config | macOS-only API，iOS 没这个 | 不可选 |
| swizzle WKWebView init 注入 viewport / inset | Flutter InAppWebView 走的路；对所有 WebView 全局生效 | 不选。侵入太大，副作用面广 |
| Pre-render detection loop（轮询 3s 检查 webview 死活后重建） | 一直耗 timer + 重建 WebView 成本 | 不选。Best-effort 兜底层面 |

## 选定方案

动 `DMPPageController`：

1. 加 `hasLoadedPageFrame` 标志区分 eager / deferred load 路径
2. `configWebView()` 只在 `isRoot=true` 时立刻 `loadPageFrame()`
3. `viewDidAppear` 里 `isRoot=false` 首次时 load，但**先 guard `view.bounds.height > 0`**
4. 如果 viewDidAppear 时 height 仍是 0（极少数 timing 边界），warn 一行，挂 300ms async 救援

```swift
private var hasLoadedPageFrame = false

private func configWebView() {
    self.webview.setPagePath(pagePath: pagePath)
    if let query = query { self.webview.setQuery(query: query) }
    webview.poolState = .loading

    if isRoot {
        hasLoadedPageFrame = true
        webview.loadPageFrame()
    }
}

public override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    // 诊断日志（留着观察救援触发频率 + 万一别的页面踩 race 时定位）
    DMPLog.app.info("viewDidAppear id=... self.bounds=... wkView.frame=... wkView.window=...")

    guard !hasLoadedPageFrame else { return }

    if view.bounds.height > 0 {
        hasLoadedPageFrame = true
        webview.loadPageFrame()
    } else {
        // zero-height guard: viewDidAppear 偶发在 layout settle 前 fire
        // (实测保留诊断日志读 view.frame 的副作用后频率显著下降，但不能依赖那个副作用)
        DMPLog.render.warn("⚠️ viewDidAppear with ZERO height — deferring 300ms (zero-frame race recovery)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, !self.hasLoadedPageFrame else { return }
            self.hasLoadedPageFrame = true
            self.webview.loadPageFrame()
        }
    }
}
```

### 为什么救援用 300ms

- 0 ms（下一个 runloop tick）：可能 layout 还没跑完
- 50–100 ms：通常够，但极端动画/嵌套 nav 边界 case 可能仍然不够
- 300 ms：足以覆盖一次完整的 layout pass + 一次再 push 进 transition container 的极端 case；用户感知 = ~300ms 多一点的"白屏过渡"，已经比"永久白屏"好得多
- 不做 retry-loop：300ms 后仍 0 的话八成是页面本身配置错（比如全屏 fullscreen 模式但容器约束错），这是另一类 bug，不该用 retry 掩盖

## 代价与边界

- **UX**: push 后用户额外等待 ~300ms（pageFrame.html load + pageFrame.js init），但 push 动画期间本来就有 0.35s 过场，用户感知的"动画结束→内容出现"间隔从原来的"瞬间出（成功）/ 永久白（失败）"变成"约 300ms 后稳定出"。整体可观测性 + 可恢复性都更好

- **service / render 时序**: `DMPNavigator.navigateTo` 在 push 之前 `await app?.service?.loadSubPackage(pagePath:)`。所以 push 时 service 已经 ready，会很快 fire `serviceResourceLoaded`（loadStatusMap=.serviceLoaded）。viewDidAppear 之后 render 端 loadPageFrame → 最终 `renderResourceLoaded` 补上，OR-merge 到 `.allLoaded` → service `createInstance`。整个链路顺序兼容，OR-merge 逻辑天然兜底乱序

- **push 后立即 navigateBack 的极端 case**: 如果用户在 viewDidAppear 跑之前就触发了 back（理论可能，实际很难），WebView 没加载就被 destroy。走 `DMPPageController.deinit → destroyWebView() → app?.render?.releaseWebView(webview)` 释放回池子，这是正确语义。不会泄漏

## 进一步发现：sharedProcessPool + suppressesIncrementalRendering 才是更深的根因

实际跑下来发现纯延迟到 viewDidAppear 不够 —— 仍然有 ~1/5 概率撞到这种 case：
- `viewDidAppear` 时 `view.bounds.height = 773` 正常
- WebKit 自报 `didFinishLoad` 也正常
- 但 DOM `bodyHTMLLen = 0`、`htmlRect.h = 0`，pageFrame.js 似乎没真的执行
- 永远收不到 `renderResourceLoaded`

git diff 上游 didi/dimina 发现两个**上游原本就有**的设计点是这个 race 的根：

1. **`DMPWebViewOptimizer.applyProcessPoolOptimizations`**：所有 WebView 共用同一个 `DMPWebViewPool.sharedProcessPool`。按 [bigyelow blog](https://bigyelow.github.io/2018/%20Bugfix%20for%20WKWebView%20Blank%20Issue.html) 的分析：
   > "Each web view is given its own web content process **until an implementation-defined process limit is reached**; after that, web views with the same process pool end up sharing web content processes."
   
   我们 `pool inUse=5+` 时新建第 6 个 WebView，命中 process 数限制 → 复用旧 process → 旧 process 在 bad state（前一次 cleanup 残留？）→ 新 WebView 的 render pipeline 卡死，但 didFinishLoad 照报（WebKit 觉得 navigation 完成了，render 是另一回事）。

2. **`config.suppressesIncrementalRendering = true`**（上游也是）：让 WKWebView 在完整 render 完成前一片不显示。pipeline 一卡 → 永久纯白没有任何中间态，雪上加霜。

这两条**都是上游 didi/dimina 自带**，不是我们引入的。但我们的 mini-app 用得更复杂、tab 多、push 频繁，触发率比上游 demo 高得多。

## 实施的三层方案

### L1：关掉 `suppressesIncrementalRendering`（故意偏离上游）

`DMPWebViewOptimizer.applyMemoryOptimizations` 改 `false`。让 render pipeline 部分卡也能看到已加载的部分，最差情况从"永久纯白"降级到"渐进显示中"。零代码风险，立即改善用户感知。

### L2：renderResourceLoaded watchdog（DMPPageController）

`loadPageFrameAndWatchdog()` helper 包装 `loadPageFrame()`：
- 3s 后查 `container.isResourceLoaded(webViewId:)` 仍 false → warn + 再 `loadPageFrame()`（相当于 reload）
- 6s 后还 false → error log，认输；WebKit 自己进了死状态，要 user back+retry

```swift
private func loadPageFrameAndWatchdog() {
    let id = webview.getWebViewId()
    webview.loadPageFrame()
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
        guard let self = self, !self.isWebViewDestroyed else { return }
        if self.app?.container?.isResourceLoaded(webViewId: id) == true { return }
        DMPLog.render.warn("⚠️ render watchdog: bridgeId=\(id) not allLoaded after 3s — retrying loadPageFrame")
        self.webview.loadPageFrame()
        // 再 3s 查一次, 还不行就 error 不再重试
        ...
    }
}
```

替代过的方案：完全 release WebView 再 acquire 新的、reroute service bridge —— 代价大且 webViewId 变更影响面广。L2 先用最小入侵的 reload 兜底，观察实际触发频率。

### 路径调用

| 路径 | 时机 | 是否走 watchdog |
|---|---|---|
| isRoot=true (tab/launch 根页) | `configWebView()` 里立刻 | ✓（同 helper） |
| isRoot=false (push) - 主路径 | `viewDidAppear` first + height>0 | ✓ |
| isRoot=false (push) - 0-height 救援 | `viewDidAppear` first + height==0 → 300ms 后 | ✓ |

## 评估过但暂不上

- **L3：push 页用独立 WKProcessPool**：DMPPageController 创建 WebView 时不传 sharedProcessPool 而是 `WKProcessPool()`。从根上避免 process 共享污染。代价：每个 process pool ~10MB；架构上要打破上游 DMPWebViewPool 的池化语义。先看 L1+L2 是否够稳，不够再上。
- **`alwaysRunsAtForegroundPriority` 的等价 workaround**：iOS 没有官方 API。私有 `_alwaysRunsAtForegroundPriority` 上 App Store 风险大。不上
- **Push `animated: false`**：从源头跳过 0-frame transition container。代价是失去过场动画，UX 倒退。不上
- **完全重建 WebView（watchdog L2 的升级版）**：release + acquire 新 webView + reroute bridgeId + reattach view。bridgeId 变更涉及 service 端路由重置和 pageRecord 更新，复杂度高。如果 L2 的 reload 兜底证实无效再上

## 验证清单

- [ ] 反复 push `pages/activity-detail/index` 至少 10 次，无白屏，每次 log 都看到 `renderResourceLoaded bridgeId=N allLoaded=true`
- [ ] push 后立即 navigateBack（500ms 内），无 crash，bridgeId 释放正常
- [ ] push 进二级页 → 再 push 三级页 → back 两次回 tab，各级 page 状态保留
- [ ] tab 切换仍然正常（验证 isRoot=true 路径未受影响）
- [ ] launch 落到非 tab 页（如果业务有这条路径），首屏正常

## 与 TabBar-Memory-Model 的呼应

两个文档处理的是不同层的"页面入栈"语义：

- [[TabBar-Memory-Model]] —— tabBar **内部**多 tab 切换的 view 复用机制（attach/detach）
- [[Push-Page-Memory-Model]] (本文) —— 通过 `navigateTo` 在 nav stack 上 **push 新 page** 时的 WebView 加载时序

两者共享 `DMPPageController` 这个底层。两者修复的 race 也都源自 "WebView 在视图层级未稳定时" 这一类问题，但具体触发条件不同，所以方案不能复用：

| 触发 | TabBar race | Push race |
|---|---|---|
| 信号丢失原因 | `alpha=0` 半节流期间 invoke 排不进 / 发不出 | frame=0 期间 layout 没启动，pageFrame.js 跑不完 |
| 修法 | 改成 detach（`window=nil` 干净 suspend） | 延迟到 view 拿到稳定 frame 再 load |
