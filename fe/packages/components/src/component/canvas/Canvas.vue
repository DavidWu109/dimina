<script setup>
// 画布
// https://developers.weixin.qq.com/miniprogram/dev/component/canvas.html

import { hasEvent, triggerEvent, useInfo } from '@/common/events'
import { useTouchEvents } from '@/common/useTouchEvents'

const props = defineProps({
	canvasId: {
		type: String,
		default: '',
	},
	disableScroll: {
		type: Boolean,
		default: false,
	},
	type: {
		type: String,
		default: '',
	},
	newTouchListener: {
		type: Boolean,
		default: false,
	},
	renderWidth: {
		type: Number,
		default: 300,
	},
	renderHeight: {
		type: Number,
		default: 150,
	},
})

const info = useInfo()
const canvasRef = ref(null)
const rootRef = ref(null)
const isError = ref(false)

const hasTouchEvents = ['touchstart', 'touchmove', 'touchend', 'touchcancel', 'longpress', 'longtap']
	.some(eventName => hasEvent(info, eventName))
if (hasTouchEvents) {
	useTouchEvents(info, rootRef)
}

function preventScroll(event) {
	if (props.disableScroll && event.cancelable) {
		event.preventDefault()
	}
}

onMounted(() => {
	if (props.type) return
	let errMsg
	if (!props.canvasId) {
		errMsg = 'canvas-id attribute is undefined'
	}
	else {
		const scope = rootRef.value.closest('.dd-page') || document
		const duplicates = Array.from(scope.querySelectorAll('canvas[canvas-id]'))
			.filter(canvas => canvas.getAttribute('canvas-id') === props.canvasId)
		if (duplicates.length > 1) errMsg = `canvas-id ${props.canvasId} in this page has already existed`
	}
	if (errMsg) {
		isError.value = true
		triggerEvent('error', { info, detail: { errMsg } })
	}
})
</script>

<template>
	<div ref="rootRef" v-bind="$attrs" class="dd-canvas" :style="isError ? { display: 'none' } : undefined" @touchmove="preventScroll">
		<canvas
			ref="canvasRef" :canvas-id="canvasId" :data-type="type || undefined"
			:width="renderWidth" :height="renderHeight"
		/>
		<div class="dd-canvas-slot">
			<slot />
		</div>
	</div>
</template>

<style lang="scss">
.dd-canvas {
	display: block;
	position: relative;
	width: 300px;
	height: 150px;

	> canvas {
		position: absolute;
		top: 0;
		left: 0;
		width: 100%;
		height: 100%;
	}

	&[hidden] {
		display: none;
	}
}

.dd-canvas-slot {
	position: absolute;
	top: 0;
	left: 0;
	width: 100%;
	height: 100%;
	overflow: hidden;
	pointer-events: none;

	* {
		pointer-events: auto;
	}
}
</style>
