# 页面方向与窗口尺寸事件协议

状态：Proposed  
适用范围：Dimina 前端运行时、组件运行时、编译产物及各平台容器的协议边界  
不适用范围：Android、iOS、HarmonyOS、Web 的具体旋转实现

本文是该能力进入 Dimina 官方源前的协议依据。公共 JS 行为或内部跨层消息发生变化时，应先更新本文，再修改实现。

## 1. 背景

Dimina 已声明 `page-meta` 的 `page-orientation` 属性，也已有 Page 和 Component 的部分 resize 生命周期，但当前链路并不完整：

- `page-orientation` 只完成属性声明，尚未驱动当前页面方向。
- `wx.onWindowResize` 依赖一个未形成完整闭环的容器调用，且缺少 `wx.offWindowResize`。
- render runtime 尚未根据真实 viewport 变化发送 `pageResize`。
- Page、Component 与 `wx.onWindowResize` 的回调参数结构尚未统一。

本方案只统一 JS 接口、生命周期语义和跨层消息，不要求各移动端共享同一套宿主实现。移动端可以独立演进，只要最终向 JS 层提供相同的可观察行为。

## 2. 目标与非目标

### 2.1 目标

1. 对齐微信小程序的页面方向声明和窗口尺寸事件。
2. 统一 Page、Component、`page-meta` 和 `wx` API 的尺寸 Schema。
3. 只在 viewport 真实变化后发送 resize，不根据“方向请求”推测尺寸。
4. 定义 render、service 和容器之间最小且平台无关的协议。
5. 保证旧小程序未使用相关能力时行为不变。

### 2.2 非目标

- 不新增 `wx.setDeviceOrientation`、`qd.setDeviceOrientation` 或其他公开命令式转屏 API。
- 不规定 iOS `UIWindowScene`、Android `Activity`、HarmonyOS `UIAbility` 等系统 API 的调用方式。
- 不统一各移动端宿主回调、Delegate、Provider 或异步函数的具体签名。
- 不把方向字符串或设备方向字段附加到公开 resize 事件。
- 本期不定义 iPad resizable、大屏自由窗口和桌面端窗口管理策略。

## 3. 公共 JS 协议

### 3.1 页面静态配置

`pageOrientation` 可配置在 `app.json.window` 或页面 JSON 中：

```json
{
  "pageOrientation": "auto"
}
```

支持值：

| 值 | 语义 |
| --- | --- |
| `portrait` | 页面固定竖屏 |
| `landscape` | 页面固定横屏 |
| `auto` | 页面方向跟随设备或窗口变化 |

静态配置解析优先级为：页面 JSON > `app.json.window` > `portrait`。缺失或非法值回退为 `portrait`，不得把非法值透传给平台容器。

方向最终值的完整优先级为：当前可见页面的 `page-meta.page-orientation` 运行时覆盖 > 页面 JSON > `app.json.window` > `portrait`。隐藏页面保存的运行时值不得越过当前可见页面参与决策。

### 3.2 `page-meta`

```xml
<page-meta
  page-orientation="{{pageOrientation}}"
  bindresize="onPageMetaResize"
/>
```

`page-orientation` 支持 `portrait`、`landscape` 和 `auto`，只覆盖当前 `page-meta` 所属页面的静态配置：

- mount：建立当前页面的动态覆盖。
- 属性变化：更新该页面的动态覆盖。
- 属性为空、非法或组件 unmount：移除动态覆盖并恢复该页面静态配置。
- 隐藏页面可以保存自己的覆盖值，但不得改变当前可见页面方向。
- 页面重新显示、返回或 tab 切换时，按该页面当前动态值或静态值重新应用。

`bindresize` 只在 viewport 实际变化后触发：

```js
function onPageMetaResize(event) {
  const { windowWidth, windowHeight } = event.detail.size
}
```

### 3.3 Page 与 Component 生命周期

Page 和 Component 接收相同的 `ResizeResult`：

```ts
interface ResizeResult {
  size: {
    windowWidth: number
    windowHeight: number
  }
}
```

```js
Page({
  onResize(res) {
    const { windowWidth, windowHeight } = res.size
  },
})

Component({
  pageLifetimes: {
    resize(res) {
      const { windowWidth, windowHeight } = res.size
    },
  },
})
```

不得继续向 Page 或 Component 传递扁平的 `{ windowWidth, windowHeight }`。

### 3.4 方向相关系统信息 API

本能力对开发者交付的系统信息 API 如下。拆分 API 是后续新增代码的首选；`getSystemInfo*` 只为兼容既有小程序保留，不再扩展新字段。

| 状态 | API 与签名 | 返回内容 | 方向变化后的约束 |
| --- | --- | --- | --- |
| 推荐 | `wx.getWindowInfo(): WindowInfo` | `pixelRatio`、`screenWidth`、`screenHeight`、`windowWidth`、`windowHeight`、`statusBarHeight`、`safeArea`、`screenTop` | 每次调用返回当前窗口与 viewport 的实际尺寸，不得缓存首次启动值 |
| 推荐 | `wx.getDeviceInfo(): DeviceInfo` | `abi`、`benchmarkLevel`、`brand`、`model`、`platform`、`system` | 设备固有信息不因页面方向变化而伪造或重写 |
| 推荐 | `wx.getAppBaseInfo(): AppBaseInfo` | `SDKVersion`、`enableDebug`、`host`、`language`、`version`、`theme`、`fontSizeScaleFactor`、`fontSizeSetting` | App 基础信息与窗口尺寸解耦 |
| 兼容、停止维护 | `wx.getSystemInfo(options?): Promise<SystemInfo>` | 上述信息的兼容聚合结果 | 已有尺寸字段必须反映调用时的当前窗口，不再新增字段 |
| 兼容、停止维护 | `wx.getSystemInfoAsync(options?): Promise<SystemInfo> \| void` | `getSystemInfo` 的异步/回调兼容入口 | 与 `getSystemInfo` 返回同一时刻的尺寸语义 |
| 兼容、停止维护 | `wx.getSystemInfoSync(): SystemInfo` | `getSystemInfo` 的同步兼容入口 | 与 `getWindowInfo` 的重叠字段在同一时刻必须一致 |

`screenWidth`、`screenHeight`、`windowWidth` 和 `windowHeight` 是数值字段。业务判断当前布局应优先比较当前返回的宽高，不依赖 iOS 物理设备方向枚举。横竖屏切换完成前可以读到旧尺寸；viewport 发生真实变化并触发 resize 后，再次调用必须返回新尺寸。

### 3.5 `wx.onWindowResize` 与 `wx.offWindowResize`

```ts
wx.onWindowResize(listener: (res: ResizeResult) => void): void
wx.offWindowResize(listener?: (res: ResizeResult) => void): void
```

行为约束：

- 仅函数类型可以注册。
- 同一函数重复注册时只保留一个监听。
- `offWindowResize(listener)` 只移除指定函数。
- `offWindowResize()` 清空全部窗口尺寸监听。
- 回调参数与 Page、Component 使用同一 `ResizeResult`。
- 不包含 `deviceOrientation` 或 Dimina 私有字段。
- 一个监听函数抛错不得阻止其他监听和生命周期继续执行。

## 4. 事件来源与时序

resize 的唯一事实来源是 render viewport 的真实尺寸变化。

1. 页面 render runtime mount 时记录初始 `window.innerWidth` 和 `window.innerHeight`，不发送初始 resize。
2. 浏览器触发 `window.resize` 后，在下一帧读取最终尺寸。
3. 同一帧内的多次 resize 合并为一次。
4. 宽高与上次已发送值完全相同时不发送事件。
5. render 向 service 发送一次内部 `pageResize` 消息。
6. service 使用同一份尺寸快照通知当前页面、已 attached 的组件和 `wx` 监听者。
7. `page-meta.bindresize` 由其所在 render 页面监听真实 `window.resize`，事件 detail 使用同一 Schema。

方向请求成功但 viewport 没有变化时不得发送 resize；方向请求失败或平台不支持时也不得发送虚假 resize。

Page、Component、`page-meta` 和 `wx` 监听之间不承诺跨类型的先后顺序。业务代码不得依赖某一种回调总是先于另一种回调，只能依赖它们在同一次尺寸变化中收到一致的宽高。

## 5. 内部跨层协议

内部 `pageResize` 消息保持最小结构：

```ts
interface PageResizeMessage {
  type: 'pageResize'
  target: 'service'
  body: {
    bridgeId: string
    size: {
      windowWidth: number
      windowHeight: number
    }
  }
}
```

service 收到消息后再包装公共 `ResizeResult`。内部消息不得包含平台名称、系统方向枚举或宿主实现状态。

动态 `page-meta` 可以通过框架内部 Bridge 把最终页面方向请求交给当前平台容器。该 Bridge：

- 不是公开 `wx` API，不进入开发者可调用列表。
- 必须携带页面身份，使容器或框架能够拒绝隐藏页面影响当前页面。
- 空值表示移除动态覆盖并恢复静态配置。
- 平台不支持时应安全降级，不得导致页面启动失败。

内部 Bridge 的名称和原生函数签名属于实现细节，不构成跨平台公共 API。

## 6. 移动端适配边界

Android、iOS 和 HarmonyOS 可以采用不同实现，只需满足以下结果契约：

1. 能消费当前可见页面解析后的 `portrait`、`landscape` 或 `auto`。
2. 页面切换、返回和 tab 切换后，最终可见页面的方向配置生效。
3. 小程序关闭、启动失败或取消时，不遗留影响宿主后续页面的方向状态。
4. 平台实际改变 WebView viewport 后，浏览器产生真实 `window.resize`。
5. 平台拒绝、系统锁定或暂不支持时安全降级，不伪造成功后的尺寸事件。

具体线程模型、错误回调、异步等待和宿主状态保存方式由各平台自行设计并在平台文档中说明，但系统信息 API 的公开签名、字段拆分和尺寸语义必须遵守 3.4。

### 6.1 iOS 导航控件与安全区域

iOS 页面方向变化后，原生导航控件必须跟随当前 `UIViewController` 的 safe area 重新布局，不能缓存竖屏窗口的绝对边距：

- 右侧胶囊尺寸保持 `87 × 32pt`，其 trailing 等于当前 safe-area trailing 向内 `10pt`；
- 左侧返回或 Home 控件的 leading 等于当前 safe-area leading 向内 `4pt`；
- 标题右边界不得超过胶囊 leading 向左 `13pt`，避免横屏安全区把胶囊向内推后与标题重叠；
- `getMenuButtonBoundingClientRect` 使用窗口坐标系，并返回与原生胶囊最终布局一致的坐标；其右边距为 `safeAreaInsets.right + 10pt`；
- 正反两个横屏方向必须分别验证。刘海或灵动岛位于右侧时，胶囊不得进入系统安全区域；位于左侧时，左侧导航控件同样不得进入系统安全区域。

布局必须通过 safe-area 约束随旋转自动更新，不依赖首次创建页面时读取到的 `windowWidth` 或固定横屏方向。

## 7. 兼容性

- 未使用 `pageOrientation`、`page-meta.page-orientation` 或 resize API 的小程序不受影响。
- `wx.getWindowInfo`、`wx.getDeviceInfo` 和 `wx.getAppBaseInfo` 是推荐入口；新字段只进入对应拆分 API。
- `wx.getSystemInfo`、`wx.getSystemInfoAsync` 和 `wx.getSystemInfoSync` 保留现有兼容能力，但标记为停止维护，不作为新能力扩展入口。
- `wx.onWindowResize` 从不完整的容器回调改为 service 内事件订阅，公开签名不变。
- `wx.offWindowResize` 是新增 API。
- Page 和 Component resize 参数从扁平尺寸对象校准为微信兼容的 `ResizeResult`，属于行为修正；应在 Changelog 中明确记录。
- 平台能力可以分批实现，能力表必须逐平台标记，业务侧仍应使用 `wx.canIUse()` 保护可选能力。

## 8. 验收用例

| ID | 场景 | 预期 |
| --- | --- | --- |
| JS-ORI-001 | 页面 JSON 与 app window 同时配置 | 页面配置优先 |
| JS-ORI-002 | 配置缺失或非法 | 回退 `portrait` |
| JS-ORI-003 | `page-meta` mount、更新、unmount | 动态覆盖、更新、恢复静态配置 |
| JS-ORI-004 | 隐藏页面更新动态方向 | 不影响当前可见页面 |
| JS-ORI-005 | 页面返回与 tab 切换 | 当前可见页面配置重新生效 |
| JS-RSZ-001 | viewport 宽高真实变化 | 四类 JS 入口收到相同 `ResizeResult` |
| JS-RSZ-002 | 同一帧连续 resize | 合并为一次最终尺寸事件 |
| JS-RSZ-003 | resize 后宽高未变化 | 不发送重复事件 |
| JS-RSZ-004 | 重复注册同一监听 | 只调用一次 |
| JS-RSZ-005 | 移除指定监听或全部监听 | 仅剩余监听继续接收 |
| JS-RSZ-006 | 某监听抛出异常 | 其他监听和生命周期仍执行 |
| JS-RSZ-007 | 平台拒绝方向请求 | 不发送虚假 resize，页面继续可用 |
| JS-SYS-001 | 竖屏进入横屏并等待 viewport resize | `getWindowInfo` 的宽高更新，且 `windowWidth > windowHeight` |
| JS-SYS-002 | 横屏进入竖屏并等待 viewport resize | `getWindowInfo` 的宽高更新，且 `windowHeight > windowWidth` |
| JS-SYS-003 | 同一时刻调用三个兼容 `getSystemInfo*` | 重叠字段与 `getWindowInfo` 一致 |
| JS-SYS-004 | 调用三个推荐拆分 API | 字段只落在所属信息域，不依赖兼容聚合接口新增字段 |
| IOS-ORI-001 | 刘海或灵动岛位于横屏左侧 | 左侧导航控件位于 safe area 内，胶囊距右侧 safe area 10pt |
| IOS-ORI-002 | 刘海或灵动岛位于横屏右侧 | 胶囊位于 safe area 内且不与标题重叠 |
| IOS-ORI-003 | `getMenuButtonBoundingClientRect` | 返回值与原生胶囊最终 frame 一致 |

前端测试至少覆盖 components、render 和 service 三个包。移动端测试由各平台分别提供，但必须使用上述 JS 用例验证最终行为。

## 9. 上游交付拆分

建议在一个聚焦该能力的 Pull Request 中使用多个 commit：

1. 定义并测试统一 `ResizeResult` 与 `on/offWindowResize`。
2. 由 render 产生真实、合并且去重的 `pageResize`。
3. 实现 `page-meta.page-orientation` 动态协议和页面隔离。
4. 增加至少一个平台适配；其他平台按相同 JS 协议后续跟进。
5. 更新 API Reference、兼容性清单、Changelog 和共享 JS SDK 产物。

平台适配可以分支或分 MR 演进，但不得修改本协议定义的公开 JS 签名和事件 Schema。

## 10. 参考资料

- [微信小程序：响应显示区域变化](https://developers.weixin.qq.com/miniprogram/dev/framework/view/resizable.html)
- [微信小程序：page-meta](https://developers.weixin.qq.com/miniprogram/dev/component/page-meta.html)
- [微信小程序：wx.onWindowResize](https://developers.weixin.qq.com/miniprogram/dev/api/ui/window/wx.onWindowResize.html)
- [微信小程序：wx.offWindowResize](https://developers.weixin.qq.com/miniprogram/dev/api/ui/window/wx.offWindowResize.html)
