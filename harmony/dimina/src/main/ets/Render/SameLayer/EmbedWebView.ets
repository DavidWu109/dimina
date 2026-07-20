
import { DMPWebViewProxy } from '../../HybridContainer/DMPWebViewProxy';
import { DMPWebViewController } from '../../HybridContainer/DMPWebViewController';
import { DMPAppManager } from '../../DApp/DMPAppManager';
import { DMPMap } from '../../Utils/DMPMap';
import { DMPStringUtils } from '../../Utils/DMPStringUtils'

import { WebViewParams } from './DMPComponetParams';
import { DMPPageStyle } from '../../DPages/DMPPageStyle';
import { DMPNavigatorDelegate } from '../../Navigator/DMPNavigatorDelegate';
import { DMPNavigatorManager } from '../../Navigator/DMPNavigatorManager';
import { DMPLogger } from '../../EventTrack/DMPLogger';

//星河小程序内部嵌入的webview
@Component
export struct EmbedWebView {
  @Prop
  data: WebViewParams;
  @Prop
  parentWebViewId: number
  @Prop
  webViewId: number
  @State
  mode: CacheMode = CacheMode.Online;
  pageParams: DMPMap = new DMPMap()
  @Prop
  appIndex: number;
  private webViewProxy: DMPWebViewProxy = new DMPWebViewProxy(this.webViewId, this.appIndex);
  private webviewController =
    new DMPWebViewController(this.webViewId, DMPAppManager.sharedInstance().getApp(this.appIndex)!)

  aboutToAppear(): void {
    const render = DMPAppManager.sharedInstance().getApp(this.appIndex)?.render;
    const controller = render?.getController(this.parentWebViewId)
    if (render && controller) {
      controller.subController = this.webviewController
      render.controllerMap.set(this.webViewId, controller)
    }
  }

  aboutToDisappear(): void {
    const render = DMPAppManager.sharedInstance().getApp(this.appIndex)?.render;
    render?.controllerMap.delete(this.webViewId)
  }

  build() {
    Column() {

      Web({
        src: this.data?.attributes?.src,
        controller: this.webviewController
      })
        .fileAccess(true)
        .zoomAccess(false)
        .verticalScrollBarAccess(false)
        .domStorageAccess(true)
        .geolocationAccess(true)
        .javaScriptProxy({
          object: this.webViewProxy,
          name: "DiminaRenderBridge",
          methodList: ["invoke"],
          asyncMethodList: ["publish"],
          controller: this.webviewController
        })
        .onPageBegin(() => {
          this.webviewController.initConfig() // 设置ua
        })
        .onPageEnd(() => {
          const script = this.data.attributes?.javascript;
          const attrs = this.data.attributes?.attrs;
          const moduleId = this.data.attributes?.moduleId;

          // 给webview注入webviewId，供jssdk使用
          this.webviewController.runJavaScript(`
            window.embed_webviewId = ${this.webViewId};
            window.embed_webview_data = {
              moduleId: '${moduleId}',
              attrs: ${JSON.stringify(attrs)},
              parentWebViewId: ${this.parentWebViewId}
            };
          `);

          if (script != null) {
            this.webviewController.runJavaScript(script)
          }
        })
        .onTitleReceive((title) => {
          if (title.title) {
            const navigator: DMPNavigatorManager =
              DMPAppManager.sharedInstance().getApp(this.appIndex)?.navigatorManager!
            if (navigator) {
              const originNavStyle = navigator.getPageRecordById(this.parentWebViewId)?.pageStyle?.navStyle
              if (originNavStyle) {
                const navStyle = DMPMap.createFromDMPMap(originNavStyle)
                navStyle.set('navigationBarTitleText', DMPStringUtils.truncateString(title.title))
                navigator.getPageRecordById(this.parentWebViewId)!.pageStyle =
                  new DMPPageStyle(navStyle ?? new DMPMap(), this.appIndex)
              }
            }
          }
        })
        .cacheMode(this.mode)
        .onErrorReceive((event) => {
          if (event != null) {
            DMPLogger.e('', "webview load error:" + event.error.getErrorInfo().toString())
          }
        })

    }.width('100%').height('100%')
  }

  goBack() {
    const navigator: DMPNavigatorDelegate | undefined =
      DMPAppManager.sharedInstance().getApp(this.appIndex)?.navigatorManager?.getCurNavigator()
    navigator && navigator.pop()
  }
}
