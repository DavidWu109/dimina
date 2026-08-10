import { afterEach, describe, expect, it, vi } from 'vitest'
import hostEnv from '../src/core/host-env.js'
import {
	getAppBaseInfo,
	getDeviceInfo,
	getSystemInfoSync,
	getWindowInfo,
	offThemeChange,
	onThemeChange,
} from '../src/api/core/base/system/index.js'
import {
	offMenuButtonBoundingClientRectWeightChange,
	onMenuButtonBoundingClientRectWeightChange,
} from '../src/api/core/ui/menu/index.js'

describe('system info api', () => {
	afterEach(() => {
		offMenuButtonBoundingClientRectWeightChange()
		offThemeChange()
		hostEnv.reset()
	})

	it('should prefer host env sync info for system-related apis', () => {
		const systemInfo = {
			// window info fields
			statusBarHeight: 20,
			windowWidth: 375,
			windowHeight: 667,
			screenWidth: 375,
			screenHeight: 667,
			pixelRatio: 2,
			safeArea: { top: 20, bottom: 667, left: 0, right: 375, width: 375, height: 647 },
			// app base info fields
			SDKVersion: '3.0.0',
			enableDebug: false,
			host: { appId: 'test' },
			language: 'zh_CN',
			version: '1.0.0',
			theme: 'light',
			fontSizeScaleFactor: 1,
			fontSizeSetting: 16,
			// device info fields
			abi: 'arm64',
			benchmarkLevel: -1,
			brand: 'test',
			model: 'test',
			platform: 'devtools',
			system: 'web',
		}

		hostEnv.init({ systemInfo })

		expect(getWindowInfo()).toEqual({
			pixelRatio: 2,
			screenWidth: 375,
			screenHeight: 667,
			windowWidth: 375,
			windowHeight: 667,
			statusBarHeight: 20,
			safeArea: { top: 20, bottom: 667, left: 0, right: 375, width: 375, height: 647 },
		})
		expect(getSystemInfoSync()).toBe(systemInfo)
		expect(getAppBaseInfo()).toEqual({
			SDKVersion: '3.0.0',
			enableDebug: false,
			host: { appId: 'test' },
			language: 'zh_CN',
			version: '1.0.0',
			theme: 'light',
			fontSizeScaleFactor: 1,
			fontSizeSetting: 16,
		})
		expect(getDeviceInfo()).toEqual({
			abi: 'arm64',
			benchmarkLevel: -1,
			brand: 'test',
			model: 'test',
			platform: 'devtools',
			system: 'web',
		})
	})

	it('updates host geometry and notifies menu rect listeners', () => {
		const listener = vi.fn()
		const menuRect = { top: 52, right: 365, bottom: 84, left: 278, width: 87, height: 32 }
		hostEnv.init({ menuRect: null })
		onMenuButtonBoundingClientRectWeightChange(listener)

		hostEnv.update({ menuRect })

		expect(hostEnv.getMenuRect()).toBe(menuRect)
		expect(listener).toHaveBeenCalledWith(menuRect)
	})

	it('reads the latest window geometry after an orientation update', () => {
		const portraitInfo = {
			brand: 'Apple',
			windowWidth: 390,
			windowHeight: 844,
			screenWidth: 390,
			screenHeight: 844,
			pixelRatio: 3,
			statusBarHeight: 59,
			screenTop: 59,
			safeArea: { top: 59, bottom: 810, left: 0, right: 390, width: 390, height: 751 },
		}
		const landscapeInfo = {
			...portraitInfo,
			windowWidth: 844,
			windowHeight: 390,
			screenWidth: 844,
			screenHeight: 390,
			statusBarHeight: 0,
			screenTop: 0,
			safeArea: { top: 0, bottom: 369, left: 59, right: 785, width: 726, height: 369 },
		}

		hostEnv.init({ systemInfo: portraitInfo })
		hostEnv.update({ systemInfo: landscapeInfo })

		expect(getWindowInfo()).toEqual({
			pixelRatio: 3,
			screenWidth: 844,
			screenHeight: 390,
			windowWidth: 844,
			windowHeight: 390,
			statusBarHeight: 0,
			screenTop: 0,
			safeArea: { top: 0, bottom: 369, left: 59, right: 785, width: 726, height: 369 },
		})
		expect(getSystemInfoSync()).toBe(landscapeInfo)
	})

	it('notifies theme listeners from host environment updates', () => {
		const listener = vi.fn()
		hostEnv.init({ systemInfo: { theme: 'light' } })
		onThemeChange(listener)

		hostEnv.update({ systemInfo: { theme: 'dark' } })

		expect(listener).toHaveBeenCalledWith({ theme: 'dark' })
	})
})
