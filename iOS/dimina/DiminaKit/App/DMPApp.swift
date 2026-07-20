//
//  DMPApp.swift
//  dimina
//
//  Created by Lehem on 2025/4/17.
//

import Foundation

public class DMPApp {
    private var appId: String
    private var appIndex: Int
    private var appConfig: DMPAppConfig?

    private lazy var navigator: DMPNavigator? = DMPNavigator(app: self)

    private var bundleAppConfig: DMPBundleAppConfig?
    private var currentLaunchConfig: DMPLaunchConfig?

    public var render: DMPRender?
    public var service: DMPService?
    public var container: DMPContainer?
    public var containerApi: DMPContainerApi?

    private(set) var pageCapsuleProvider: DMPPageCapsuleProvider?

    private var isLaunching = false
    private var isDestroyed = false
    /// Host API registrations belong to the app instance, not to one container
    /// launch. `appWithConfig` may return the same app when a mini app is opened
    /// again, while every launch rebuilds `containerApi`.
    private var apiRegistrations: [(DMPApiHandler, DMPApiConflictPolicy)] = []

    public init(appConfig: DMPAppConfig, appIndex: Int) {
        self.appConfig = appConfig
        self.appId = appConfig.appId
        self.appIndex = appIndex
    }

    @MainActor
    public func launch(launchConfig: DMPLaunchConfig) async {
        guard !isLaunching else {
            DMPLogger.debug("launch skipped: app is already launching")
            return
        }

        isLaunching = true
        defer {
            isLaunching = false
        }

        DMPLog.resetFile()
        DMPLog.app.info("launch start, appId=\(appId), versionCode=\(appConfig?.versionCode ?? -1)")
        // 注册 versionCode 映射，供 DiminaURLSchemeHandler 使用
        if let vc = appConfig?.versionCode {
            DiminaURLSchemeHandler.appVersionMap[appId] = vc
        }
        showLoading()

        await Self.prepareBundleResources(appId: appId)

        initBundle()
        DMPLog.app.info("initBundle done")

        initContainer()
        DMPLog.app.info("initContainer done")

        await initService()
        DMPLog.app.info("initService done")

        await loadBundle()
        DMPLog.app.info("loadBundle done, bundleAppConfig=\(bundleAppConfig != nil ? "ok" : "nil")")

        if let manifestUrl = appConfig?.updateManifestUrl,
           !manifestUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Task {
                await DMPRemoteUpdateManager.shared.checkForUpdate(app: self, manifestUrl: manifestUrl)
            }
        } else {
            await notifyUpdateStatus(event: "noupdate")
        }

        initRender()
        DMPLog.app.info("initRender done")

        await openPage(launchConfig: launchConfig)
        DMPLog.app.info("openPage done")

        hideLoading()
        DMPLog.app.info("launch finished")
    }

    public func initService() async {
        service = DMPService(app: self)
    }

    public func getNavigator() -> DMPNavigator? {
        return navigator
    }

    public func getService() -> DMPService? {
        return service
    }

    public func getAppConfig() -> DMPAppConfig? {
        return appConfig
    }

    public func getCurrentWebViewId() -> Int {
        return navigator?.getTopPageRecord()?.webViewId ?? -1
    }

    public func getAppId() -> String {
        return appId
    }

    public func getAppIndex() -> Int {
        return appIndex
    }

    /// Registers host APIs for this mini app.
    ///
    /// Register APIs before calling `launch`. Registrations are scoped to this
    /// `DMPApp` and are released when the app is destroyed.
    @discardableResult
    public func registerApi(
        _ handler: DMPApiHandler,
        conflictPolicy: DMPApiConflictPolicy = .reject
    ) -> Bool {
        guard !isLaunching, !isDestroyed else {
            DMPLogger.debug("registerApi skipped: APIs must be registered before launch")
            return false
        }
        guard !handler.apiNames.isEmpty else {
            DMPLogger.debug("registerApi skipped: handler has no API names")
            return false
        }

        // Reopening the same mini app normally registers the same API groups
        // again before launch. Replace that group instead of growing duplicate
        // registrations indefinitely; disjoint API groups remain untouched.
        if let index = apiRegistrations.firstIndex(where: {
            $0.0.apiNames == handler.apiNames
        }) {
            apiRegistrations[index] = (handler, conflictPolicy)
        } else {
            apiRegistrations.append((handler, conflictPolicy))
        }
        return true
    }

    /// Registers a host-provided replacement for the built-in page capsule.
    ///
    /// Register the provider before calling `launch`. The provider is scoped to
    /// this `DMPApp` and is released when the app is destroyed.
    @MainActor
    @discardableResult
    public func registerPageCapsuleProvider(_ provider: DMPPageCapsuleProvider) -> Bool {
        guard !isLaunching, container == nil, !isDestroyed else {
            DMPLogger.debug(
                "registerPageCapsuleProvider skipped: provider must be registered before launch"
            )
            return false
        }
        guard pageCapsuleProvider == nil else {
            DMPLogger.debug("registerPageCapsuleProvider skipped: provider is already registered")
            return false
        }

        pageCapsuleProvider = provider
        return true
    }

    public func getBundleAppConfig() -> DMPBundleAppConfig? {
        return bundleAppConfig
    }

    public func getContainer() -> DMPContainer? {
        return container
    }

    public func initBundle() {
        DMPLog.bundle.debug("initBundle, appId=\(appId)")
        DMPSandboxManager.initBundleDirectoryForApp(appId: appId)
        DMPResourceManager.prepareSdk()
        DMPResourceManager.prepareApp(appId: appId)
        // 如果有 versionCode，也确保版本目录的结构
        if let versionCode = appConfig?.versionCode {
            DMPSandboxManager.initBundleDirectoryForApp(appId: appId + "/\(versionCode)")
        }
    }

    private static func prepareBundleResources(appId: String) async {
        await Task.detached(priority: .userInitiated) {
            DMPResourceManager.prepareSdk()
            DMPResourceManager.prepareApp(appId: appId)
            DMPSandboxManager.initBundleDirectoryForApp(appId: appId)
        }.value
    }

    public func initContainer() {
        DMPLog.app.debug("initContainer")
        DMPStorage.setupModule(appId: appId)
        DMPUIManager.shared.prepareUI()
        container = DMPContainer(app: self)
        containerApi = DMPContainerApi.create(app: self)
        if let containerApi {
            for (handler, conflictPolicy) in apiRegistrations {
                let conflicts = containerApi.registerCustomAPI(
                    handler,
                    conflictPolicy: conflictPolicy
                )
                if !conflicts.isEmpty {
                    DMPLogger.debug(
                        "registerApi rejected conflicting methods: \(conflicts.sorted())"
                    )
                }
            }
        }
    }

    @MainActor
    public func initRender() {
        DMPLog.render.debug("initRender")
        render = DMPRender(app: self)

        // Pre-warm WebView pool to improve first page opening speed
        DMPWebViewPool.shared.warmUp()
    }

    public func loadBundle() async {
        DMPLog.bundle.debug("loadBundle")
        let versionCode = appConfig?.versionCode

        // Inject custom API namespaces before loading service.js
        let namespaces = DMPAppManager.sharedInstance().apiNamespaces
        if !namespaces.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: namespaces),
           let json = String(data: data, encoding: .utf8) {
            await service?.evaluateScript("globalThis.__diminaApiNamespaces = \(json)")
        }
        // 注入已注册的 API 名字，使 service 层的 wx 对象能枚举到它们
        let registeredApis = containerApi?.getAllRegisteredMethods() ?? []
        if !registeredApis.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: registeredApis),
           let json = String(data: data, encoding: .utf8) {
            await service?.evaluateScript("globalThis.__diminaRegisteredApis = \(json)")
        }

        await service?.loadFile(path: DMPSandboxManager.sdkServicePath())

        // createInnerAudioContext 是同步 API，必须在 JS 端注册
        // Native AudioAPI Bridge 处理后续的 play/pause/stop 等异步操作
        await service?.evaluateScript("""
            (function() {
                wx.createInnerAudioContext = function() {
                    var ctx = {
                        src: '', startTime: 0, autoplay: false, loop: false,
                        obeyMuteSwitch: true, volume: 1, playbackRate: 1,
                        duration: 0, currentTime: 0, paused: true, buffered: 0,
                        _audioId: 'audio_' + Date.now() + '_' + Math.floor(Math.random() * 9999),
                        _listeners: {},
                        play: function() {
                            this.paused = false;
                            wx.innerAudioPlay({ audioId: this._audioId, src: this.src, loop: this.loop, volume: this.volume, startTime: this.startTime });
                            this._emit('play');
                        },
                        pause: function() { this.paused = true; wx.innerAudioPause({ audioId: this._audioId }); this._emit('pause'); },
                        stop: function() { this.paused = true; this.currentTime = 0; wx.innerAudioStop({ audioId: this._audioId }); this._emit('stop'); },
                        seek: function(pos) { this.currentTime = pos; wx.innerAudioSeek({ audioId: this._audioId, position: pos }); this._emit('seeked'); },
                        destroy: function() { wx.innerAudioDestroy({ audioId: this._audioId }); this._listeners = {}; },
                        onCanplay: function(cb) { this._on('canplay', cb); },
                        onPlay: function(cb) { this._on('play', cb); },
                        onPause: function(cb) { this._on('pause', cb); },
                        onStop: function(cb) { this._on('stop', cb); },
                        onEnded: function(cb) { this._on('ended', cb); },
                        onError: function(cb) { this._on('error', cb); },
                        onTimeUpdate: function(cb) { this._on('timeUpdate', cb); },
                        onWaiting: function(cb) { this._on('waiting', cb); },
                        onSeeking: function(cb) { this._on('seeking', cb); },
                        onSeeked: function(cb) { this._on('seeked', cb); },
                        offCanplay: function(cb) { this._off('canplay', cb); },
                        offPlay: function(cb) { this._off('play', cb); },
                        offPause: function(cb) { this._off('pause', cb); },
                        offStop: function(cb) { this._off('stop', cb); },
                        offEnded: function(cb) { this._off('ended', cb); },
                        offError: function(cb) { this._off('error', cb); },
                        offTimeUpdate: function(cb) { this._off('timeUpdate', cb); },
                        offWaiting: function(cb) { this._off('waiting', cb); },
                        offSeeking: function(cb) { this._off('seeking', cb); },
                        offSeeked: function(cb) { this._off('seeked', cb); },
                        _on: function(evt, cb) { if (!this._listeners[evt]) this._listeners[evt] = []; if (typeof cb === 'function') this._listeners[evt].push(cb); },
                        _off: function(evt, cb) { if (!this._listeners[evt]) return; if (cb) this._listeners[evt] = this._listeners[evt].filter(function(f){return f!==cb;}); else this._listeners[evt] = []; },
                        _emit: function(evt, data) { (this._listeners[evt]||[]).forEach(function(cb){ try{cb(data);}catch(e){} }); }
                    };
                    return ctx;
                };
            })();

            // TabBar APIs polyfill: 桥接到 native TabBarAPI（避免 Taro mini-app 调用未实现方法抛 TypeError 导致白屏）
            (function() {
                function bridge(name) {
                    return function(opts) {
                        opts = opts || {};
                        try {
                            DiminaServiceBridge.invoke({
                                type: name,
                                body: opts,
                                bridgeId: opts.bridgeId
                            });
                        } catch (e) {}
                        // Taro/wx callback 约定：同步触发 success/complete
                        try {
                            var res = { errMsg: name + ':ok' };
                            if (typeof opts.success === 'function') opts.success(res);
                            if (typeof opts.complete === 'function') opts.complete(res);
                        } catch (e) {}
                    };
                }
                var methods = [
                    'setTabBarStyle', 'setTabBarItem',
                    'showTabBar', 'hideTabBar',
                    'setTabBarBadge', 'removeTabBarBadge',
                    'showTabBarRedDot', 'hideTabBarRedDot'
                ];
                methods.forEach(function(m) {
                    if (typeof wx[m] !== 'function') wx[m] = bridge(m);
                });
            })();

            // getFileSystemManager 同步 API
            wx.getFileSystemManager = function() {
                return {
                    readFile: function(opts) { wx.fsReadFile(opts); },
                    readFileSync: function(filePath, encoding) { return ''; },
                    writeFile: function(opts) { wx.fsWriteFile(opts); },
                    writeFileSync: function(filePath, data, encoding) {},
                    mkdir: function(opts) { wx.fsMkdir(opts); },
                    mkdirSync: function(dirPath, recursive) {},
                    rmdir: function(opts) { wx.fsRmdir(opts); },
                    rmdirSync: function(dirPath, recursive) {},
                    unlink: function(opts) { wx.fsUnlink(opts); },
                    unlinkSync: function(filePath) {},
                    stat: function(opts) { wx.fsStat(opts); },
                    statSync: function(path, recursive) { return {}; },
                    access: function(opts) { wx.fsAccess(opts); },
                    accessSync: function(path) {},
                    readdir: function(opts) { wx.fsReaddir(opts); },
                    readdirSync: function(dirPath) { return []; },
                    copyFile: function(opts) { wx.fsCopyFile(opts); },
                    copyFileSync: function(srcPath, destPath) {},
                    rename: function(opts) { wx.fsRename(opts); },
                    renameSync: function(oldPath, newPath) {},
                    appendFile: function(opts) { if (opts.success) opts.success(); },
                    appendFileSync: function() {},
                    saveFile: function(opts) { if (opts.success) opts.success({savedFilePath: opts.tempFilePath}); },
                    saveFileSync: function(tempFilePath) { return tempFilePath; },
                    removeSavedFile: function(opts) { wx.fsUnlink(opts); },
                    getSavedFileList: function(opts) { if (opts.success) opts.success({fileList: []}); },
                    getFileInfo: function(opts) { wx.fsStat(opts); },
                };
            };
        """)

        await service?.loadFile(path: DMPSandboxManager.appServicePath(appId: appId, versionCode: versionCode))

        // mini-app 的 Taro 模块（modDefine('/taro', ...)）有自己一套 API 白名单，不自动代理 wx。
        // 通过 modRequire('/taro') 拿到模块 exports，给 Taro 对象注入缺失方法（来源：wx）。
        //
        // 实测要补的方法（每条都有具体业务问题报告）：
        // - tabBar 8 个（避免 Taro mini-app 调 setTabBarStyle 等抛 TypeError）
        // - showModal: 一键登录拿到 code 后 Taro.showModal 弹 alert 没显示 → 是 Taro 这边没桥
        //   实测 method=login + method=setClipboardData 都 callback OK 但没有 method=showModal
        // - showToast / hideToast / showLoading / hideLoading: Taro 常用 UI 反馈类，同源问题
        // - getAppBaseInfo / getWindowInfo: 业务 onLaunch 时报 TypeError，被 try/catch 吞但日志噪音大
        await service?.evaluateScript("""
            (function() {
                try {
                    console.log('[DEBUG][dimina] Taro polyfill: entry');
                    if (typeof modRequire !== 'function') {
                        console.error('[DEBUG][dimina] Taro polyfill: modRequire is not a function');
                        return;
                    }
                    var taroMod = modRequire('/taro');
                    if (!taroMod) {
                        console.error('[DEBUG][dimina] Taro polyfill: modRequire(/taro) returned null');
                        return;
                    }
                    if (!taroMod.Taro) {
                        console.error('[DEBUG][dimina] Taro polyfill: taroMod has no .Taro export, keys=', Object.keys(taroMod));
                        return;
                    }
                    var Taro = taroMod.Taro;
                    var methods = [
                        // tabBar
                        'setTabBarStyle', 'setTabBarItem',
                        'showTabBar', 'hideTabBar',
                        'setTabBarBadge', 'removeTabBarBadge',
                        'showTabBarRedDot', 'hideTabBarRedDot',
                        // UI feedback / dialogs
                        'showModal', 'showActionSheet',
                        'showToast', 'hideToast',
                        'showLoading', 'hideLoading',
                        // env / device info（mini-app onLaunch 常用）
                        'getAppBaseInfo', 'getWindowInfo', 'getSystemInfoSync', 'getSystemInfo'
                    ];
                    var patched = [];
                    var skippedHasTaro = [];
                    var skippedNoWx = [];
                    methods.forEach(function(m) {
                        var hasTaro = typeof Taro[m] === 'function';
                        var hasWx = typeof wx[m] === 'function';
                        if (!hasTaro && hasWx) {
                            Taro[m] = wx[m];
                            patched.push(m);
                        } else if (hasTaro) {
                            skippedHasTaro.push(m);
                        } else {
                            skippedNoWx.push(m);
                        }
                    });
                    console.log('[DEBUG][dimina] Taro polyfill summary: patched=[' + patched.join(',') + '] skippedAlreadyOnTaro=[' + skippedHasTaro.join(',') + '] skippedMissingOnWx=[' + skippedNoWx.join(',') + ']');

                    // Taro 自己的 showModal 实现实测不走 native bridge（dimina_console 永远看不到 method=showModal）。
                    // mini-app 一键登录拿到 code 后 alert 不弹就是这个原因。强制用 wx.showModal 覆盖。
                    // 用 list 集中维护，以后发现别的 Taro API 也 broken 时直接加进来。
                    var forceOverride = ['showModal', 'showActionSheet', 'showToast', 'hideToast', 'showLoading', 'hideLoading'];
                    var overridden = [];
                    var failedOverride = [];
                    forceOverride.forEach(function(m) {
                        if (typeof wx[m] === 'function') {
                            try {
                                var desc = Object.getOwnPropertyDescriptor(Taro, m);
                                // 优先尝试普通赋值
                                Taro[m] = wx[m];
                                // 验证：如果 Taro[m] 没被改成 wx[m]，说明属性是 readonly / 有 setter / 冻结
                                if (Taro[m] !== wx[m]) {
                                    // 强制 redefine（如果可以的话）
                                    try {
                                        Object.defineProperty(Taro, m, {
                                            value: wx[m],
                                            writable: true,
                                            configurable: true,
                                            enumerable: true
                                        });
                                    } catch (e2) {}
                                    if (Taro[m] !== wx[m]) {
                                        failedOverride.push(m + '(desc=' + JSON.stringify(desc) + ')');
                                        return;
                                    }
                                }
                                overridden.push(m);
                            } catch (e) {
                                failedOverride.push(m + '(throw: ' + e.message + ')');
                            }
                        }
                    });
                    if (overridden.length) {
                        console.log('[DEBUG][dimina] Taro polyfill force-overridden OK: ' + overridden.join(','));
                    }
                    if (failedOverride.length) {
                        console.error('[DEBUG][dimina] Taro polyfill force-override FAILED: ' + failedOverride.join(' | '));
                    }

                    // 诊断：包装 wx.showModal，记录每次调用（判断业务到底有没有触发到 wx 这一层）
                    var origShowModal = wx.showModal;
                    wx.showModal = function(opts) {
                        console.log('[DEBUG][dimina] wx.showModal CALLED title=' + (opts && opts.title) + ' contentLen=' + (opts && opts.content ? String(opts.content).length : 0));
                        return origShowModal(opts);
                    };
                    // 重新指向新的 wrapped wx.showModal（之前 force-override 拿到的是旧引用）
                    Taro.showModal = wx.showModal;

                    // 1 秒后验证 Taro.showModal 引用是否被外力篡改
                    setTimeout(function() {
                        var stillEqual = (Taro.showModal === wx.showModal);
                        console.log('[DEBUG][dimina] Taro polyfill 1s post-check: Taro.showModal===wx.showModal=' + stillEqual);
                    }, 1000);
                } catch (e) {
                    console.error('[DEBUG][dimina] Taro polyfill failed:', e && e.message ? e.message : e);
                }
            })();
        """)

        let path = DMPSandboxManager.appConfigPath(appId: appId, versionCode: versionCode)
        let config = DMPFileUtil.readJsonFile(at: path)
        DMPLog.bundle.debug("loaded app-config.json at \(path)")
        if config == "{}" {
            DMPLog.bundle.warn("app-config.json is nil at \(path)")
        }
        self.bundleAppConfig = DMPBundleAppConfig.fromJsonString(json: config)
    }

    func notifyUpdateStatus(event: String) async {
        let message = DMPMap([
            "type": "onUpdateStatusChange",
            "body": [
                "event": event,
            ],
        ])
        await service?.postMessage(data: message)
    }

    @MainActor
    public func openPage(launchConfig: DMPLaunchConfig) async {
        // 优先使用传入的 path，没传时 fallback 到 app-config.json 的第一个页面
        let requestedPath = (launchConfig.appEntryPath ?? "").isEmpty
            ? (self.bundleAppConfig?.entryPagePath ?? "")
            : launchConfig.appEntryPath ?? ""
        let route = DMPPageRoute(path: requestedPath)
        let query = route.merging(query: launchConfig.query)
        DMPLog.app.info("openPage entryPath=\(route.pagePath) (launchConfig=\(launchConfig.appEntryPath ?? "nil"), bundleConfig=\(self.bundleAppConfig?.entryPagePath ?? "nil"))")

        // Cache the resolved launch config for applyUpdate relaunch
        var resolvedConfig = launchConfig
        resolvedConfig.appEntryPath = route.pagePath
        resolvedConfig.query = query
        currentLaunchConfig = resolvedConfig

        await navigator?.launch(to: route.pagePath, query: query)
    }

    @MainActor
    public func applyUpdate() async {
        let launchConfig = currentLaunchConfig
        service?.destroy()
        await initService()
        await loadBundle()

        let entryPath = launchConfig?.appEntryPath ?? bundleAppConfig?.entryPagePath ?? ""
        await navigator?.relaunch(to: entryPath, query: launchConfig?.query, animated: false)
    }

    /// 注册第三方扩展 bridge 模块。
    ///
    /// 小程序通过 `wx.extBridge` / `wx.extOnBridge` / `wx.extOffBridge` 与 native 模块通信，
    /// 宿主通过此方法（或 `DMPAppManager.registerExtModule`）向框架注册对应处理器。
    ///
    /// - Parameters:
    ///   - moduleName: 模块名，与小程序侧 `module` 参数一致
    ///   - handler:    处理器，详见 `DMPExtModuleHandler`
    public func registerExtModule(_ moduleName: String, handler: @escaping DMPExtModuleHandler) {
        container?.registerExtModule(moduleName, handler: handler)
    }

    public func showLoading() {
        DMPLog.app.debug("showLoading")
    }

    public func hideLoading() {
        DMPLog.app.debug("hideLoading")
    }

    public func destroy() {
        guard !isDestroyed else {
            return
        }
        isDestroyed = true
        DMPLog.app.info("destroy, appId=\(appId)")

        BluetoothAPIManager.shared.clearApp(appId)
        LocalNetworkAPIManager.shared.clearApp(appId)

        // Clear WebView cache pool (execute on main thread)
        Task { @MainActor in
            DMPWebViewPool.shared.clearPool()
        }

        let serviceToDestroy = service
        let containerToDestroy = container

        service = nil
        container = nil
        containerApi = nil
        apiRegistrations.removeAll()
        render = nil
        pageCapsuleProvider = nil

        DMPAppManager.sharedInstance().removeApp(appId: appId)

        // 清理第三方扩展的持续订阅，防止内存泄漏
        containerToDestroy?.clearExtSubscriptions()

        // Storage is a global singleton. Tear it down before another app initializes it.
        DMPStorage.teardownModule(appId: appId)

        DispatchQueue.global(qos: .utility).async {
            serviceToDestroy?.destroy()
        }
    }
}
