import { afterEach, describe, expect, it, vi } from 'vitest'
import { offWindowResize, onWindowResize } from '../src/api/core/ui/window'
import { createWindowResizeEvent, emitWindowResize } from '../src/api/core/ui/window/events'

describe('window resize API', () => {
	afterEach(() => {
		offWindowResize()
	})

	it('delivers one resize event to every registered listener', () => {
		const first = vi.fn()
		const second = vi.fn()
		const event = createWindowResizeEvent({ windowWidth: 844, windowHeight: 390 })

		onWindowResize(first)
		onWindowResize(second)
		emitWindowResize(event)

		expect(first).toHaveBeenCalledOnce()
		expect(first).toHaveBeenCalledWith(event)
		expect(second).toHaveBeenCalledOnce()
		expect(event).toEqual({
			size: { windowWidth: 844, windowHeight: 390 },
		})
		expect(event).not.toHaveProperty('deviceOrientation')
	})

	it('deduplicates the same function and ignores non-function listeners', () => {
		const listener = vi.fn()
		onWindowResize(listener)
		onWindowResize(listener)
		onWindowResize(null)

		emitWindowResize(createWindowResizeEvent({ windowWidth: 390, windowHeight: 844 }))

		expect(listener).toHaveBeenCalledOnce()
	})

	it('supports removing one listener or all listeners', () => {
		const first = vi.fn()
		const second = vi.fn()
		onWindowResize(first)
		onWindowResize(second)

		offWindowResize(first)
		emitWindowResize({})
		expect(first).not.toHaveBeenCalled()
		expect(second).toHaveBeenCalledOnce()

		offWindowResize()
		emitWindowResize({})
		expect(second).toHaveBeenCalledOnce()
	})

	it('continues notifying listeners when one listener throws', () => {
		const error = new Error('listener failed')
		const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})
		const failing = vi.fn(() => { throw error })
		const following = vi.fn()
		onWindowResize(failing)
		onWindowResize(following)

		const event = createWindowResizeEvent({ windowWidth: 844, windowHeight: 390 })
		emitWindowResize(event)

		expect(failing).toHaveBeenCalledWith(event)
		expect(following).toHaveBeenCalledWith(event)
		expect(consoleError).toHaveBeenCalledWith('[window resize listener error]', error)
	})
})
