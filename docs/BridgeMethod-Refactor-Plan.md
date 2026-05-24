# `@BridgeMethod` Property Wrapper 重构计划

> 把 dimina iOS 的所有 `@BridgeMethod` property wrapper 迁移到 init-register 模式。
> 反模式的元编程让 Swift 编译器多次崩溃 + 注册时机不可靠 + 阻碍上游 merge。

## 一句话目标

`@BridgeMethod("showModal") var showModal = { ... }` → `register("showModal") { ... }` 在 `init()` 里。

## 为什么要改

### 1. property wrapper 在 swiftc 里长期不稳

跨 Swift 5.x / 6.x 至少 10+ 个公开 compiler crash issue 还在开（[#65860](https://github.com/swiftlang/swift/issues/65860)、[#59294](https://github.com/apple/swift/issues/59294)、[#61223](https://github.com/apple/swift/issues/61223)、[#56668](https://github.com/apple/swift/issues/56668)、[#75577](https://github.com/swiftlang/swift/issues/75577)、[#66634](https://github.com/swiftlang/swift/issues/66634)、[#54048](https://github.com/apple/swift/issues/54048)、[#61368](https://github.com/apple/swift/issues/61368)、[#60825](https://github.com/swiftlang/swift/issues/60825) 等），跟 weak / projected value / function parameter / default closure / mutating getter 都有冲突历史。

实测我们撞到的两次：
- **2026-05-23 InteractionAPI**：实现 `BridgeMethodProtocol` 时 wrapper stored property 二次求值，第二次的空 closure 覆盖了第一次注册的真 closure。dispatch 时拿到的是空 closure，所有 showModal 调用静默失败。
- **2026-05-24 NavigationBarAPI**：merge github.com/main 后 Swift 6.2.3 swift-frontend SIGSEGV 在 `PropertyWrapperBackingPropertyTypeRequest` —— 跟 `@BridgeMethod(SET_NAVIGATION_BAR_TITLE)` 的 static let 引用 + closure default value 的组合有关。

### 2. 反模式：用 wrapper 的副作用注册全局 map

property wrapper 设计目的是"wrap 单个值的存取行为"。`@BridgeMethod` 是**利用 wrapper init 的副作用**把 closure 注册到 `DMPContainerApi.bridgeHandlerMap` 静态 map：

```swift
@propertyWrapper
public struct BridgeMethod {
    public init(wrappedValue: @escaping DMPBridgeMethodHandler, _ name: String) {
        self.name = name
        self.wrappedValue = wrappedValue
        DMPContainerApi.registerMethod(name: name, handler: wrappedValue)  // ← 副作用
    }
}
```

这跟 property wrapper 的设计预期相悖。Swift 编译器对"按预期使用"的代码 type check 容错好，对反模式的 fragility 就会暴露 —— 我们撞的两次都是这种情况。

### 3. 注册时机依赖 `_ = ClassName()` 手动实例化

`@BridgeMethod` 只在 `_ = NavigationBarAPI()` 这种 init 调用发生时才注册。`DMPContainerApi.create()` 里有一长串：

```swift
_ = RouteAPI(app: app)
_ = BaseAPI(app: app)
_ = SystemAPI(app: app)
...
_ = LoginAPI()     // 公司 fork 加的
_ = TabBarAPI()    // 公司 fork 加的
```

漏掉一行 = 整组 method 静默失效，编译器不报错。merge 上游时这些行容易丢。

### 4. Apple 自己在远离 property wrapper

- [GSoC 2025 项目专门用 declaration macros 重新实现 property wrappers](https://forums.swift.org/t/gsoc-2025-questions-and-findings-to-re-implement-property-wrappers-with-macros/78644)
- SwiftData `@Model` / `@Observable` 等新 API 全部用 macros 不用 property wrapper
- Macros 是 compile-time code gen，property wrapper 是 runtime —— Apple 明确推 macros

### 5. 阻碍上游 merge

每次 fetch + merge github.com/main 都要小心 @BridgeMethod 相关文件的 hand-merge。merge 后还可能撞到上面第 1 点的 compiler bug 阻塞 build。

## 目标设计

### 父类暴露 `register` 实例方法

```swift
// DMPContainerApi.swift
public class DMPContainerApi: NSObject {
    // 实例方法 helper，包装现有的静态 registerMethod
    public func register(_ name: String, handler: @escaping DMPBridgeMethodHandler) {
        DMPContainerApi.registerMethod(name: name, handler: handler)
    }
}
```

### 子类在 init 里 register

```swift
public class InteractionAPI: DMPContainerApi {
    public required override init(app: DMPApp? = nil) {
        super.init(app: app)

        register("showModal") { param, env, callback in
            let p = param.getMap()
            let title = p.get("title") as? String ?? ""
            // ... body 完全不变 ...
            return DMPAsyncResult()
        }

        register("showToast") { param, env, callback in
            // ...
            return DMPAsyncResult()
        }
    }
}
```

### 删除 `@propertyWrapper struct BridgeMethod`

整段 `BridgeMethod` 结构体定义 + `init(_ name:)` / `init(wrappedValue:_:)` 全删，代码量 -15 行。

## 工作量评估

预计 ~10 个 API 类 × 平均 6 个 @BridgeMethod = **~60 个迁移点**：

| API 类 | 文件 | 大概 @BridgeMethod 个数 |
|---|---|---|
| RouteAPI | Container/Api/Route/RouteAPI.swift | 5 (navigateTo/back/redirectTo/reLaunch/switchTab) |
| BaseAPI | Container/Api/Base/BaseAPI.swift | ~5 |
| SystemAPI | Container/Api/Base/SystemAPI.swift | ~10 (getSystemInfo*/getWindowInfo/getAppBaseInfo 等) |
| UpdateAPI | Container/Api/Base/UpdateAPI.swift | ~3 |
| FileSystemAPI | Container/Api/Base/FileSystemAPI.swift | ~13 (fsRead/fsWrite/fsAccess 等) |
| LoginAPI | Container/Api/Base/LoginAPI.swift | 1 |
| InteractionAPI | Container/Api/UI/InteractionAPI.swift | 6 (showModal/showToast/showLoading 等) |
| NavigationBarAPI | Container/Api/UI/NavigationBarAPI.swift | 2 |
| TabBarAPI | Container/Api/UI/TabBarAPI.swift | 8 |
| MenuAPI / ScrollAPI / NativeComponentAPI | UI/ | 各 1-3 |
| NetworkAPI | Container/Api/Network/NetworkAPI.swift | ~3 (request/upload/download) |
| StorageAPI | Container/Api/Storage/StorageAPI.swift | ~10 (get/set/remove + sync versions) |
| ImageAPI | Container/Api/Media/ImageAPI.swift | ~3 |
| AudioAPI | Container/Api/Media/AudioAPI.swift | ~7 |
| VideoAPI | Container/Api/Media/VideoAPI.swift | ~3 |
| 各 Device API (ClipboardAPI / ContactAPI / KeyboardAPI / PhoneAPI / VibrateAPI 等) | Container/Api/Device/ | 各 1-3 |

机械改造，1-2 小时一气呵成。

## 迁移步骤（按依赖顺序）

1. **在 `DMPContainerApi` 加 `register(_:handler:)` 实例方法** —— 不影响现有代码
2. **逐个 API 类**：每个文件内 `@BridgeMethod("name") var foo = { ... }` 改 `register("name") { ... }` 放进 `init()`。closure body 完全不变
3. **所有 API 类迁移完成后**：删 `@propertyWrapper struct BridgeMethod`
4. **删 `DMPContainerApi.create()` 里那一长串 `_ = ClassName()`**：换成在 each API 类的 init 里调 super 就足够。或者保留（不痛不痒）
5. **编译验证**：build 通过 + 跑 mini-app 验证所有 wx API 正常

## 验证清单

- [ ] 编译通过（不再撞 NavigationBarAPI 那个 PropertyWrapperBackingPropertyTypeRequest crash）
- [ ] mini-app 启动后 `bridgeHandlerMap` 应包含 ~80 个 key（跟当前一样）
- [ ] 一键登录 wx.login → setClipboardData → showModal 链路通
- [ ] tabBar 切换 wx.switchTab 正常
- [ ] wx.navigateTo / redirectTo / navigateBack 正常
- [ ] showToast / showLoading / showActionSheet 正常
- [ ] storage / request / file API 正常

## 如何 push 给上游

完成后给 didi/dimina 提 PR，理由：
1. 已知 compiler bug 在 property wrapper 上反复触发（附 reproduce）
2. init register 模式跟 Apple 主推方向（macros）一致
3. 对 dimina 自身没破坏性，向后兼容（外部用户调 wx API 不变）

如果上游接受 → 公司 fork merge 时不再有 hand-merge 痛点。

## 暂不做

- declaration macro 方案（`#bridgeMethod("name") { ... }`）—— 视觉效果更接近原 `@BridgeMethod` 但要建 SwiftSyntax macro target + 单独 module，工作量大。init register 已经够清晰
- Mirror-based 自动注册 —— 反射性能差 + 失去 type safety
- class function 返回 `[String: handler]` 函数表 —— 比 init register 稍 declarative 但每个 API 类内访问 self.app 不方便（要从 env 拿）

## 决策摘要

| 选项 | 工作量 | 风险 | 推荐 |
|---|---|---|---|
| **A. init register**（本文方案） | 1-2 小时 | 低 | ✅ |
| B. declaration macro | 1 天 | 中（macro infrastructure） | 后续可选 |
| C. 不重构，遇到 compiler bug 一个个 workaround | 短期 0，长期累计高 | 高 | ❌ |
| D. 给上游 PR 改 BridgeMethod 实现 | 不可控 | 高（不能短期 deliver） | 长期目标 |

走 **A**。下次 session 一开始就执行。
