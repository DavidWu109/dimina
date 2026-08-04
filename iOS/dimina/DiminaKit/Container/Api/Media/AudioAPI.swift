//
//  AudioAPI.swift
//  dimina
//
//  Created by David on 2026/3/30.
//

import AVFoundation
import Foundation

private struct AudioPlaybackOptions {
    let audioId: String
    let appId: String
    let source: String
    let loop: Bool
    let volume: Double
    let startTime: Double
}

/**
 * Media - InnerAudioContext API
 * https://developers.weixin.qq.com/miniprogram/dev/api/media/audio/wx.createInnerAudioContext.html
 *
 * createInnerAudioContext 是同步 API，直接返回一个音频上下文对象。
 * 后续的 play/pause/stop/seek 等操作通过 Bridge 异步调用。
 */
public class AudioAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)

        register("createInnerAudioContext", handler: createInnerAudioContext)
        register("innerAudioPlay", handler: innerAudioPlay)
        register("innerAudioPause", handler: innerAudioPause)
        register("innerAudioStop", handler: innerAudioStop)
        register("innerAudioSeek", handler: innerAudioSeek)
        register("innerAudioDestroy", handler: innerAudioDestroy)
    }

    private func createInnerAudioContext(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let audioId = "audio_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 1000...9999))"
        let result = DMPMap()
        result.set("audioId", audioId)
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPAsyncResult()
    }

    private func innerAudioPlay(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let params = param.getMap()
        let audioId = params.getString(key: "audioId") ?? ""
        let src = params.getString(key: "src") ?? ""
        let loop = params.get("loop") as? Bool ?? false
        let volume = params.get("volume") as? Double ?? 1.0
        let startTime = params.get("startTime") as? Double ?? 0

        guard !audioId.isEmpty else {
            DMPContainerApi.invokeFailure(
                callback: callback,
                param: nil,
                errMsg: "innerAudioPlay:fail audioId is empty"
            )
            return DMPAsyncResult()
        }
        guard !src.isEmpty else {
            DMPContainerApi.invokeFailure(
                callback: callback,
                param: nil,
                errMsg: "innerAudioPlay:fail src is empty"
            )
            return DMPAsyncResult()
        }

        AudioAPIManager.shared.play(
            AudioPlaybackOptions(
                audioId: audioId,
                appId: env.appId,
                source: src,
                loop: loop,
                volume: volume,
                startTime: startTime
            ),
            callback: callback
        )

        return DMPAsyncResult()
    }

    private func innerAudioPause(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        AudioAPIManager.shared.pause(audioId: audioId, appId: env.appId, callback: callback)
        return DMPAsyncResult()
    }

    private func innerAudioStop(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        AudioAPIManager.shared.stop(audioId: audioId, appId: env.appId, callback: callback)
        return DMPAsyncResult()
    }

    private func innerAudioSeek(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        let position = param.getMap().get("position") as? Double ?? 0
        AudioAPIManager.shared.seek(
            audioId: audioId,
            appId: env.appId,
            position: position,
            callback: callback
        )
        return DMPAsyncResult()
    }

    private func innerAudioDestroy(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        AudioAPIManager.shared.destroy(audioId: audioId, appId: env.appId, callback: callback)
        return DMPAsyncResult()
    }

    static func clearApp(_ appId: String) {
        AudioAPIManager.shared.clearApp(appId)
    }
}

private final class AudioAPIManager {
    static let shared = AudioAPIManager()

    private struct Key: Hashable {
        let appId: String
        let audioId: String
    }

    private final class Entry {
        var player: AVAudioPlayer?
        var dataTask: URLSessionDataTask?

        func cancelAndStop() {
            dataTask?.cancel()
            dataTask = nil
            player?.stop()
            player = nil
        }
    }

    private var entries: [Key: Entry] = [:]

    private init() {}

    func play(_ options: AudioPlaybackOptions, callback: DMPBridgeCallback?) {
        onMain { [weak self] in
            guard let self else { return }
            let key = Key(appId: options.appId, audioId: options.audioId)
            self.entries[key]?.cancelAndStop()

            let entry = Entry()
            self.entries[key] = entry

            let completion: (Data?) -> Void = { [weak self, weak entry] data in
                self?.finishLoading(
                    data,
                    key: key,
                    entry: entry,
                    options: options,
                    callback: callback
                )
            }

            if options.source.hasPrefix("http://") || options.source.hasPrefix("https://") {
                guard let url = URL(string: options.source) else {
                    completion(nil)
                    return
                }
                let task = URLSession.shared.dataTask(with: url) { data, _, error in
                    DispatchQueue.main.async {
                        completion(error == nil ? data : nil)
                    }
                }
                entry.dataTask = task
                task.resume()
            } else {
                DispatchQueue.global(qos: .userInitiated).async {
                    let data = try? Data(contentsOf: URL(fileURLWithPath: options.source))
                    DispatchQueue.main.async {
                        completion(data)
                    }
                }
            }
        }
    }

    func pause(audioId: String, appId: String, callback: DMPBridgeCallback?) {
        onMain { [weak self] in
            if let entry = self?.entry(audioId: audioId, appId: appId) {
                entry.player?.pause()
            }
            Self.succeed(audioId: audioId, callback: callback)
        }
    }

    func stop(audioId: String, appId: String, callback: DMPBridgeCallback?) {
        onMain { [weak self] in
            if let self {
                let key = Key(appId: appId, audioId: audioId)
                self.entries.removeValue(forKey: key)?.cancelAndStop()
            }
            Self.succeed(audioId: audioId, callback: callback)
        }
    }

    func seek(
        audioId: String,
        appId: String,
        position: Double,
        callback: DMPBridgeCallback?
    ) {
        onMain { [weak self] in
            self?.entry(audioId: audioId, appId: appId)?.player?.currentTime = position
            Self.succeed(audioId: audioId, callback: callback)
        }
    }

    func destroy(audioId: String, appId: String, callback: DMPBridgeCallback?) {
        onMain { [weak self] in
            guard let self else { return }
            let key = Key(appId: appId, audioId: audioId)
            self.entries.removeValue(forKey: key)?.cancelAndStop()
            Self.succeed(audioId: audioId, callback: callback)
        }
    }

    func clearApp(_ appId: String) {
        onMain { [weak self] in
            guard let self else { return }
            let keys = self.entries.keys.filter { key in
                key.appId == appId
            }
            keys.forEach { key in
                self.entries.removeValue(forKey: key)?.cancelAndStop()
            }
        }
    }

    private func finishLoading(
        _ data: Data?,
        key: Key,
        entry: Entry?,
        options: AudioPlaybackOptions,
        callback: DMPBridgeCallback?
    ) {
        guard let entry,
              entries[key] === entry else {
            return
        }
        entry.dataTask = nil

        guard let data, let player = try? AVAudioPlayer(data: data) else {
            entries.removeValue(forKey: key)
            DMPContainerApi.invokeFailure(
                callback: callback,
                param: nil,
                errMsg: "innerAudioPlay:fail cannot load audio"
            )
            return
        }

        player.numberOfLoops = options.loop ? -1 : 0
        player.volume = Float(options.volume)
        player.currentTime = options.startTime
        entry.player = player
        player.play()
        Self.succeed(audioId: key.audioId, callback: callback)
    }

    private func entry(audioId: String, appId: String) -> Entry? {
        entries[Key(appId: appId, audioId: audioId)]
    }

    private static func succeed(audioId: String, callback: DMPBridgeCallback?) {
        DMPContainerApi.invokeSuccess(
            callback: callback,
            param: DMPMap(["audioId": audioId])
        )
    }

    private func onMain(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }
}
