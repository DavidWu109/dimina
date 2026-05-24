//
//  VibrateAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation
import UIKit
import AudioToolbox

/**
 * Device - Vibrate API
 */
public class VibrateAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("vibrateShort", handler: vibrateShort)
        register("vibrateLong", handler: vibrateLong)
    }

    private func vibrateShort(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let type = param.getMap()["type"] as? String
        let style = VibrateAPI.getVibrationType(type: type)
        VibrateAPI.vibrate(style: style)

        // Return success response
        let result = DMPMap()
        result.set("errMsg", "vibrateShort:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)

        return nil
    }

    private func vibrateLong(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        DispatchQueue.main.async {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }

        // Return success response
        let result = DMPMap()
        result.set("errMsg", "vibrateLong:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)

        return nil
    }

    // Helper method to get vibration pattern
    private static func getVibrationType(type: String?) -> UIImpactFeedbackGenerator.FeedbackStyle {
        guard let type = type else {
            // Default to heavy if no type specified
            return .heavy
        }

        switch type.lowercased() {
        case "light":
            return .light
        case "medium":
            return .medium
        default:
            // Default case (including "heavy" or any other value)
            return .heavy
        }
    }

    // Helper method to trigger vibration
    private static func vibrate(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        DispatchQueue.main.async {
            let impactGenerator = UIImpactFeedbackGenerator(style: style)
            impactGenerator.prepare()
            impactGenerator.impactOccurred()
        }
    }
}
