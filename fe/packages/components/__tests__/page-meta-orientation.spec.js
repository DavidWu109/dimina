/** @vitest-environment jsdom */

import fs from 'node:fs'
import { resolve } from 'node:path'
import { createApp, h, nextTick, provide, ref } from 'vue'
import PageMeta from '../src/component/page-meta/PageMeta.vue'

const PAGE_META_FILE = resolve(process.cwd(), 'src/component/page-meta/PageMeta.vue')

function orientationCalls() {
	return window.__message.invoke.mock.calls
		.map(([message]) => message)
		.filter(message => message.body.name === '__setPageOrientation')
}

describe('PageMeta orientation bridge', () => {
	let app
	let host
	let orientation

	beforeEach(() => {
		window.__message = { invoke: vi.fn() }
		window.__callback = {
			remove: vi.fn(),
			store: vi.fn(() => 'callback-1'),
		}
		host = document.createElement('div')
		document.body.appendChild(host)
		orientation = ref('portrait')
		app = createApp({
			setup() {
				provide('bridgeId', 'bridge-1')
				provide('path', 'page-path')
				provide('page-path', { id: 'module-1' })
				return () => h(PageMeta, { pageOrientation: orientation.value })
			},
		})
	})

	afterEach(() => {
		app?.unmount()
		host?.remove()
	})

	it('applies dynamic values and restores static configuration on unmount', async () => {
		app.mount(host)
		expect(orientationCalls().at(-1).body.params).toEqual({ pageOrientation: 'portrait' })

		orientation.value = 'landscape'
		await nextTick()
		expect(orientationCalls().at(-1).body.params).toEqual({ pageOrientation: 'landscape' })

		app.unmount()
		app = null
		expect(orientationCalls().at(-1).body.params).toEqual({ pageOrientation: '' })
	})

	it('treats an invalid dynamic value as removal of the override', async () => {
		app.mount(host)
		orientation.value = 'diagonal'
		await nextTick()

		expect(orientationCalls().at(-1).body.params).toEqual({ pageOrientation: '' })
	})

	it('uses an internal page-property bridge rather than a public device API', () => {
		const source = fs.readFileSync(PAGE_META_FILE, 'utf-8')

		expect(source).toContain("invokeAPI('__setPageOrientation'")
		expect(source).not.toContain("invokeAPI('setDeviceOrientation'")
	})
})
