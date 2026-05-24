# Dimina 调试基础设施（iOS）

> 本文档描述 Dimina iOS 端的统一日志、错误捕获、白屏诊断三套基础设施，以及典型排查链路。
> 适用引擎：Dimina（EMP）。

## 1. 统一日志门面 `DMPLog`

位置：`iOS/dimina/DiminaKit/Utils/DMPLog.swift`

替换原先散落各处的 `print()` / 三份独立的文件日志（`dimina_launch.log` / `dimina_render.log` / `dimina_scheme.log`），统一到一个门面。

### 1.1 频道（category）

| Channel | 用途 |
|---------|------|
| `app`    | DMPApp 生命周期：launch start/finish, initBundle/Container/Service/Render, openPage |
| `render` | DMPRender / WebView：loadPageFrame, didFinish/didFail navigation, marked as ready |
| `bridge` | JSBridge invoke / publish：container→service / service→render 消息流 |
| `bundle` | 资源包：app-config.json 加载, loadResourceService/Render |
| `pool`   | WebView 复用池：acquire (reused/new), release, recycle, pool snapshot |
| `scheme` | 自定义 URLScheme 资源解析：`dimina://` / `difile://` 路径解析 + 文件存在性 |

### 1.2 级别（severity）

`debug → info → warn → error`，可通过 `DMPLog.minimumLevel` 在运行时调整。默认 `.debug`（开发期），线上建议 `.info`。

### 1.3 输出位置

每条日志双写两路：

**A. `os_log`（subsystem = `com.echo.dimina`，category = 频道名）**

实时过滤：
```bash
# 全部 Dimina 日志（含 info/debug）
xcrun simctl spawn booted log show --last 1m --info --debug \
  --predicate 'subsystem == "com.echo.dimina"' --style compact

# 单频道
xcrun simctl spawn booted log show --info --debug \
  --predicate 'subsystem == "com.echo.dimina" AND category == "render"'

# 只看 warn/error
xcrun simctl spawn booted log show \
  --predicate 'subsystem == "com.echo.dimina"'
```

> 注意：`log show` 默认只显示 `default` 及以上级别。`.info` 和 `.debug` 必须显式带 `--info --debug` 才能看到。

**B. 文件 `Documents/dimina.log`**

每次 `DMPApp.launch` 调用 `DMPLog.resetFile()` 清空，所以这份是「最近一次启动」的完整记录。模拟器上：
```bash
CONTAINER=$(xcrun simctl get_app_container booted <bundle-id> data)
cat "$CONTAINER/Documents/dimina.log"
```

### 1.4 调用方式

```swift
DMPLog.app.info("launch start, appId=\(appId)")
DMPLog.scheme.error("resource not found: \(path)")
DMPLog.pool.debug("acquire id=\(id) reused=\(reused) \(poolSnapshot())")
```

每条记录自动追加 `(file.swift:line)` 便于跳转。

## 2. JSContext Console 错误捕获

位置：`iOS/dimina/DiminaKit/Service/DMPEngineLog.swift`

### 2.1 之前的 bug

`formatJSValue(_:)` 对 Error 对象走 `value.toDictionary()` 路径，但 `Error.message` / `Error.stack` 是 **non-enumerable** 属性，导致序列化结果是空字典 `{}`。线上看到的 `❌ [ERROR] { }` 完全无价值，无法定位 mini-app 的 JS 异常。

### 2.2 修复

`formatJSValue` 现在检测 `value.constructor.name` 以 `Error` 结尾时显式取 `.name / .message / .stack`，否则才走 dictionary 序列化。空字典回退到 `toString()` 并附带 `message` 字段（如果有）。

输出示例：
```
❌ [ERROR] TypeError: e.Taro.setTabBarStyle is not a function. (In 'e.Taro.setTabBarStyle(...)', 'e.Taro.setTabBarStyle' is undefined)
r@
@
Na2@
```

> Stack 通常因 mini-app 经过 minify 而成为单字母帧，凭 message 就能定位调用点。

## 3. WebView DOM 诊断（白屏排查）

位置：`DMPRender.swift` 的 `scheduleDOMDiagnostics(webview:webViewId:)`

`webViewDidFinishLoad` 之后，分别在 **3s 和 10s** 通过 `executeJavaScript` dump 当前 WebView 的 DOM 实时状态，结果写入 `DMPLog.render.info`，自动落到 `dimina.log`。

dump 字段：

```json
{
  "htmlFontSize": "0.535987px",
  "htmlRect": {"w": 402, "h": 0},
  "bodyRect":  {"w": 402, "h": 0},
  "bodyHTMLLen": 51,
  "bodyChildren": [
    {
      "tag": "div", "cls": "dd-page dd-view",
      "w": 402, "h": 0,
      "display": "block", "visibility": "visible", "opacity": "1",
      "childCount": 0
    }
  ],
  "pageFrame": "NOT FOUND",
  "errors": [],
  "netErrors": [],
  "url": "file://.../Dimina/sdk/main/pageFrame.html"
}
```

### 3.1 怎么读

- `bodyChildren[0].childCount == 0` + `h == 0` → **白屏**：根容器存在但里面没节点
- `bodyHTMLLen` 接近 `<body><div class="dd-page dd-view"></div></body>` 的字符数 → render 端 bridge 收到空 `cn:[]`，service 没下发节点
- `errors` 是 `window.__diminaErrors`（如果 mini-app 注入了全局错误捕获）的最近 10 条
- `htmlFontSize` 异常小（< 1px）是正常的 —— Dimina 的 rem 适配方案

### 3.2 典型链路对比

**正常**：3s 时 `bodyChildren` 已有多个有尺寸的子节点 / `childCount > 0`
**白屏**：3s 和 10s 都是 `cn:[]`、`childCount:0、h:0` → 跑到 4 看 service 端报错

## 4. 排查典型链路

排查白屏顺序（用 mini-app `echowrUO9lbxSmY2qunM` / Taro 写的「原神计算器」做实例）：

1. **看 `Documents/dimina.log`** —— 看 `app/launch start` 到 `render/marked as ready` 是否完整  
   → 看到 `loadPageFrame exists=true`、`didFinish navigation` 表示 native 层 OK
2. **看 DOM diag 输出** —— 10s 的快照仍是 `cn:[]`/`childCount:0`
3. **看 `dimina_console.log`** —— 找 `❌ [ERROR]` 项  
   → 修复后看到：`TypeError: e.Taro.setTabBarStyle is not a function`
4. **定位**：mini-app 调用了 Dimina 未实现的 wx API（这里是 `setTabBarStyle`），异常导致 React/Taro setup 早退，service 给 render 发的首屏数据是空 `{root:{cn:[]}}`
5. **修复**：增加缺失 API 的 native handler + wx polyfill（参见 `TabBarAPI.swift` 和 `DMPApp.loadBundle` 中的 polyfill 段）

## 5. 未实现 API 的处理建议

发现 mini-app 用 Dimina 没实现的 wx API 时，处理顺序：

1. 在 `Container/Api/UI/`（或合适的子目录）新建 `XxxAPI.swift`，继承 `DMPContainerApi`，用 `@BridgeMethod` 注册方法
2. 在 `DMPContainerApi.create()` 里把 API 实例化加进去（`_ = XxxAPI()`）—— **没注册就是 dead code**
3. 在 `DMPApp.loadBundle()` 注入 wx polyfill：`wx.xxx = function(opts) { DiminaServiceBridge.invoke({type:'xxx', body:opts, bridgeId:opts.bridgeId}); ... }`
4. logic.js 加载后再补一次 `Taro[m] = wx[m]`（防 Taro 静态拷贝时机问题）

## 6. 已知坑

- **`DMPContainerApi.create()` 不会自动发现 @BridgeMethod 标注的类**。曾经的 `NavigationBarAPI` 因为没被实例化，`setNavigationBarTitle` / `setNavigationBarColor` 全是 dead code。新增 API 必须显式在 `create()` 里加一行。
- **`os_log --info --debug` 必填**，否则 info/debug 日志被默默丢弃。
- **Pods/Dimina 文件夹是静态拷贝快照**，不参与编译。源文件在 `dimina/iOS/dimina/DiminaKit/`。新增文件后需要 `pod install` 让 `Pods.xcodeproj` 注册引用。
