import { callback } from '@dimina/common'
import { invokeAPI } from '@/api/common'

export const ARRAY_BUFFER_BASE64_KEY = '__diminaArrayBufferBase64'

const BASE64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
const BASE64_LOOKUP = Object.fromEntries([...BASE64_CHARS].map((char, index) => [char, index]))

function isArrayBuffer(value) {
	return Object.prototype.toString.call(value) === '[object ArrayBuffer]'
}

function toArrayBuffer(value) {
	if (isArrayBuffer(value)) return value
	if (value && isArrayBuffer(value.buffer)) {
		return value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength)
	}
	return null
}

function arrayBufferToBase64(buffer) {
	const bytes = new Uint8Array(buffer)
	let result = ''
	let index = 0
	for (; index + 2 < bytes.length; index += 3) {
		result += BASE64_CHARS[bytes[index] >> 2]
		result += BASE64_CHARS[((bytes[index] & 3) << 4) | (bytes[index + 1] >> 4)]
		result += BASE64_CHARS[((bytes[index + 1] & 15) << 2) | (bytes[index + 2] >> 6)]
		result += BASE64_CHARS[bytes[index + 2] & 63]
	}
	if (index < bytes.length) {
		result += BASE64_CHARS[bytes[index] >> 2]
		if (index + 1 < bytes.length) {
			result += BASE64_CHARS[((bytes[index] & 3) << 4) | (bytes[index + 1] >> 4)]
			result += `${BASE64_CHARS[(bytes[index + 1] & 15) << 2]}=`
		}
		else {
			result += `${BASE64_CHARS[(bytes[index] & 3) << 4]}==`
		}
	}
	return result
}

function base64ToArrayBuffer(base64) {
	const clean = String(base64 || '').replace(/[\r\n\s]/g, '')
	if (!clean) return new ArrayBuffer(0)

	const padding = clean.endsWith('==') ? 2 : clean.endsWith('=') ? 1 : 0
	const length = (clean.length * 3 / 4) - padding
	const bytes = new Uint8Array(length)
	let byteIndex = 0
	for (let index = 0; index < clean.length; index += 4) {
		const first = BASE64_LOOKUP[clean[index]]
		const second = BASE64_LOOKUP[clean[index + 1]]
		const third = clean[index + 2] === '=' ? 0 : BASE64_LOOKUP[clean[index + 2]]
		const fourth = clean[index + 3] === '=' ? 0 : BASE64_LOOKUP[clean[index + 3]]
		if (byteIndex < length) bytes[byteIndex++] = (first << 2) | (second >> 4)
		if (byteIndex < length) bytes[byteIndex++] = ((second & 15) << 4) | (third >> 2)
		if (byteIndex < length) bytes[byteIndex++] = ((third & 3) << 6) | fourth
	}
	return bytes.buffer
}

export function encodeSocketMessage(value) {
	const buffer = toArrayBuffer(value)
	return buffer ? { [ARRAY_BUFFER_BASE64_KEY]: arrayBufferToBase64(buffer) } : value
}

export function decodeSocketMessageResult(value) {
	if (!value || typeof value !== 'object') return value
	const encoded = value.message
	if (!encoded || typeof encoded !== 'object' || encoded[ARRAY_BUFFER_BASE64_KEY] === undefined) return value
	return {
		...value,
		message: base64ToArrayBuffer(encoded[ARRAY_BUFFER_BASE64_KEY]),
	}
}

export function createSocketId(type) {
	return `${type}_${Date.now()}_${Math.random().toString(36).slice(2, 11)}`
}

export function invokeSocketMethod(name, socketId, data = {}) {
	return invokeAPI(name, { socketId, ...data, keep: true })
}

export function createNativeEvent(onName, offName, baseParams = {}, transform = value => value) {
	const listeners = new Set()
	let callbackId
	let afterEmit

	function stopNative() {
		if (!callbackId) return
		const currentId = callbackId
		callbackId = undefined
		callback.remove(currentId)
		invokeAPI(offName, { ...baseParams, callbackId: currentId, keep: true })
	}

	return {
		on(listener) {
			if (typeof listener !== 'function' || listeners.has(listener)) return
			listeners.add(listener)
			if (callbackId) return

			callbackId = callback.store((value) => {
				const result = transform(value)
				for (const current of [...listeners]) current(result)
				afterEmit?.()
			}, true)
			return invokeAPI(onName, { ...baseParams, callbackId, success: callbackId, keep: true })
		},
		off(listener) {
			if (typeof listener === 'function') listeners.delete(listener)
			else listeners.clear()
			if (listeners.size === 0) return stopNative()
		},
		dispose({ notifyNative = false } = {}) {
			listeners.clear()
			if (notifyNative) return stopNative()
			if (callbackId) callback.remove(callbackId)
			callbackId = undefined
		},
		hasListeners() {
			return listeners.size > 0
		},
		setAfterEmit(handler) {
			afterEmit = handler
		},
	}
}
