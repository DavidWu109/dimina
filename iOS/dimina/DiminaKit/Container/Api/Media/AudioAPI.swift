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

    private static let CREATE_INNER_AUDIO_CONTEXT = "createInnerAudioContext"
    private static let INNER_AUDIO_PLAY = "innerAudioPlay"
    private static let INNER_AUDIO_PAUSE = "innerAudioPause"
    private static let INNER_AUDIO_STOP = "innerAudioStop"
    private static let INNER_AUDIO_SEEK = "innerAudioSeek"
    private static let INNER_AUDIO_DESTROY = "innerAudioDestroy"
    private static let INNER_AUDIO_SET_SRC = "innerAudioSetSrc"

    /// 音频播放器实例池，key 为 audioId
    private static var players: [String: AVAudioPlayer] = [:]

    // MARK: - createInnerAudioContext（同步，返回 audioId）

    @BridgeMethod(CREATE_INNER_AUDIO_CONTEXT)
    var createInnerAudioContext: DMPBridgeMethodHandler = { param, env, callback in
        let audioId = "audio_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 1000...9999))"
        let result = DMPMap()
        result.set("audioId", audioId)
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return nil
    }

    // MARK: - play

    @BridgeMethod(INNER_AUDIO_PLAY)
    var innerAudioPlay: DMPBridgeMethodHandler = { param, env, callback in
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

        // 异步下载/加载音频
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

    // MARK: - pause

    @BridgeMethod(INNER_AUDIO_PAUSE)
    var innerAudioPause: DMPBridgeMethodHandler = { param, env, callback in
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        AudioAPI.players[audioId]?.pause()
        DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["audioId": audioId]))
        return nil
    }

    // MARK: - stop

    @BridgeMethod(INNER_AUDIO_STOP)
    var innerAudioStop: DMPBridgeMethodHandler = { param, env, callback in
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        AudioAPI.players[audioId]?.stop()
        AudioAPI.players[audioId]?.currentTime = 0
        DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["audioId": audioId]))
        return nil
    }

    // MARK: - seek

    @BridgeMethod(INNER_AUDIO_SEEK)
    var innerAudioSeek: DMPBridgeMethodHandler = { param, env, callback in
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        let position = param.getMap().get("position") as? Double ?? 0
        AudioAPI.players[audioId]?.currentTime = position
        DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["audioId": audioId]))
        return nil
    }

    // MARK: - destroy

    @BridgeMethod(INNER_AUDIO_DESTROY)
    var innerAudioDestroy: DMPBridgeMethodHandler = { param, env, callback in
        let audioId = param.getMap().getString(key: "audioId") ?? ""
        AudioAPI.players[audioId]?.stop()
        AudioAPI.players.removeValue(forKey: audioId)
        DMPContainerApi.invokeSuccess(callback: callback, param: DMPMap(["audioId": audioId]))
        return nil
    }
}
