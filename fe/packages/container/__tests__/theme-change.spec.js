import { describe, expect, it, vi } from 'vitest'
import { MiniApp } from '../src/pages/miniApp/miniApp'

describe('MiniApp theme changes', () => {
	it('forwards host color-scheme changes to the service environment', () => {
		const listenerApi = vi.fn()
		const mediaQuery = {
			addEventListener: listenerApi,
			matches: false,
		}
		const originalMatchMedia = globalThis.matchMedia
		globalThis.matchMedia = vi.fn(() => mediaQuery)
		const app = Object.create(MiniApp.prototype)
		app.jscore = { postMessage: vi.fn() }
		app.getSystemInfoSync = vi.fn(() => ({ theme: 'light', windowWidth: 375 }))

		try {
			app._bindThemeChange()
			const handler = listenerApi.mock.calls[0][1]
			handler({ matches: true })

			expect(app.jscore.postMessage).toHaveBeenCalledWith({
				type: 'hostEnvUpdate',
				body: {
					systemInfo: { theme: 'dark', windowWidth: 375 },
				},
			})
		}
		finally {
			globalThis.matchMedia = originalMatchMedia
		}
	})
})
