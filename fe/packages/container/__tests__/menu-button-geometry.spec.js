import { describe, expect, it } from 'vitest'
import { MiniApp } from '../src/pages/miniApp/miniApp'

describe('MiniApp menu button geometry', () => {
	it('returns menu coordinates relative to the mini-program viewport', () => {
		const app = Object.create(MiniApp.prototype)
		const menuRect = {
			top: 82,
			right: 829,
			bottom: 119,
			left: 734,
			width: 95,
			height: 37,
			x: 734,
			y: 82,
		}
		app.el = {
			getBoundingClientRect: () => ({ left: 428 }),
			querySelector: () => ({ getBoundingClientRect: () => menuRect }),
		}
		app.parent = {
			parent: {
				root: {
					querySelector: () => ({
						getBoundingClientRect: () => ({ height: 48 }),
					}),
				},
			},
		}

		expect(app.getMenuButtonBoundingClientRect()).toEqual({
			top: 52,
			right: 401,
			bottom: 89,
			left: 306,
			width: 95,
			height: 37,
			x: 306,
			y: 52,
		})
	})
})
