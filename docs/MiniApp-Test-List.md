# Dimina 小程序测试清单

> 在模拟器或真机上通过 deeplink 打开：`https://qiandao.com/miniapp?appId=<ID>&type=<env>`
>
> 或在千岛 App 内搜索/访问对应小程序。

## 线上小程序（type=prod）

| 名称 | appId | 入口路径 | 说明 |
|---|---|---|---|
| 能力广场 | `echoEMMycBPxZZUCGp06` | `pages/index/index` | API 兼容性测试平台，显示已适配/总 API 数量，按分类（授权、基础、设备、媒体、网络等）逐项测试 |

**测试 URL：**
```
https://qiandao.com/miniapp?appId=echoEMMycBPxZZUCGp06&type=prod
```

## 内置 Demo 小程序（离线 bundle）

这些小程序打包在 `dimina/iOS/dimina/Resources/JsApp.bundle/` 中，无需网络即可运行。

| 名称 | appId | 入口路径 | 说明 |
|---|---|---|---|
| 小程序官方组件展示 | `wxe5f52902cf4de896` | `page/tabBar/component/index` | 微信官方组件 demo，覆盖 view/scroll-view/swiper/text 等基础组件 |
| WeUI for 小程序 | `wx92269e3b2f304afc` | `example/index` | WeUI 组件库 demo，覆盖 form/actionsheet/dialog/toast 等 |
| 胡腾小程序 | `echoBuGD9jxFdD2DrMlk` | `pages/index/index` | 内部测试小程序 |
| taroecho222 | `wx92269e3b2f302c` | `example/index` | Taro 框架测试用例 |

**测试 URL（以官方组件展示为例）：**
```
https://qiandao.com/miniapp?appId=wxe5f52902cf4de896
```

## 前端 Example 小程序（需本地编译）

在 `dimina/fe/example/` 目录下，需要先编译再通过本地调试模式加载。

| 目录 | 说明 |
|---|---|
| `fe/example/base` | 基础 API 测试（mini-app lifecycle、storage、request 等） |
| `fe/example/weui` | WeUI 组件集成测试 |
| `fe/example/vant` | Vant Weapp 组件集成测试 |
| `fe/example/taro-todo` | Taro 框架 TODO 应用 |
| `fe/example/subpackages` | 分包加载测试 |

**本地调试启动：**
```bash
# 1. 编译 example
cd dimina/fe/example/base && npm install && npm run build

# 2. 启动 dev server
cd dimina/fe && npm run dev

# 3. 在 App 中通过 ws 参数连接
# AppLauncherViewController(appId: "dev", ws: "ws://localhost:9090")
```

## 业务小程序（需登录千岛 App）

以下小程序通过千岛 App 业务入口访问，需要登录账号。

| 名称 | 入口 | 说明 |
|---|---|---|
| 商家助手 | 我的 → 商家助手 | 商家管理后台小程序 |
| 兴趣士多 | 奇货 → 商品卡片 | 团购/商品详情小程序 |
| 千岛剧本杀 | 剧本杀频道 → 分享 | 剧本杀拼团分享小程序 |

## 验证清单

每次 Dimina 引擎变更后，建议按以下顺序验证：

### 1. 基础能力（能力广场）
- [ ] 小程序启动不白屏
- [ ] `bridgeHandlerMap` 包含所有注册的 API key
- [ ] wx.login → setClipboardData → showModal 链路通

### 2. 路由（官方组件展示 / WeUI）
- [ ] wx.navigateTo / navigateBack 正常
- [ ] wx.redirectTo 正常
- [ ] wx.reLaunch 正常
- [ ] wx.switchTab 正常（如有 tabBar 页面）

### 3. UI 交互（能力广场）
- [ ] showToast / showLoading / hideToast 正常
- [ ] showModal 弹窗 confirm/cancel 正常
- [ ] showActionSheet 正常

### 4. 存储 & 网络
- [ ] wx.setStorage / getStorage / removeStorage 正常
- [ ] wx.request GET/POST 正常
- [ ] wx.downloadFile 正常

### 5. 媒体
- [ ] wx.chooseImage 相册/拍照正常
- [ ] wx.previewImage 正常
- [ ] InnerAudioContext play/pause/stop 正常

### 6. TabBar（如有 tabBar 小程序）
- [ ] tab 切换不白屏
- [ ] setTabBarStyle 样式更新正常
- [ ] show/hideTabBar 正常
