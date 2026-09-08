//
//  DMPPageLifecycle.swift
//  dimina
//
//  Created by Lehem on 2025/4/27.
//

public class DMPPageLifecycle {
    var app: DMPApp
    
    init(app: DMPApp) {
        self.app = app
    }
        
    @MainActor
    public func onShow(webviewId: Int) {
        app.applyScreenShotProtectionForCurrentPage()
        let msg = DMPMap([
            "type": "pageShow",
            "body": [
                "bridgeId": webviewId
            ]
        ])
        DMPChannelProxy.containerToService(msg: msg, app: app)
    }
    
    public func onHide(webviewId: Int) {
        if webviewId <= 0 {
            return
        }
        
        let msg = DMPMap([
            "type": "pageHide",
            "body": [
                "bridgeId": webviewId
            ]
        ])
        DMPChannelProxy.containerToService(msg: msg, app: app)
    }
    
    public func onUnload(webviewId: Int) {
        let msg = DMPMap([
            "type": "pageUnload",
            "body": [
                "bridgeId": webviewId
            ]
        ])
        DMPChannelProxy.containerToService(msg: msg, app: app)
    }
    
}
