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
    
    public var render: DMPRender?
    public var service: DMPService?
    public var container: DMPContainer?
    public var containerApi: DMPContainerApi?

    /// Host app provides overlay views (e.g., capsule button) for mini-program pages
    public var pageOverlayProvider: DMPPageOverlayProvider?

    /// 小程序启动完成后的回调（用于引擎自检等）
    public var onLaunchComplete: (() -> Void)?
    
    public init(appConfig: DMPAppConfig, appIndex: Int) {
        self.appConfig = appConfig
        self.appId = appConfig.appId
        self.appIndex = appIndex
    }

    private func debugLog(_ msg: String) {
        print(msg)
        let logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("dimina_launch.log")
        let line = "\(Date()) \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    @MainActor
    public func launch(launchConfig: DMPLaunchConfig) async {
        // 清空旧日志
        let logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("dimina_launch.log")
        try? FileManager.default.removeItem(at: logFile)

        debugLog("🔵 [DMPApp] launch 开始, appId=\(appId), versionCode=\(appConfig?.versionCode ?? -1)")
        // 注册 versionCode 映射，供 DiminaURLSchemeHandler 使用
        if let vc = appConfig?.versionCode {
            DiminaURLSchemeHandler.appVersionMap[appId] = vc
        }
        showLoading()
        initBundle()
        debugLog("🔵 [DMPApp] initBundle 完成")

        initContainer()
        debugLog("🔵 [DMPApp] initContainer 完成")

        await initService()
        debugLog("🔵 [DMPApp] initService 完成")

        await loadBundle()
        debugLog("🔵 [DMPApp] loadBundle 完成, bundleAppConfig=\(bundleAppConfig != nil ? "有" : "nil")")

        initRender()
        debugLog("🔵 [DMPApp] initRender 完成")

        await openPage(launchConfig: launchConfig)
        debugLog("🔵 [DMPApp] openPage 完成")

        hideLoading()
        debugLog("🔵 [DMPApp] launch 全部完成")
        onLaunchComplete?()
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
        
    public func getBundleAppConfig() -> DMPBundleAppConfig? {
        return bundleAppConfig
    }
    
    public func getContainer() -> DMPContainer? {
        return container
    }
    
    public func initBundle() {
        print("initBundle")
        DMPSandboxManager.initBundleDirectoryForApp(appId: appId)
        DMPResourceManager.prepareSdk()
        DMPResourceManager.prepareApp(appId: appId)
        // 如果有 versionCode，也确保版本目录的结构
        if let versionCode = appConfig?.versionCode {
            DMPSandboxManager.initBundleDirectoryForApp(appId: appId + "/\(versionCode)")
        }
    }

    public func initContainer() {
        print("initContainer")
        DMPStorage.setupModule(appId: appId)        
        DMPUIManager.shared.prepareUI()
        container = DMPContainer(app: self)
        containerApi = DMPContainerApi.create(app: self)
    }

    @MainActor
    public func initRender() {
        print("initRender")
        render = DMPRender(app: self)
        
        // Pre-warm WebView pool to improve first page opening speed
        DMPWebViewPool.shared.warmUp()
    }

    public func loadBundle() async {
        print("loadBundle")
        let versionCode = appConfig?.versionCode
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

        let path = DMPSandboxManager.appConfigPath(appId: appId, versionCode: versionCode)
        let config = DMPFileUtil.readJsonFile(at: path)
        print("config: \(path) \(String(describing: config))")
        self.bundleAppConfig = DMPBundleAppConfig.fromJsonString(json: config)
    }

    @MainActor
    public func openPage(launchConfig: DMPLaunchConfig) async {
        print("openPage")
        // 优先使用传入的 path，没传时 fallback 到 app-config.json 的第一个页面
        let entryPath = (launchConfig.appEntryPath ?? "").isEmpty
            ? (self.bundleAppConfig?.entryPagePath ?? "")
            : launchConfig.appEntryPath ?? ""
        print("openPage entryPath=\(entryPath) (from launchConfig=\(launchConfig.appEntryPath ?? "nil"), bundleConfig=\(self.bundleAppConfig?.entryPagePath ?? "nil"))")
        await navigator?.launch(to: entryPath, query: launchConfig.query)
    }

    public func showLoading() {
        print("showLoading")
    }

    public func hideLoading() {
        print("hideLoading")
    } 

    public func destroy() {
        print("app destroy")
        
        // Clear WebView cache pool (execute on main thread)
        Task { @MainActor in
            DMPWebViewPool.shared.clearPool()
        }
        
        DMPStorage.teardownModule()
        
        DMPAppManager.sharedInstance().removeApp(appId: appId)
        service?.destroy()
    }
}
