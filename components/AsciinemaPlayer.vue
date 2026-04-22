<template>
  <div class="asciinema-container">
    <div ref="playerEl" class="ap-slot" />
  </div>
</template>

<script setup lang="ts">
import { onMounted, onBeforeUnmount, ref } from 'vue'
import * as AsciinemaPlayer from 'asciinema-player'
import 'asciinema-player/dist/bundle/asciinema-player.css'

const props = defineProps<{
  src: string
  speed?: number
  autoplay?: boolean
  loop?: boolean
  cols?: number
  rows?: number
  fit?: string
}>()

const playerEl = ref<HTMLDivElement | null>(null)
let player: any = null

onMounted(() => {
  if (!playerEl.value) return
  player = AsciinemaPlayer.create(props.src, playerEl.value, {
    speed: props.speed ?? 1,
    autoPlay: props.autoplay ?? false,
    loop: props.loop ?? false,
    cols: props.cols ?? 120,
    rows: props.rows ?? 30,
    fit: props.fit ?? 'both',
    theme: 'monokai',
    idleTimeLimit: 1,
  })
})

onBeforeUnmount(() => {
  player?.dispose?.()
})
</script>

<style scoped>
.asciinema-container {
  border-radius: 10px;
  overflow: hidden;
  border: 1px solid var(--vc-slate-light);
  background: var(--vc-slate-deep);
  width: 100%;
  height: 100%;
  min-height: 340px;
}
.ap-slot {
  width: 100%;
  height: 100%;
}
.asciinema-container :deep(.ap-wrapper),
.asciinema-container :deep(.asciinema-player) {
  width: 100% !important;
  height: 100% !important;
  max-width: 100%;
  max-height: 100%;
}
</style>
