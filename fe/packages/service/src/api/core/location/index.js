import { callback, isFunction } from '@dimina/common'
import { invokeAPI } from '@/api/common'

const locationChangeListeners = new Map()

/**
 * 获取当前的地理位置、速度。
 * https://developers.weixin.qq.com/miniprogram/dev/api/location/wx.getLocation.html
 */
export function getLocation(opts) {
	return invokeAPI('getLocation', opts)
}

/**
 * 获取模糊地理位置。
 * https://developers.weixin.qq.com/miniprogram/dev/api/location/wx.getFuzzyLocation.html
 */
export function getFuzzyLocation(opts) {
	return invokeAPI('getFuzzyLocation', opts)
}

/**
 * 开启小程序进入前台时接收位置消息。
 * https://developers.weixin.qq.com/miniprogram/dev/api/location/wx.startLocationUpdate.html
 */
export function startLocationUpdate(opts) {
	return invokeAPI('startLocationUpdate', opts)
}

/**
 * 使用内置地图查看位置
 * https://developers.weixin.qq.com/miniprogram/dev/api/location/wx.openLocation.html
 */
export function openLocation(opts) {
	return invokeAPI('openLocation', opts)
}

/**
 * 关闭监听实时位置变化，前后台都停止消息接收
 * https://developers.weixin.qq.com/miniprogram/dev/api/location/wx.stopLocationUpdate.html
 */
export function stopLocationUpdate(opts) {
	return invokeAPI('stopLocationUpdate', opts)
}

/**
 * 监听实时地理位置变化事件
 * https://developers.weixin.qq.com/miniprogram/dev/api/location/wx.onLocationChange.html
 */
export function onLocationChange(listener) {
	if (!isFunction(listener) || locationChangeListeners.has(listener)) {
		return
	}
	const id = callback.store(value => listener(value), true)
	locationChangeListeners.set(listener, id)
	return invokeAPI('onLocationChange', {
		callback: id,
		keep: true,
	})
}

/**
 * 移除实时地理位置变化事件的监听函数
 * https://developers.weixin.qq.com/miniprogram/dev/api/location/wx.offLocationChange.html
 * @param {*} listener onLocationChange 传入的监听函数。不传此参数则移除所有监听函数。
 */
export function offLocationChange(listener) {
	if (isFunction(listener)) {
		const id = locationChangeListeners.get(listener)
		if (!id) {
			return
		}
		locationChangeListeners.delete(listener)
		callback.remove(id)
		return invokeAPI('offLocationChange', {
			callback: id,
			keep: true,
		})
	}

	for (const id of locationChangeListeners.values()) {
		callback.remove(id)
	}
	locationChangeListeners.clear()
	return invokeAPI('offLocationChange', { keep: true })
}
