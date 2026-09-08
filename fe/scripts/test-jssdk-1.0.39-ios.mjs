import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import vm from 'node:vm'
import { test } from 'node:test'

const archive = process.env.JSSDK_ARCHIVE
assert(archive, 'Set JSSDK_ARCHIVE to the actual main.zip being tested')
const frame = execFileSync('unzip', ['-p', archive, 'main/assets/pageFrame.js'], { encoding: 'utf8' })
const start = frame.indexOf('ah={__name:`WebView`') + 3
const end = frame.indexOf(',oh=Y(', start)
assert(start > 3 && end > start)
const componentCode = frame.slice(start, end)

// Evaluate the published component, not a reimplementation. Native, DOM and Vue
// scheduling are isolated test doubles, so no network or app state is touched.
function harness({ desktop = false } = {}) {
	const calls = [], events = [], watches = [], off = [], frames = []
	const listeners = new Map()
	let mount, unmount, observerDisconnected = false
	const props = { id: 'first', src: 'https://example.test/one' }
	const element = { getBoundingClientRect: () => ({ left: 1, top: 2, width: 300, height: 500 }),
		hasAttribute: () => false }
	const window = { scrollX: 0, scrollY: 10, innerWidth: 390, innerHeight: 800,
		ResizeObserver: true,
		addEventListener: (name, fn) => listeners.set(name, fn),
		removeEventListener: name => listeners.delete(name) }
	const nativeEvents = new Map()
	const context = vm.createContext({
		z: () => ({ value: element }), J: getter => ({ get value() { return getter() } }),
		X: () => ({ bridgeId: 7, moduleId: 8, attrs: { bindload: 'loaded' } }),
		Ac: desktop, Dc: false, ih: 'native/webview', rh: '$1\uFFFD$2', encodeURI, window,
		$c: (name, payload) => calls.push({ name, ...payload }),
		Z: (name, payload) => events.push({ name, ...payload }),
		tl: (name, fn) => { nativeEvents.set(name, fn); return () => off.push(name) },
		ji: fn => { mount = fn }, Pi: fn => { unmount = fn },
		H: (getter, fn, options) => watches.push({ getter, fn, options }),
		requestAnimationFrame: fn => { frames.push(fn); return frames.length },
		cancelAnimationFrame: () => {},
		ResizeObserver: class { observe() {} disconnect() { observerDisconnected = true } },
	})
	context.props = props
	vm.runInContext(`(${componentCode}).setup(props)`, context, { timeout: 1000 })
	function change(id, src = props.src) {
		const old = [props.id, props.src]
		props.id = id
		props.src = src
		watches[0].fn([id, src], old)
	}
	return { calls, events, watches, off, frames, props, mount, unmount, change,
		listeners, nativeEvents, get disconnected() { return observerDisconnected } }
}

test('mount carries layout, module and both parent-page identifiers', () => {
	const h = harness(); h.mount()
	const call = h.calls[0]
	assert.equal(call.name, 'componentMount')
	assert.equal(call.params.id, 'first')
	assert.equal(call.params.parentWebViewId, 7)
	assert.equal(call.params.bridgeId, 7)
	assert.equal(call.params.rect.pageTop, 12)
	assert.equal(call.params.attributes.moduleId, 8)
})
test('id changes unmount old instance and mount new instance after DOM update', () => {
	const h = harness(); h.mount(); h.change('second')
	assert.equal(h.watches[0].options.flush, 'post')
	assert.deepEqual(h.calls.map(c => [c.name, c.params.id]), [
		['componentMount', 'first'], ['componentUnmount', 'first'], ['componentMount', 'second']])
	h.change('third'); h.unmount()
	assert.equal(h.calls.at(-1).params.id, 'third')
})
test('src changes update without recreating and changes after unmount do nothing', () => {
	const h = harness(); h.mount(); h.change('first', 'https://example.test/two')
	assert.equal(h.calls.at(-1).name, 'propsUpdate')
	assert.equal(h.calls.at(-1).params.url, 'https://example.test/two')
	h.unmount(); const count = h.calls.length; h.change('after-unmount')
	assert.equal(h.calls.length, count)
})
test('native error forwards errMsg and ignores events owned by another component', () => {
	const h = harness(); h.mount()
	h.nativeEvents.get('binderror')({ id: 'other', errMsg: 'ignore' })
	assert.equal(h.events.length, 0)
	h.nativeEvents.get('binderror')({ id: 'first', errMsg: 'invalid URL', url: 'bad' })
	assert.equal(h.events[0].detail.errMsg, 'invalid URL')
})
test('scroll is coalesced; unmount removes listeners and native event handlers', () => {
	const h = harness(); h.mount()
	h.listeners.get('scroll')(); h.listeners.get('scroll')()
	assert.equal(h.frames.length, 1)
	h.frames[0](); h.unmount()
	assert.equal(h.listeners.size, 0)
	assert.equal(h.off.length, 3)
	assert(h.disconnected)
})
test('desktop remains an iframe without native mount/update/unmount calls', () => {
	const h = harness({ desktop: true }); h.mount(); h.change('second'); h.unmount()
	assert.equal(h.calls.length, 0)
})
test('release registers host methods dynamically, including requireEchoAuthorize', () => {
	const service = execFileSync('unzip', ['-p', archive, 'main/assets/service.js'], { encoding: 'utf8' })
	const begin = service.indexOf('function md(')
	const end = service.indexOf('var hd=', begin)
	assert(begin >= 0 && end > begin)
	const calls = [], methods = {}
	const context = vm.createContext({ pd: new Set(), fd: methods, T: (...args) => calls.push(args) })
	vm.runInContext(`${service.slice(begin, end)}md(['requireEchoAuthorize']);fd.requireEchoAuthorize({scopes:['scope.wish']})`, context, { timeout: 1000 })
	assert.equal(calls[0][0], 'requireEchoAuthorize')
	assert.equal(calls[0][1].scopes[0], 'scope.wish')
})
