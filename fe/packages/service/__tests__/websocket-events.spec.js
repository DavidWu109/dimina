import { beforeEach, describe, expect, it, vi } from 'vitest'

vi.mock('@/api/common', () => ({
	invokeAPI: vi.fn(),
}))

import { callback } from '@dimina/common'
import { invokeAPI } from '@/api/common'
import { connectSocket, offSocketMessage, onSocketMessage } from '../src/api/core/network/websocket/index.js'

describe('websocket event callback registry', () => {
	beforeEach(() => {
		vi.mocked(invokeAPI).mockReset()
		callback.remove()
	})

	it('removes a SocketTask listener by its bridge callback id', () => {
		const task = connectSocket({ url: 'wss://example.com' })
		const listener = vi.fn()
		task.onMessage(listener)

		const onParams = vi.mocked(invokeAPI).mock.calls[1][1]
		expect(onParams.callback).toEqual(expect.any(String))

		task.offMessage(listener)

		expect(invokeAPI).toHaveBeenLastCalledWith('offSocketMessage', {
			socketId: task.socketId,
			callback: onParams.callback,
			keep: true,
		})
		callback.invoke(onParams.callback, { data: 'late message' })
		expect(listener).not.toHaveBeenCalled()
	})

	it('keeps registrations for the same listener isolated by event', () => {
		const task = connectSocket({ url: 'wss://example.com' })
		const listener = vi.fn()
		task.onOpen(listener)
		task.onMessage(listener)

		const openId = vi.mocked(invokeAPI).mock.calls[1][1].callback
		const messageId = vi.mocked(invokeAPI).mock.calls[2][1].callback
		expect(openId).not.toBe(messageId)

		task.offOpen(listener)
		callback.invoke(messageId, { data: 'message' })
		expect(listener).toHaveBeenCalledWith({ data: 'message' })
	})

	it('supports removing global socket listeners', () => {
		const listener = vi.fn()
		onSocketMessage(listener)
		const callbackId = vi.mocked(invokeAPI).mock.calls[0][1].callback

		offSocketMessage(listener)

		expect(invokeAPI).toHaveBeenLastCalledWith('offSocketMessage', {
			callback: callbackId,
			keep: true,
		})
	})
})
