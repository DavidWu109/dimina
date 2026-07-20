import { describe, expect, it, vi } from 'vitest'
import { MiniApp } from '../src/pages/miniApp/miniApp'

function createElement() {
	const element = {
		classList: {
			add: vi.fn(),
			remove: vi.fn(),
		},
		addEventListener: vi.fn((_type, handler) => {
			handler({ propertyName: 'transform' })
		}),
		removeEventListener: vi.fn(),
		style: {},
		parentNode: {
			removeChild: vi.fn(),
		},
	}
	return element
}

function createBridge(pagePath) {
	return {
		opts: { pagePath },
		destroy: vi.fn(),
		start: vi.fn(),
		pageShow: vi.fn(),
		pageHide: vi.fn(),
		webview: {
			el: createElement(),
		},
	}
}

function createApp() {
	const app = Object.create(MiniApp.prototype)
	app.appConfig = {
		app: {},
		modules: {
			'pages/first': {},
			'pages/second': {},
		},
	}
	app.appInfo = { scene: 1001 }
	app.appId = 'test-app'
	app.bridgeList = []
	app.jscore = { postMessage: vi.fn() }
	app.tabBarBridges = new Map()
	app.webviewAnimaEnd = true
	app._isTabBarPage = vi.fn(() => false)
	app._setTabBarVisible = vi.fn()
	app._syncHash = vi.fn()
	app.updateTargetPageColorStyle = vi.fn()
	return app
}

function callbackIds(app) {
	return app.jscore.postMessage.mock.calls.map(([message]) => message.body.id)
}

describe('MiniApp navigation callbacks', () => {
	it('keeps custom tabBar inside the page without falling back to the host tabBar', () => {
		const app = createApp()
		const tabBarEl = { style: {}, textContent: 'host tabBar' }
		app.el = {
			querySelector: vi.fn(() => tabBarEl),
			style: { setProperty: vi.fn() },
		}
		app.appConfig.app.tabBar = {
			custom: true,
			list: [{ pagePath: 'pages/first', text: 'First' }],
		}
		app._renderTabBar = vi.fn()

		app._initTabBar()

		expect(app.customTabBar).toBe(true)
		expect(app.tabBarPaths).toEqual(['pages/first'])
		expect(tabBarEl.textContent).toBe('')
		expect(tabBarEl.style.display).toBe('none')
		expect(app.tabBarHeight).toBe(0)
		expect(app._renderTabBar).not.toHaveBeenCalled()
	})

	it('restores only the top page as visible', async () => {
		const app = createApp()
		const root = createBridge('pages/first')
		const middle = createBridge('pages/first')
		const top = createBridge('pages/second')
		app.bridgeList = [root]
		app.createBridge = vi.fn()
			.mockResolvedValueOnce(middle)
			.mockResolvedValueOnce(top)

		await app.restorePageStack([
			{ pagePath: 'pages/first', query: {} },
			{ pagePath: 'pages/second', query: {} },
		])

		expect(middle.start).toHaveBeenCalledWith({ visible: false })
		expect(top.start).toHaveBeenCalledWith({ visible: true })
	})

	it('resolves navigateBack with success and complete callbacks', async () => {
		const app = createApp()
		const previous = createBridge('pages/first')
		const current = createBridge('pages/second')
		app.bridgeList = [previous, current]

		await app.navigateBack({ success: 'success-id', fail: 'fail-id', complete: 'complete-id' })

		expect(callbackIds(app)).toEqual(['success-id', 'complete-id'])
		expect(app.webviewAnimaEnd).toBe(true)
		expect(current.destroy).toHaveBeenCalledTimes(1)
		expect(previous.pageShow).toHaveBeenCalledTimes(1)
	})

	it('rejects navigateBack when there is no previous page', async () => {
		const app = createApp()
		app.bridgeList = [createBridge('pages/first')]

		await app.navigateBack({ success: 'success-id', fail: 'fail-id', complete: 'complete-id' })

		expect(callbackIds(app)).toEqual(['fail-id', 'complete-id'])
	})

	it('rejects navigation while another transition is active', async () => {
		const app = createApp()
		app.webviewAnimaEnd = false

		await app.navigateTo({ url: 'pages/second', success: 'success-id', fail: 'fail-id', complete: 'complete-id' })

		expect(callbackIds(app)).toEqual(['fail-id', 'complete-id'])
	})

	it('restores the navigation lock when creating a page fails', async () => {
		const app = createApp()
		app.bridgeList = [createBridge('pages/first')]
		app.createBridge = vi.fn().mockRejectedValue(new Error('bridge failed'))

		await app.navigateTo({ url: 'pages/second', success: 'success-id', fail: 'fail-id', complete: 'complete-id' })

		expect(callbackIds(app)).toEqual(['fail-id', 'complete-id'])
		expect(app.webviewAnimaEnd).toBe(true)
	})
})
