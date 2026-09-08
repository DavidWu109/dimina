import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const WEB_VIEW_FILE = fileURLToPath(new URL('../src/component/web-view/WebView.vue', import.meta.url))
const source = fs.readFileSync(WEB_VIEW_FILE, 'utf-8')

describe('web-view iOS native component contract', () => {
	it('sends layout and parent-page context to the native host', () => {
		expect(source).toContain("const type = 'native/webview'")
		expect(source).toContain('rect: getRect()')
		expect(source).toContain('parentWebViewId: info.bridgeId')
		expect(source).toContain("invokeNative('componentMount'")
		expect(source).toContain("invokeNative('componentUnmount'")
	})

	it('keeps native bounds synchronized without fixed delays', () => {
		expect(source).toContain("window.addEventListener('scroll', scheduleSyncRect, true)")
		expect(source).toContain('new ResizeObserver(scheduleSyncRect)')
		expect(source).not.toContain('setTimeout(')
	})

	it('preserves component ownership for native events and id changes', () => {
		expect(source).toContain('msg.id !== props.id')
		expect(source).toContain("invokeNative('componentUnmount', oldId)")
		expect(source).toContain('nativeEventOffs.splice(0).forEach(off => off())')
	})
})
