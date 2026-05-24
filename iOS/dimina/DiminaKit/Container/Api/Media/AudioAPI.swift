//
//  AudioAPI.swift
//  dimina
//
//  Created by David on 2026/3/30.
//

import Foundation
import AVFoundation

/**
 * Media - InnerAudioContext API
 * https://developers.weixin.qq.com/miniprogram/dev/api/media/audio/wx.createInnerAudioContext.html
 *
 * createInnerAudioContext 是同步 API，直接返回一个音频上下文对象。
 * 后续的 play/pause/stop/seek 等操作通过 Bridge 异步调用。
 */
public class AudioAPI: DMPContainerApi {

    /// 音频播放器实例池，key 为 audioId
    private static var players: [String: AVAudioPlayer] = [:]

    public override init(app: DMPApp? = nil) {
        super.init(app: app)

        register("createInnerAudioContext", handler: createInnerAudioContext)
        register("innerAudioPlay", handler: innerAudioPlay)
        register("innerAudioPause", handler: innerAudioPause)
        register("innerAudioStop", handler: innerAudioStop)
        register("innerAudioSeek", handler: innerAudioSeek)
        register("innerAudioDestroy", handler: innerAudioDestroy)
    }

    private func createInnerAudioContext(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let audioId = "audio_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 1000...9999))"
        let result = DMPMap()
        result.set("audioId", audioId)
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return nil
    }

    private func innerAudioPlay(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let params = param.getMap()
        let audioId = params.getString(key: "audioId") ?? ""
        let src = params.getString(key: "src") ?? ""
        let loop = params.get("loop") as? Bool ?? false
        let volume = params.get("volume") as? Double ?? 1.0
        let startTime = params.get("startTime") as? Double ?? 0

        guard !src.isEmpty else {
            DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "innerAudioPlay:fail src is empty")
            return nil
        }

        DispatchQueue.global().async {
            var audioData: Data?

            if src.hasPrefix("http://") || src.hasPrefix("https://") {
                audioData = try? Data(contentsOf: URL(string: src)!)
            } else {
                audioData = try? Data(contentsOf: URL(fileURLWithPath: src))
            }

            DispatchQueue.main.async {
                guard let data = audioData, let player = try? AVAudioPlayer(data: data) else {
                    DMPContainerApi.invokeFailure(callback: callback, param: nil, errMsg: "innerAudioPlay:fail cannot load audio")
                    return
                }

                player.numberOfLoops = loop ? -1 : 0
                player.volume = Float(volume)
                player.currentTime = startTime

                AudioAPI.players[audioId] = player
                player.play()

                DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["audioId": audioId]))
            }
        }

        return nil
    }

    private func innerAudioPause(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        AudioAPI.players[audioId]?.pause()
        DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["audioId": audioId]))
        return nil
    }

    private func innerAudioStop(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        AudioAPI.players[audioId]?.stop()
        AudioAPI.players[audioId]?.currentTime = 0
        DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["audioId": audioId]))
        return nil
    }

    private func innerAudioSeek(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        let position = param.getMap().get("position") as? Double ?? 0
        AudioAPI.players[audioId]?.currentTime = position
        DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["audioId": audioId]))
        return nil
    }

    private func innerAudioDestroy(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        AudioAPI.players[audioId]?.stop()
        AudioAPI.players.removeValue(forKey: audioId)
        DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["audioId": audioId]))
        return nil
    }
}
