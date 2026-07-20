# 公司 Fork 与 didi/dimina 上游差异说明

本文说明公司 fork 当前代码相对 `didi/dimina` 上游 `main` 做了哪些长期定制、每组定制解决什么问题，以及后续同步上游时应如何处理。

## 1. 对比基线

| 项目 | Commit | 说明 |
|---|---|---|
| 上游基线 | `c8cf93c50ba79f274bce1b288eb3a84eda1512a0` | `didi/dimina` 2026-07-18 的 `main` |
| fork 代码基线 | `a9af2acd171beb542810eb031863c8d26549affd` | 合入上游并清理安装环境噪音后的公司 fork |
| 本轮合并提交 | `b13adaf31b15d4a2531a79801a5fc8d6d296a1d3` | 第一父提交是旧 fork，第二父提交是上游基线 |
| 历史共同基线 | `05c75a9bc8eb156d7c5222b35154f88c99eaabc3` | 本轮同步前双方共同祖先 |
| 同步前 fork | `8b7ab55fb210dec5b79fa6aba99c5b225b21b63a` | 本轮同步前公司 fork 的 `main` |

固定基线下的整体差异：

```text
70 files changed, 8653 insertions(+), 2619 deletions(-)
```

这个数字包含公司补充的设计文档、宿主集成代码和若干较大规模的 iOS 架构改造，不能简单理解为 8,000 多行独立业务逻辑。

## 2. 结论

公司 fork 的核心定位不是“上游加几个 bugfix”，而是：

> 在 didi/dimina 的跨端小程序运行时之上，增加一层适配千岛 iOS 宿主、双引擎、版本化资源、宿主 UI 和线上诊断的集成层。

差异主要集中在 iOS，分为七类：

1. 千岛宿主与私有依赖集成；
2. Dimina/WebView 双引擎选择与版本化资源；
3. 宿主 overlay、导航栏和 TabBar；
4. Bridge 注册方式与业务所需 API 兼容；
5. WebView 复用、页面生命周期和白屏恢复；
6. 日志与 DOM 诊断；
7. CocoaPods/SPM 构建适配。

这些差异中，前六类直接承载宿主行为或线上稳定性，后续合并上游时不能整文件使用 `theirs` 覆盖。

## 3. 详细差异与目的

### 3.1 千岛宿主与私有依赖集成

主要文件：

- `Dimina.podspec`
- `iOS/dimina/DiminaKit/Utils/AppConfigManager.swift`
- `iOS/dimina/DiminaKit/Utils/DiminaEngineManager.swift`
- `iOS/dimina/DiminaKit/Utils/EngineSelectionConfig.swift`
- `iOS/dimina/DiminaKit/Utils/MiniProgramInfo+Extension.swift`
- `iOS/dimina/DiminaKit/App/DMPAppManager.swift`
- `iOS/dimina.xcodeproj/project.pbxproj`

修改内容：

- 接入 `echo_entity_swift`、`RxSwift`、`KurilUniversalKit` 等公司私有依赖；
- 从千岛接口读取 `MiniProgramInfo`，并根据服务端 `loader` 判断使用 Dimina 还是 WebView；
- 管理小程序包下载、解压、缓存、入口页和本地路径；
- 按 `appId + versionCode` 管理不同版本的本地资源；
- 对正式版复用 `lookup_apps_list` 缓存，体验版 `ex`、开发版 `dev` 和强制刷新场景直接请求远端；
- 保留宿主可配置的引擎选择规则和灰度入口。

目的：

- 让 Dimina 能作为千岛 App 的一套可选小程序引擎，而不是只能运行仓库内置 Demo；
- 避免体验版或开发版按 `appId` 错误命中正式版缓存；
- 支持旧 WebView 引擎与 Dimina 新引擎并存、灰度和回退；
- 复用千岛已有的小程序实体、网络层、下载器和本地缓存体系。

合并要求：

- 这是公司 fork 的宿主适配边界，必须保留；
- 上游无法直接编译这些文件，因为上游没有公司私有依赖；
- SPM 构建会排除这三份宿主文件，真正的宿主集成需要在 Kuril CocoaPods/工程环境中验证。

### 3.2 双引擎与版本化资源体系

主要文件：

- `iOS/dimina/DiminaKit/App/DMPApp.swift`
- `iOS/dimina/DiminaKit/App/DMPAppConfig.swift`
- `iOS/dimina/DiminaKit/Bundle/DMPResourceConfig.swift`
- `iOS/dimina/DiminaKit/Bundle/DMPResourceManager.swift`
- `iOS/dimina/DiminaKit/Bundle/DMPSandboxManager.swift`
- `iOS/dimina/DiminaKit/Render/DiminaURLSchemeHandler.swift`
- `iOS/dimina/DiminaKit/Render/DifileURLSchemeHandler.swift`
- `iOS/dimina/DiminaKit/Utils/DMPFileUtil.swift`
- `iOS/dimina/DiminaKit/Utils/DMPMediaFileUtil.swift`

修改内容：

- `DMPAppConfig` 对宿主公开 `appId`、路径、版本和展示配置；
- 资源目录从单纯 `appId` 扩展为可感知 `versionCode` 的路径；
- `DMPApp.launch` 注册 `appId -> versionCode` 映射，URL Scheme Handler 按对应版本取文件；
- 资源加载支持 SPM Bundle、主 Bundle、远端 Bundle 的 fallback；
- 增加远端 JSApp Bundle 配置、下载、刷新和缓存检查；
- 根据引擎类型和启动环境建立不同的下载目录；
- 同时兼容 `.emp`、`.zip` 以及多种历史解压目录结构；
- Scheme 路径解析保留版本能力，同时合入了上游的路径穿越防护。

目的：

- 同一个小程序可以并存正式版、体验版和开发版资源；
- 页面、图片、脚本和 TabBar 图标必须读取启动时选中的版本，不能串包；
- 支持 App 内置资源、SPM 资源和线上下发资源三种交付方式；
- 兼容公司历史小程序包格式和目录布局；
- 防止旧包、错误缓存或非法相对路径导致白屏和越界读文件。

合并要求：

- `DMPResourceManager`、`DMPSandboxManager` 和两个 URL Scheme Handler 是高冲突区；
- 合并上游安全修复时，应把安全校验叠加到版本化路径上，不能退回上游的无版本路径；
- 任何目录调整都需要同时验证 service、render、媒体文件和 TabBar 图标。

### 3.3 宿主 Overlay、导航栏与 TabBar

主要文件：

- `iOS/dimina/DiminaKit/Container/DMPPageOverlayProvider.swift`
- `iOS/dimina/DiminaKit/Container/DMPPageController.swift`
- `iOS/dimina/DiminaKit/Container/UI/DMPTabBarContainerController.swift`
- `iOS/dimina/DiminaKit/Container/UI/DMPTabBarView.swift`
- `iOS/dimina/DiminaKit/Container/Api/UI/NavigationBarAPI.swift`
- `iOS/dimina/DiminaKit/Container/Api/UI/TabBarAPI.swift`
- `iOS/dimina/DiminaKit/Container/Api/UI/MenuAPI.swift`
- `iOS/dimina/DiminaKit/Navigator/DMPNavigator.swift`
- `iOS/dimina/DiminaKit/Bundle/DMPBundleAppConfig.swift`

修改内容：

- 增加 `DMPPageOverlayProvider`，允许宿主把胶囊按钮等视图覆盖到小程序页面；
- 增加 `DMPNavigationBarColorApplicable`，让 `wx.setNavigationBarColor` 同步宿主 overlay 的前景色和背景色；
- 自建 UIKit TabBar 容器和视图，支持图标、选中态、隐藏、badge 和 red dot；
- 扩展 `app-config.json` 的 window/tabBar 数据模型并规范化页面路径；
- `switchTab`、push、back、redirect 等导航操作同步页面记录和生命周期；
- 对暗色模式、导航栏样式缓存和宿主胶囊关闭行为做了适配；
- 本轮同步吸收上游新的菜单按钮几何计算，但保留宿主 overlay 协议。

目的：

- 千岛 App 的小程序顶部需要使用宿主统一的胶囊和关闭入口；
- 小程序调用导航栏 API 时，Web 内容与宿主控件必须保持同一颜色和明暗模式；
- Taro/微信小程序的 TabBar API 需要真实更新原生 UI，而不是只返回成功；
- 修复 TabBar 快速切换、页面记录不一致和页面生命周期错序导致的白屏。

合并要求：

- 上游 TabBar 的 “alive-but-hidden” 模型与 fork 当前 “detach + 必要时销毁” 模型不同；
- 不应仅按文件新旧选择实现，必须根据 `docs/TabBar-Memory-Model.md` 重新验证内存和生命周期；
- `DMPNavigator.swift`、`DMPPageController.swift` 和 TabBar 容器需要作为一个整体评审。

### 3.4 Bridge 注册与 API 兼容层

主要文件：

- `iOS/dimina/DiminaKit/Container/Api/DMPContainerApi.swift`
- `iOS/dimina/DiminaKit/Container/Api/DMPApiHandler.swift`
- `iOS/dimina/DiminaKit/Container/Api/Base/BaseAPI.swift`
- `iOS/dimina/DiminaKit/Container/Api/Base/FileSystemAPI.swift`
- `iOS/dimina/DiminaKit/Container/Api/Device/DeviceAPI.swift`
- `iOS/dimina/DiminaKit/Container/Api/Media/AudioAPI.swift`
- `iOS/dimina/DiminaKit/Container/Api/Storage/StorageAPI.swift`
- `iOS/dimina/DiminaKit/Container/Api/UI/InteractionAPI.swift`
- 其他经过 `init + register()` 改造的内置 API 文件

修改内容：

- 大部分原有内置 API 从 `@BridgeMethod` property wrapper 改成在 `init` 中显式 `register()`；
- 内置 API 仍由静态表承载，宿主 API 改为 `DMPApp.registerApi(_:)` 按 App 实例注册；
- 宿主 handler 通过 `DMPBaseApiHandler` 显式声明方法，冲突默认拒绝，也可显式 `.replace`；
- `DMPContainerApi.create()` 显式实例化并注册所有内置 API；
- 将当前 App 的 API 名称和自定义 namespace 注入 service JS；
- `wx.login` 由 EchoWebKit 的业务 handler 注入，Dimina 不再持有登录 provider；
- 原始页面 URL 在 `DMPPageRoute` 中统一拆成 `pagePath + query`，WebView 只接收规范化后的路径；
- 增加文件系统、设备信息、音频、TabBar 和 UI 反馈等业务需要的 API；
- 在 service 启动阶段为 Taro 和部分微信同步 API 注入兼容层；
- Storage Sync API 同时接受数组参数和对象参数，并按 `appId` 隔离存储。

目的：

- 避免依赖 property wrapper 初始化副作用注册全局 handler，减少注册时序不确定和 `swiftc` 问题；
- 允许公司其他模块注入自定义 API，且不会污染其他小程序实例；
- 补齐线上小程序和 Taro 应用实际调用、但上游当时未覆盖的 API；
- 防止某个小程序读取到另一个小程序的 storage；
- 避免缺失方法直接抛 `TypeError` 并中断首屏渲染。

合并要求：

- 新上游 API 仍有部分使用 `@BridgeMethod`，当前处于两种注册方式共存状态；
- 新增 API 时必须确认 `DMPContainerApi.create()` 已实例化对应类型；
- 不要把 fork 内置 API 整体换回 wrapper 模式；
- 宿主 API 必须在 `DMPApp.launch` 前注册；仅在明确覆盖内置实现时使用 `.replace`；
- JS polyfill 只应作为 Native API 缺口的兼容层，不能无验证地继续堆叠空实现。

### 3.5 WebView 复用、生命周期与白屏恢复

主要文件：

- `iOS/dimina/DiminaKit/Render/DMPWebViewPool.swift`
- `iOS/dimina/DiminaKit/Render/DMPWebview.swift`
- `iOS/dimina/DiminaKit/Render/DMPWebViewOptimizer.swift`
- `iOS/dimina/DiminaKit/Render/DMPWebViewUnified.swift`
- `iOS/dimina/DiminaKit/Render/DMPRender.swift`
- `iOS/dimina/DiminaKit/Render/DMPWebViewInvoke.swift`
- `iOS/dimina/DiminaKit/Container/DMPChannelProxy.swift`
- `iOS/dimina/DiminaKit/Navigator/DMPNavigator.swift`

修改内容：

- fork 保留全局 WebView 池，复用时重新绑定 `appId`、scheme handler、delegate 和 bridge 状态；
- 释放 WebView 时分阶段清理脚本、消息 handler、回调和页面状态；
- 关闭 `suppressesIncrementalRendering`，避免非根页面等待全部资源后才显示；
- 增加 `renderResourceLoaded` watchdog 和 DOM 可见性救援；
- WebContent Process 被系统终止后重新加载 page frame；
- `pagePath` 入池前去掉 query，避免 CSS/JS 资源名计算错误；
- 增加 UIKit/SwiftUI WebView 选择和工厂配置；
- 自定义 URL scheme 由宿主注册，并在 WebView 复用时更新对应的 `appId`。

目的：

- 降低频繁 push、back 和 TabBar 切换时创建 WKWebView 的成本；
- 防止复用 WebView 残留上一个小程序的脚本、回调或资源路径；
- 修复 push 页面出现 zero-frame、首屏不显示和 WebContent Process 终止后的白屏；
- 保持宿主自定义 scheme 在复用后的 WebView 中仍然可用。

合并要求：

- 这是 fork 与上游分歧最大的区域之一；
- 不能只验证“能编译”，必须覆盖快速 push/back、快速切 Tab、内存警告和进程终止；
- 设计依据见 `docs/Push-Page-Memory-Model.md` 和 `docs/TabBar-Memory-Model.md`。

### 3.6 日志和诊断

主要文件：

- `iOS/dimina/DiminaKit/Utils/DMPLog.swift`
- `iOS/dimina/DiminaKit/Service/DMPEngineLog.swift`
- `iOS/dimina/DiminaKit/Render/DMPWebViewLogger.swift`
- `iOS/dimina/DiminaKit/Render/DMPWebview.swift`
- `iOS/dimina/DiminaKit/Render/DMPWebViewPool.swift`
- `docs/Debugging-Infrastructure.md`

修改内容：

- 增加统一的 `DMPLog`，按 app、render、bridge、bundle、pool、scheme 分类；
- 同时输出到 `os_log` 和 `Documents/dimina.log`；
- 对共享日志配置和 ID 生成器增加显式锁，避免多线程数据竞争；
- 捕获 JSContext console error；
- 记录 WebView 加载、DOM 尺寸/可见性、资源解析、池状态和页面生命周期；
- 资源加载失败时记录实际路径、相邻文件和错误域。

目的：

- 小程序白屏通常跨 service、render、scheme 和 WebView 多层，普通单点日志无法还原链路；
- 文件日志便于从测试设备直接取回；
- 分类日志可以在 Console.app 中快速过滤；
- DOM 诊断用于区分“没有生成 DOM”“DOM 为零尺寸”“DOM 存在但不可见”。

合并要求：

- 上游 `DMPLogger` 更新可以吸收，但不能移除 fork 的分类和落盘能力；
- 新增页面加载或资源路径分支时，应继续使用对应 channel。

### 3.7 构建和分发方式

主要文件：

- `Dimina.podspec`
- `Package.swift`
- `iOS/dimina.xcodeproj/project.pbxproj`

修改内容：

- 增加 CocoaPods podspec 和公司私有依赖；
- SPM target 排除只能在千岛宿主环境编译的三个文件；
- SPM 声明 Swift 5 language mode，与 Xcode 工程的 `SWIFT_VERSION = 5.0` 保持一致；
- Xcode 工程纳入 fork 新增的源码和资源。

目的：

- 公司项目继续通过 CocoaPods/本地 pod 集成；
- 开源核心部分仍可通过 SPM 独立编译；
- 避免 Swift tools 6 默认启用 Swift 6 严格并发后，把仍按 Swift 5 维护的代码当成编译错误。

当前注意事项：

- `Dimina.podspec` 仍是 `1.1.4`，而当前 SDK/Xcode 工程是 `1.4.1`；
- podspec 的 `source` 仍指向 didi 上游仓库；
- 在正式发布下一个 pod 版本前，需要单独统一版本号和 source，不能把它当成本轮上游同步的一部分静默修改。

## 4. 不属于 fork 定制的内容

本轮已经合入的以下能力来自上游，不应在后续评审中误判为公司私有实现：

- Bluetooth/BLE API；
- Local Network、UDP、TCP 和服务发现；
- 新 File API；
- Scan API；
- 新菜单按钮几何计算；
- 按 app 隔离的部分上游 storage 改进；
- 路径穿越防护；
- JSSDK `1.0.18`。

判断原则：

```bash
# 只看 fork 当前相对上游仍然不同的内容
git diff c8cf93c50ba79f274bce1b288eb3a84eda1512a0..a9af2acd171beb542810eb031863c8d26549affd
```

如果某段代码不出现在这个 diff 中，它已经与本轮上游基线一致。

## 5. 后续同步上游的处理原则

| 区域 | 默认策略 | 原因 |
|---|---|---|
| Android、Harmony、FE 通用运行时 | 优先跟随上游 | 当前 fork 的长期差异主要不在这些区域 |
| 宿主集成与双引擎 | 保留 fork，逐段吸收上游 | 依赖公司模型、接口和缓存规则 |
| Resource/Sandbox/Scheme | 手工合并 | 必须同时保留版本路径和上游安全修复 |
| Navigator/Page/TabBar | 按行为合并 | 两边内存模型和生命周期语义不同 |
| WebView Pool/Optimizer/Webview | 手工合并并做压力测试 | 容易引入跨 app 残留和白屏 |
| Bridge/API 注册 | 保留显式注册，补接新上游 API | 当前处于两种注册方式共存期 |
| 日志与诊断 | 保留 fork | 是线上问题定位基础设施 |
| 文档 | 两边都保留 | fork 文档记录了偏离上游的设计原因 |

禁止做法：

- 对上述高冲突区批量执行 `checkout --theirs`；
- 为了消除冲突直接删除宿主协议、版本参数或诊断代码；
- 只做编译验证，不跑页面生命周期和资源隔离测试；
- 在未核对 app/version 的情况下复用旧缓存；
- 覆盖 fork 标签或强推改写 fork 历史。

## 6. 可复现的代码 Diff

### 6.1 完整 fork 差异

```bash
git fetch origin main
git fetch upstream main
git diff --stat c8cf93c50ba79f274bce1b288eb3a84eda1512a0..a9af2acd171beb542810eb031863c8d26549affd
git diff --name-status c8cf93c50ba79f274bce1b288eb3a84eda1512a0..a9af2acd171beb542810eb031863c8d26549affd
git diff c8cf93c50ba79f274bce1b288eb3a84eda1512a0..a9af2acd171beb542810eb031863c8d26549affd
```

### 6.2 只看某个高冲突域

```bash
# 宿主和双引擎
git diff c8cf93c..a9af2ac -- \
  iOS/dimina/DiminaKit/Utils/AppConfigManager.swift \
  iOS/dimina/DiminaKit/Utils/DiminaEngineManager.swift \
  iOS/dimina/DiminaKit/Utils/EngineSelectionConfig.swift

# 资源与版本路径
git diff c8cf93c..a9af2ac -- \
  iOS/dimina/DiminaKit/Bundle \
  iOS/dimina/DiminaKit/Render/DiminaURLSchemeHandler.swift \
  iOS/dimina/DiminaKit/Utils/DMPFileUtil.swift

# 导航、TabBar 和页面模型
git diff c8cf93c..a9af2ac -- \
  iOS/dimina/DiminaKit/Navigator \
  iOS/dimina/DiminaKit/Container/DMPPageController.swift \
  iOS/dimina/DiminaKit/Container/UI

# Bridge 与 API
git diff c8cf93c..a9af2ac -- \
  iOS/dimina/DiminaKit/Container/Api

# WebView 与白屏恢复
git diff c8cf93c..a9af2ac -- \
  iOS/dimina/DiminaKit/Render
```

### 6.3 查看本轮冲突是如何解决的

```bash
git show --remerge-diff b13adaf31b15d4a2531a79801a5fc8d6d296a1d3
```

这个命令会重演三方合并并显示人工冲突处理，适合审查是否同时保留了 fork 行为和上游修改。

### 6.4 查看同步前 fork 的历史来源

```bash
git log --reverse --oneline \
  05c75a9bc8eb156d7c5222b35154f88c99eaabc3..8b7ab55fb210dec5b79fa6aba99c5b225b21b63a
```

## 7. 已知技术债

以下内容属于当前 fork 的真实状态，但不应被当成理想设计长期固化：

1. `AppConfigManager` 与 `DiminaEngineManager` 职责有较大重叠，下载、缓存和路径判断存在重复；
2. 内置 API 的显式注册与新上游 API 的 `@BridgeMethod` 暂时共存；
3. `DMPApp.loadBundle()` 中有较多 JS polyfill，部分同步文件 API 是兼容性占位实现；
4. `DiminaEngineManager` 中仍存在开发机模拟器路径辅助代码，不适合作为通用发布逻辑；
5. 部分调试输出仍使用 `print`/`NSLog`，尚未全部归入 `DMPLog`；
6. CocoaPods、Xcode 和 SDK 内置版本号尚未完全统一；
7. SPM 构建通过不代表千岛私有依赖集成通过，宿主工程仍需要单独验证。

这些问题适合拆成独立重构任务，不应夹在下一次上游同步中顺手大改。

## 8. 回归验证重点

每次改动上述 fork 区域，至少覆盖：

- 正式版、体验版、开发版是否加载正确版本；
- Dimina/WebView 双引擎选择和回退；
- `wx.login` 及宿主 provider；
- storage 跨 app 隔离和数组/对象两种 Sync 参数；
- navigateTo、navigateBack、redirectTo、reLaunch、switchTab；
- TabBar 快速切换、badge、red dot 和 show/hide；
- 宿主胶囊的关闭行为、导航栏颜色和暗色模式；
- WebView 池复用后 appId、scheme handler 和回调是否残留；
- push 页面首屏、WebContent Process 终止和内存警告恢复；
- app/version 路径下的 JS、CSS、图片和媒体资源；
- `dimina.log` 是否能串起 app、bundle、bridge、render、pool、scheme 全链路。

更细的用例见：

- `docs/MiniApp-Test-List.md`
- `docs/Push-Page-Memory-Model.md`
- `docs/TabBar-Memory-Model.md`
- `docs/Debugging-Infrastructure.md`
- `docs/BridgeMethod-Refactor-Plan.md`
