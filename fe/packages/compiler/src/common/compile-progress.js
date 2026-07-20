import process from 'node:process'
import { isUnicodeSupported } from 'listr2'

const DEFAULT_TERMINAL_COLUMNS = 80
const MIN_PROGRESS_WIDTH = 8
const MAX_PROGRESS_WIDTH = 28
const RENDERER_CHROME_WIDTH = 14
const PROGRESS_BRACKETS_WIDTH = 2

/**
 * Format worker progress without assuming a fixed terminal width.
 * The completed count remains the source of truth. Whole cells avoid the
 * visible gap that partial block glyphs leave before the unfilled section.
 */
export function formatCompileProgress(completed, total, options = {}) {
	const unicode = options.unicode ?? isUnicodeSupported()
	const columns = normalizePositiveInteger(options.columns) || process.stdout.columns || DEFAULT_TERMINAL_COLUMNS
	const safeTotal = normalizePositiveInteger(total)
	const safeCompleted = Math.min(normalizePositiveInteger(completed), safeTotal)
	const ratio = safeTotal === 0 ? 0 : safeCompleted / safeTotal
	const percentage = Math.round(ratio * 100)
	const separator = unicode ? '·' : '|'
	const metadata = `${String(safeCompleted).padStart(String(safeTotal).length)}/${safeTotal} ${separator} ${String(percentage).padStart(3)}%`
	const availableWidth = columns - metadata.length - RENDERER_CHROME_WIDTH - PROGRESS_BRACKETS_WIDTH

	if (availableWidth < MIN_PROGRESS_WIDTH) {
		return metadata
	}

	const width = Math.min(availableWidth, MAX_PROGRESS_WIDTH)
	const bar = unicode
		? createUnicodeBar(ratio, width)
		: createAsciiBar(ratio, width)

	return `[${bar}]  ${metadata}`
}

function createUnicodeBar(ratio, width) {
	const completeWidth = Math.round(ratio * width)
	const emptyWidth = width - completeWidth

	return `${'█'.repeat(completeWidth)}${'░'.repeat(emptyWidth)}`
}

function createAsciiBar(ratio, width) {
	const completeWidth = Math.floor(ratio * width)
	const showHead = ratio > 0 && ratio < 1
	const bodyWidth = Math.max(0, completeWidth - (showHead ? 1 : 0))
	const emptyWidth = width - bodyWidth - (showHead ? 1 : 0)

	return `${'='.repeat(bodyWidth)}${showHead ? '>' : ''}${'-'.repeat(emptyWidth)}`
}

function normalizePositiveInteger(value) {
	return Number.isFinite(value) ? Math.max(0, Math.trunc(value)) : 0
}
