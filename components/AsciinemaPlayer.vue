<template>
  <div class="asciinema-container">
    <div ref="playerEl" />
  </div>
</template>

<script setup lang="ts">
import { onMounted, onBeforeUnmount, ref } from 'vue'

const props = defineProps<{
  src: string
  speed?: number
  autoplay?: boolean
  loop?: boolean
  cols?: number
  rows?: number
}>()

const playerEl = ref<HTMLDivElement | null>(null)
let player: any = null

onMounted(async () => {
  if (!playerEl.value) return

  // Lazy-load so SSR/build doesn't choke on window
  const mod = await import('asciinema-player')
  // @ts-ignore — CSS side-effect import
  await import('asciinema-player/dist/bundle/asciinema-player.css')

  player = mod.create(props.src, playerEl.value, {
    speed: props.speed ?? 1,
    autoPlay: props.autoplay ?? false,
    loop: props.loop ?? false,
    cols: props.cols ?? 120,
    rows: props.rows ?? 30,
    fit: 'both',
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
  max-width: 100%;
}
.asciinema-container :deep(.ap-player) {
  max-width: 100%;
  max-height: 100%;
}
</style>
