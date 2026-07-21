//
//  CanvasAPI.swift
//  dimina
//

import Foundation

/**
 * UI - Canvas API
 *
 * Canvas drawing runs in the render WebView. The container persists the
 * exported data URL and returns a Dimina virtual path to the mini program.
 */
public final class CanvasAPI: DMPContainerApi {
    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("saveCanvasTempFile", handler: saveCanvasTempFile)
    }

    private func saveCanvasTempFile(
        _ param: DMPBridgeParam,
        _ env: DMPBridgeEnv,
        _ callback: DMPBridgeCallback?
    ) -> DMPAPIResult {
        let map = param.getMap()
        guard let dataURL = map.getString(key: "dataURL"), !dataURL.isEmpty else {
            return failure(callback, message: "dataURL is empty")
        }

        guard let imageData = decodeImageDataURL(dataURL) else {
            return failure(callback, message: "dataURL is invalid")
        }

        let fileExtension = normalizedFileExtension(map.getString(key: "fileType"))
        let directoryPath = DMPSandboxManager.appTmpResourceDirectoryPath(appId: env.appId)
        let fileName = "canvas_\(UUID().uuidString.lowercased()).\(fileExtension)"
        let filePath = (directoryPath as NSString).appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(
                atPath: directoryPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try imageData.write(to: URL(fileURLWithPath: filePath), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(atPath: filePath)
            return failure(callback, message: error.localizedDescription)
        }

        let result = DMPMap()
        result.set(
            "tempFilePath",
            DMPFileUtil.vPathFromSandboxPath(sandboxPath: filePath, appId: env.appId)
        )
        result.set("errMsg", "canvasToTempFilePath:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return DMPAsyncResult()
    }

    private func decodeImageDataURL(_ dataURL: String) -> Data? {
        guard let separatorIndex = dataURL.firstIndex(of: ",") else {
            return nil
        }

        let header = dataURL[..<separatorIndex].lowercased()
        guard header.hasPrefix("data:image/"), header.hasSuffix(";base64") else {
            return nil
        }

        let encodedData = String(dataURL[dataURL.index(after: separatorIndex)...])
        guard !encodedData.isEmpty else {
            return nil
        }
        return Data(base64Encoded: encodedData)
    }

    private func normalizedFileExtension(_ fileType: String?) -> String {
        switch fileType?.lowercased() {
        case "jpg", "jpeg":
            return "jpg"
        default:
            return "png"
        }
    }

    private func failure(
        _ callback: DMPBridgeCallback?,
        message: String
    ) -> DMPAPIResult {
        DMPContainerApi.invokeFailure(
            callback: callback,
            param: nil,
            errMsg: "canvasToTempFilePath:fail \(message)"
        )
        return DMPAsyncResult()
    }
}
