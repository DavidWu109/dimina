// Apply the local WebView fixes to the exact published Furina 1.0.39 artifact.
// Do not rebuild the rest of the release from the older local fe/ checkout.
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const [input, output] = process.argv.slice(2)
assert(input && output, 'Usage: node patch-jssdk-1.0.39-ios.mjs <published jssdk.zip> <output directory>')
const original = execFileSync('unzip', ['-p', path.resolve(input), 'jssdk/main.zip'])
const sha256 = data => createHash('sha256').update(data).digest('hex')
assert.equal(sha256(original), '1d82b6b41287f3c9433a97c92648740a7cc40a1b7280c4cea2902101ba2733f3',
	'Unexpected release: review the new source and artifact before porting this patch')
const config = JSON.parse(execFileSync('unzip', ['-p', path.resolve(input), 'jssdk/config.json'], { encoding: 'utf8' }))
assert.deepEqual(config, { versionCode: 40, versionName: '1.0.39' })
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'dimina-jssdk-ios-'))
try {
	const archive = path.join(temp, 'original.zip')
	fs.writeFileSync(archive, original)
	const files = ['main/assets/dimina-logo.png', 'main/assets/pageFrame.css',
		'main/assets/pageFrame.js', 'main/assets/service.js', 'main/pageFrame.html']
	const entries = execFileSync('unzip', ['-Z1', archive], { encoding: 'utf8' }).trim().split('\n')
	assert.deepEqual(entries.filter(entry => !entry.endsWith('/')).sort(), [...files].sort())
	for (const name of files) {
		const destination = path.join(temp, name)
		fs.mkdirSync(path.dirname(destination), { recursive: true })
		fs.writeFileSync(destination, execFileSync('unzip', ['-p', archive, name]))
	}
	const frame = path.join(temp, 'main/assets/pageFrame.js')
	let code = fs.readFileSync(frame, 'utf8')
	const start = code.indexOf('ah={__name:`WebView`')
	const end = code.indexOf(',oh=Y(', start)
	assert(start >= 0 && end > start, 'WebView component boundaries changed')
	const before = code.slice(start, end)
	let component = before
	function replace(from, to) {
		assert.equal(component.split(from).length - 1, 1, `Patch anchor changed: ${from}`)
		component = component.replace(from, to)
	}
	replace('u,d=!1;', 'u,d=!1,mountedWebViewId=``;')
	replace('function m(){', 'function m(e=t.id){')
	replace('id:t.id,bridgeId:o.bridgeId,', 'id:e,bridgeId:o.bridgeId,parentWebViewId:o.bridgeId,')
	replace('function h(e){Ac||e===`propsUpdate`&&!d||$c(e,{bridgeId:o.bridgeId,params:m()})}',
		'function h(e,n=mountedWebViewId||t.id){Ac||e===`propsUpdate`&&!d||$c(e,{bridgeId:o.bridgeId,params:m(n)})}')
	replace('fullUrl:e.fullUrl,id:e.id}', 'fullUrl:e.fullUrl,id:e.id,errMsg:e.errMsg}')
	replace('d=!0,h(`componentMount`)', 'd=!0,mountedWebViewId=t.id,h(`componentMount`)')
	// Post-flush observes the new DOM before measuring it; no timer or deferred remount.
	replace('H(()=>[t.id,a.value],()=>h(`propsUpdate`))',
		'H(()=>[t.id,a.value],([newId,newUrl],[oldId,oldUrl])=>{if(!d||Ac)return;if(newId!==oldId){h(`componentUnmount`);mountedWebViewId=newId;h(`componentMount`)}else if(newUrl!==oldUrl)h(`propsUpdate`)},{flush:`post`})')
	replace('h(`componentUnmount`),d=!1,s.splice', 'h(`componentUnmount`),d=!1,mountedWebViewId=``,s.splice')
	code = code.slice(0, start) + component + code.slice(end)
	fs.writeFileSync(frame, code)
	execFileSync(process.execPath, ['--check', frame])
	const patched = path.join(temp, 'patched.zip')
	const zipEpoch = new Date('1980-01-01T00:00:00Z')
	for (const name of files) fs.utimesSync(path.join(temp, name), zipEpoch, zipEpoch)
	execFileSync('zip', ['-X', '-q', patched, ...files], { cwd: temp, env: { ...process.env, TZ: 'UTC' } })
	// Every non-WebView release file must remain byte-identical.
	for (const name of files.filter(name => !name.endsWith('pageFrame.js'))) {
		assert.deepEqual(execFileSync('unzip', ['-p', patched, name]), execFileSync('unzip', ['-p', archive, name]))
	}
	fs.mkdirSync(output, { recursive: true })
	fs.copyFileSync(patched, path.join(output, 'main.zip'))
	fs.writeFileSync(path.join(output, 'config.json'), `${JSON.stringify(config, null, 2)}\n`)
	console.log(JSON.stringify({ version: config, mainSHA256: sha256(fs.readFileSync(patched)),
		modifiedReleaseFile: 'main/assets/pageFrame.js', component: 'WebView' }, null, 2))
} finally {
	fs.rmSync(temp, { recursive: true, force: true })
}
