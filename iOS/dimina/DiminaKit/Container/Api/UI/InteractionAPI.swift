//
//  InteractionAPI.swift
//  dimina
//
//  Created by DosLin on 2025/5/10.
//

import Foundation
import UIKit

public class InteractionAPI: DMPContainerApi {

    public override init(app: DMPApp? = nil) {
        super.init(app: app)
        register("showToast", handler: showToast)
        register("showModal", handler: showModal)
        register("showLoading", handler: showLoading)
        register("hideToast", handler: hideToast)
        register("hideLoading", handler: hideLoading)
        register("showActionSheet", handler: showActionSheet)
    }

    private func showToast(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let param = param.getMap()
        guard let title = param.get("title") as? String else {
            let errorMap = DMPMap()
            errorMap.set("errMsg", "showToast:fail title is required")
            DMPContainerApi.invokeFailure(callback: callback, param: errorMap, errMsg: "title is required")
            return nil
        }

        let icon = param.get("icon") as? String ?? "success"
        let duration = param.get("duration") as? Int ?? 1500
        let mask = param.get("mask") as? Bool ?? false

        DispatchQueue.main.async {
            var toastType: ToastType = .success
            switch icon {
            case "success":
                toastType = .success
            case "error":
                toastType = .error
            case "loading":
                toastType = .loading
            case "none":
                toastType = .none
            default:
                toastType = .success
            }

            ToastManager.shared.showToast(title: title, type: toastType, duration: duration, mask: mask)
        }

        let result = DMPMap()
        result.set("errMsg", "showToast:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return nil
    }

    private func showModal(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let param = param.getMap()
        let title = param.get("title") as? String ?? ""
        let content = param.get("content") as? String ?? ""
        DMPLog.bridge.info("showModal native handler title=\(title) contentLen=\(content.count)")
        let showCancel = param.get("showCancel") as? Bool ?? true
        let cancelText = param.get("cancelText") as? String ?? "取消"
        let cancelColor = param.get("cancelColor") as? String ?? "#000000"
        let confirmText = param.get("confirmText") as? String ?? "确定"
        let confirmColor = param.get("confirmColor") as? String ?? "#576B95"

        DispatchQueue.main.async {
            ModalManager.shared.showModal(
                title: title,
                content: content,
                showCancel: showCancel,
                cancelText: cancelText,
                cancelColor: cancelColor,
                confirmText: confirmText,
                confirmColor: confirmColor
            ) { isConfirmed in
                let result = DMPMap()
                result.set("confirm", isConfirmed)
                result.set("cancel", !isConfirmed)
                result.set("errMsg", "showModal:ok")
                DMPContainerApi.invokeSuccess(callback: callback, param: result)
            }
        }
        return nil
    }

    private func showLoading(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let param = param.getMap()
        guard let title = param.get("title") as? String else {
            let errorMap = DMPMap()
            errorMap.set("errMsg", "showLoading:fail title is required")
            DMPContainerApi.invokeFailure(callback: callback, param: errorMap, errMsg: "title is required")
            return nil
        }

        let mask = param.get("mask") as? Bool ?? false

        DispatchQueue.main.async {
            ToastManager.shared.showToast(title: title, type: .loading, duration: 0, mask: mask)
        }

        let result = DMPMap()
        result.set("errMsg", "showLoading:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return nil
    }

    private func hideToast(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        DispatchQueue.main.async {
            ToastManager.shared.hideToast()
        }

        let result = DMPMap()
        result.set("errMsg", "hideToast:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return nil
    }

    private func hideLoading(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        DispatchQueue.main.async {
            ToastManager.shared.hideToast()
        }

        let result = DMPMap()
        result.set("errMsg", "hideLoading:ok")
        DMPContainerApi.invokeSuccess(callback: callback, param: result)
        return nil
    }

    private func showActionSheet(_ param: DMPBridgeParam, _ env: DMPBridgeEnv, _ callback: DMPBridgeCallback?) -> Any? {
        let param = param.getMap()
        let itemColor = param.get("itemColor") as? String ?? "#000000"

        var itemList: [String] = []
        if let items = param.get("itemList") as? [String] {
            itemList = items
        } else if let items = param.get("itemList") as? [Any] {
            itemList = items.compactMap { $0 as? String }
        }

        if itemList.isEmpty {
            let errorMap = DMPMap()
            errorMap.set("errMsg", "showActionSheet:fail itemList is empty")
            DMPContainerApi.invokeFailure(callback: callback, param: errorMap, errMsg: "itemList is empty")
            return nil
        }

        DispatchQueue.main.async {
            ActionSheetManager.shared.showActionSheet(
                itemList: itemList,
                itemColor: itemColor
            ) { selectedIndex in
                let result = DMPMap()
                result.set("tapIndex", selectedIndex)
                result.set("errMsg", "showActionSheet:ok")
                DMPContainerApi.invokeSuccess(callback: callback, param: result)
            }
        }
        return nil
    }
}
