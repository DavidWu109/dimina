import { addWindowResizeListener, removeWindowResizeListener } from './events'

/**
 * 监听窗口尺寸变化事件
 * https://developers.weixin.qq.com/miniprogram/dev/api/ui/window/wx.onWindowResize.html
 */
export function onWindowResize(listener) {
	addWindowResizeListener(listener)
}

/**
 * 取消监听窗口尺寸变化事件
 * https://developers.weixin.qq.com/miniprogram/dev/api/ui/window/wx.offWindowResize.html
 */
export function offWindowResize(listener) {
	removeWindowResizeListener(listener)
}
