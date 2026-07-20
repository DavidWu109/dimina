import fs from 'node:fs'
import path from 'node:path'
import { isMainThread, parentPort } from 'node:worker_threads'
import { compileStyle } from '@vue/compiler-sfc'
import autoprefixer from 'autoprefixer'
import cssnano from 'cssnano'
import less from 'less'
import postcss from 'postcss'
import selectorParser from 'postcss-selector-parser'
import * as sass from 'sass'
import { collectAssets, tagWhiteList, transformRpx } from '../common/utils.js'
import { getAppId, getComponent, getContentByPath, getStyleExts, getTargetPath, getWorkPath, resetStoreInfo } from '../env.js'

const compileRes = new Map()

if (!isMainThread) {
	parentPort.on('message', async ({ pages, storeInfo }) => {
		try {
			resetStoreInfo(storeInfo)

			const progress = {
				_completedTasks: 0,
				get completedTasks() {
					return this._completedTasks
				},
				set completedTasks(value) {
					this._completedTasks = value

					parentPort.postMessage({ completedTasks: this._completedTasks })
				},
			}

			await compileSS(pages.mainPages, null, progress)

			for (const [root, subPages] of Object.entries(pages.subPages)) {
				await compileSS(subPages.info, root, progress)
			}

			// Worker 任务完成后清理缓存，释放内存
			compileRes.clear()

			parentPort.postMessage({ success: true })
		}
		catch (error) {
			// 错误时也清理缓存
			compileRes.clear()
			
			parentPort.postMessage({ 
				success: false, 
				error: {
					message: error.message,
					stack: error.stack,
					name: error.name
				}
			})
		}
	})
}

/**
 *  编译样式文件
 */
async function compileSS(pages, root, progress) {
	// page 样式
	for (const page of pages) {
		const code = await buildCompileCss(page, new Set()) || ''
		const filename = `${page.path.replace(/\//g, '_')}`
		if (root) {
			const subDir = `${getTargetPath()}/${root}`
			if (!fs.existsSync(subDir)) {
				fs.mkdirSync(subDir, { recursive: true })
			}

			fs.writeFileSync(`${subDir}/${filename}.css`, code)
		}
		else {
			const mainDir = `${getTargetPath()}/main`
			if (!fs.existsSync(mainDir)) {
				fs.mkdirSync(mainDir, { recursive: true })
			}

			fs.writeFileSync(`${mainDir}/${filename}.css`, code)
		}

		progress.completedTasks++
	}
}

async function buildCompileCss(module, compiledPaths = new Set()) {
	let result = ''
	const pendingModules = [module]

	while (pendingModules.length > 0) {
		const currentModule = pendingModules.pop()
		const currentPath = currentModule.path || currentModule.absolutePath

		// A component stylesheet only needs to be emitted once per page traversal.
		// Mark it before visiting children so self and mutual references close
		// naturally without a fixed depth limit.
		if (compiledPaths.has(currentPath)) {
			continue
		}
		compiledPaths.add(currentPath)
		result += await enhanceCSS(currentModule) || ''

		// Preserve the original depth-first, declaration-order traversal while
		// using an explicit stack instead of the JavaScript call stack.
		const componentPaths = Object.values(currentModule.usingComponents || {})
		for (let index = componentPaths.length - 1; index >= 0; index--) {
			const componentModule = getComponent(componentPaths[index])
			if (componentModule) {
				pendingModules.push(componentModule)
			}
		}
	}

	return result
}

function boostExternalClassSelectors(cssCode, moduleId) {
	if (!moduleId || !cssCode) {
		return cssCode
	}

	const scopeAttribute = `data-v-${moduleId}`
	const externalScopeAttribute = 'data-dd-external-class-scope'
	const ast = postcss.parse(cssCode)

	ast.walkRules((rule) => {
		if (!rule.selector.includes(`[${scopeAttribute}]`)) {
			return
		}

		rule.selector = selectorParser((selectors) => {
			for (const selector of [...selectors.nodes]) {
				const boostedSelector = selector.clone()
				const scopeNodes = []
				boostedSelector.walkAttributes((attribute) => {
					if (attribute.attribute === scopeAttribute) {
						scopeNodes.push(attribute)
					}
				})

				const targetScope = scopeNodes.at(-1)
				if (!targetScope) {
					continue
				}

				targetScope.parent.insertAfter(targetScope, selectorParser.attribute({
					attribute: externalScopeAttribute,
					operator: '~=',
					quoteMark: '"',
					value: scopeAttribute,
				}))
				selectors.append(boostedSelector)
			}
		}).processSync(rule.selector)
	})

	return ast.toResult().css
}

async function enhanceCSS(module) {
	const absolutePath = module.absolutePath ? module.absolutePath : getAbsolutePath(module.path)
	if (!absolutePath) {
		// 样式文件不存在
		return ''
	}
	const cacheKey = `${absolutePath}::${module.id || ''}`

	const inputCSS = getContentByPath(absolutePath)
	if (!inputCSS) {
		return ''
	}

	if (compileRes.has(cacheKey)) {
		return compileRes.get(cacheKey)
	}

	// 预处理器编译
	let processedCSS = normalizeRootStyleImports(inputCSS)
	const ext = path.extname(absolutePath).toLowerCase()
	
	try {
		if (ext === '.less') {
			const result = await less.render(processedCSS, {
				filename: absolutePath,
				paths: [path.dirname(absolutePath), getWorkPath()],
			})
			processedCSS = result.css
		} else if (ext === '.scss' || ext === '.sass') {
			const result = sass.compileString(processedCSS, {
				loadPaths: [path.dirname(absolutePath), getWorkPath()],
				syntax: ext === '.sass' ? 'indented' : 'scss',
			})
			processedCSS = result.css
		}
	} catch (error) {
		console.error(`[style] 预处理器编译失败 ${absolutePath}:`, error.message)
		// 如果预处理器编译失败，使用原始内容继续处理
		processedCSS = inputCSS
	}

	const fixedCSS = ensureImportSemicolons(processedCSS)

	let ast
	try {
		ast = postcss.parse(fixedCSS)
	} catch (error) {
		console.error(`[style] PostCSS 解析失败 ${absolutePath}:`, error.message)
		// 如果 PostCSS 解析失败，返回空字符串
		return ''
	}
	const promises = []
	ast.walk(async (node) => {
		if (node.type === 'atrule' && node.name === 'import') {
			// @import 样式导入
			// 替换字符串首尾的引号
			const str = node.params.replace(/^['"]|['"]$/g, '')
			const importFullPath = resolveStyleImportPath(absolutePath, str)

			node.remove()

			promises.push(buildCompileCss({ absolutePath: importFullPath, id: module.id }, new Set()))
		}
		else if (node.type === 'rule') {
			// 处理 ::v-deep
			if (node.selector.includes('::v-deep')) {
				node.selector = node.selector.replace(/::v-deep\s+(\S[^{]*)/g, ':deep($1)')
			}

			// 处理 :host 选择器
			if (node.selector.includes(':host')) {
				node.selector = processHostSelector(node.selector, module.id)
			}

			// 转换基础组件标签为类选择器
			node.selector = selectorParser((selectors) => {
				selectors.walkTags((tag) => {
					if (tagWhiteList.includes(tag.value)) {
						tag.value = `.dd-${tag.value}`
					}
				})
			}).processSync(node.selector)
		}
		else if (node.type === 'comment') {
			// 移除注释
			node.remove()
		}
	})

	ast.walkDecls((decl) => {
		decl.value = normalizeCssUrlValue(decl.value, absolutePath)
		decl.value = transformRpx(decl.value)
	})

	const cssCode = ast.toResult().css

	// 样式隔离
	const moduleId = module.id
	const scopedCode = compileStyle({
		source: cssCode,
		id: moduleId,
		scoped: !!moduleId,
	}).code
	const externalClassCode = boostExternalClassSelectors(scopedCode, moduleId)

	// 统一后处理：autoprefixer + 压缩
	const res = await postcss([
		autoprefixer({ overrideBrowserslist: ['cover 99.5%'] }), 
		cssnano()
	]).process(externalClassCode, { from: undefined })

	// 处理导入的样式
	const importCss = (await Promise.all(promises))
		.filter(Boolean)
		.join('')

	const result = importCss + res.css

	compileRes.set(cacheKey, result)

	return result
}

function normalizeCssUrlValue(value, absolutePath) {
	return value.replace(/url\(([^)]+)\)/g, (fullMatch, rawUrl) => {
		const cleanedUrl = rawUrl.trim().replace(/^['"]|['"]$/g, '')

		if (!cleanedUrl || cleanedUrl.startsWith('data:image')) {
			return fullMatch
		}

		if (cleanedUrl.startsWith('//')) {
			return `url(https:${cleanedUrl})`
		}

		if (/^(https?:|blob:|data:)/.test(cleanedUrl)) {
			return fullMatch
		}

		const realSrc = collectAssets(getWorkPath(), absolutePath, cleanedUrl, getTargetPath(), getAppId())
		return `url(${realSrc})`
	})
}

function getAbsolutePath(modulePath) {
	const workPath = getWorkPath()
	const src = modulePath.startsWith('/') ? modulePath : `/${modulePath}`

	for (const ssType of getStyleExts()) {
		const ssFullPath = `${workPath}${src}${ssType}`
		if (fs.existsSync(ssFullPath)) {
			return ssFullPath
		}

		const indexSsFullPath = `${workPath}${src}/index${ssType}`
		if (fs.existsSync(indexSsFullPath)) {
			return indexSsFullPath
		}
	}
}

function resolveStyleImportPath(absolutePath, importPath, workPath = getWorkPath()) {
	if (importPath.startsWith('/')) {
		return path.join(workPath, importPath)
	}
	return path.resolve(path.dirname(absolutePath), importPath)
}

function normalizeRootStyleImports(source, workPath = getWorkPath()) {
	return source.replace(/(@import\s+(?:\(.*?\)\s*)?(?:url\()?['"])(\/[^'")]+)(['"]\)?)/g, (_, prefix, importPath, suffix) => {
		return `${prefix}${path.join(workPath, importPath)}${suffix}`
	})
}

/**
 * Ensures that all @import statements in CSS end with semicolons
 * @param {string} css - The CSS content to process
 * @returns {string} - The processed CSS with semicolons added to @import statements as needed
 */
function ensureImportSemicolons(css) {
	// 查找所有未以分号结尾的@import语句，并在它们后面添加分号
	return css.replace(/@import[^;\n]*$/gm, (match) => {
		// Check if the match already ends with a semicolon
		return match.endsWith(';') ? match : `${match};`
	})
}

/**
 * 处理 :host 选择器，将其转换为适合组件根节点的选择器
 * @param {string} selector - 包含 :host 的选择器
 * @param {string} moduleId - 组件的模块ID
 * @returns {string} - 转换后的选择器
 */
function processHostSelector(selector, moduleId) {
	const hostSelector = `[data-dd-style-host~="${moduleId}"]`

	return selector
		// :host(.class) 选择带有特定类的组件根节点
		.replace(/:host\(([^)]+)\)/g, `${hostSelector}$1`)
		// 宿主标记与 data-v 样式作用域分离，避免 shared 作用域扩散后 :host 误命中页面节点。
		.replace(/:host(?![\w-])/g, hostSelector)
}

export { boostExternalClassSelectors, compileSS, ensureImportSemicolons, normalizeCssUrlValue, normalizeRootStyleImports, processHostSelector, resolveStyleImportPath }
