const listeners = new Set()

export function createWindowResizeEvent(size = {}) {
	return {
		size: {
			windowWidth: size.windowWidth,
			windowHeight: size.windowHeight,
		},
	}
}

export function addWindowResizeListener(listener) {
	if (typeof listener === 'function') {
		listeners.add(listener)
	}
}

export function removeWindowResizeListener(listener) {
	if (typeof listener === 'function') {
		listeners.delete(listener)
	}
	else {
		listeners.clear()
	}
}

export function emitWindowResize(event) {
	for (const listener of [...listeners]) {
		try {
			listener(event)
		}
		catch (error) {
			console.error('[window resize listener error]', error)
		}
	}
}
