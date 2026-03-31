# DMPResourceManager 使用说明

## 概述

`DMPResourceManager` 现在支持两种资源获取方式：
1. **本地 Bundle**: 从应用包内的 `.bundle` 文件获取资源
2. **远程下载**: 从远程服务器下载资源并缓存到本地

## 主要特性

- ✅ 自动选择本地或远程资源
- ✅ 支持远程资源下载和缓存
- ✅ 版本比较和更新检查
- ✅ 可配置的下载参数
- ✅ 错误处理和重试机制
- ✅ 资源验证和完整性检查

## 基本使用

### 1. 获取 JSApp Bundle

```swift
// 自动选择本地或远程Bundle
if let bundle = DMPResourceManager.jsappBundle {
    print("Bundle路径: \(bundle.bundlePath)")
} else {
    print("无法获取Bundle")
}
```

### 2. 获取可用的 Bundle（优先本地）

```swift
if let bundle = DMPResourceManager.getAvailableJsAppBundle() {
    print("可用Bundle: \(bundle.bundlePath)")
}
```

## 配置远程下载

### 1. 基本配置

```swift
// 设置远程下载URL
DMPResourceConfig.shared.remoteJsAppBundleURL = "https://your-server.com/jsapp-bundle.zip"

// 启用自动下载
DMPResourceConfig.shared.enableAutoDownload = true

// 设置下载超时时间（秒）
DMPResourceConfig.shared.downloadTimeout = 60.0

// 设置最大重试次数
DMPResourceConfig.shared.maxRetryCount = 3
```

### 2. 配置验证

```swift
let errors = DMPResourceConfig.shared.validateConfig()
if errors.isEmpty {
    print("配置验证通过")
} else {
    for error in errors {
        print("配置错误: \(error)")
    }
}
```

## 高级功能

### 1. 检查远程更新

```swift
DMPResourceManager.checkRemoteBundleUpdate { needsUpdate in
    if needsUpdate {
        print("远程Bundle有更新")
    } else {
        print("远程Bundle无需更新")
    }
}
```

### 2. 强制刷新远程Bundle

```swift
DMPResourceManager.refreshRemoteBundle { success in
    if success {
        print("远程Bundle刷新成功")
    } else {
        print("远程Bundle刷新失败")
    }
}
```

## 注意事项

1. **网络权限**: 确保应用有网络访问权限
2. **存储空间**: 远程下载的资源会占用本地存储空间
3. **版本管理**: 建议实现版本比较逻辑，避免重复下载
4. **错误处理**: 始终提供备用方案，确保应用稳定性
5. **配置安全**: 生产环境中应该使用HTTPS URL和适当的认证
