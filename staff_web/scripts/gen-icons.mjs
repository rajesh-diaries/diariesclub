// Generates PWA + iOS home-screen icons from an inline SVG brand mark.
// Run: node scripts/gen-icons.mjs   (requires devDep `sharp`)
import sharp from 'sharp'
import { mkdirSync } from 'node:fs'

mkdirSync('public/icons', { recursive: true })

// Premium "PD" monogram on a navy→indigo gradient with a warm gold spark.
const svg = (size) => `
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1B2A6B"/>
      <stop offset="0.55" stop-color="#2C3FA0"/>
      <stop offset="1" stop-color="#4F7CFF"/>
    </linearGradient>
    <linearGradient id="gold" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FFD66B"/>
      <stop offset="1" stop-color="#FFB938"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="112" fill="url(#bg)"/>
  <text x="50%" y="58%" text-anchor="middle" font-family="-apple-system, SF Pro Display, Segoe UI, Roboto, sans-serif"
        font-size="232" font-weight="800" fill="#FFFFFF" letter-spacing="-12">PD</text>
  <circle cx="372" cy="150" r="34" fill="url(#gold)"/>
</svg>`

const out = [
  ['public/icons/icon-192.png', 192],
  ['public/icons/icon-512.png', 512],
  ['public/icons/maskable-512.png', 512],
  ['public/icons/apple-touch-icon.png', 180],
]

for (const [file, size] of out) {
  await sharp(Buffer.from(svg(size))).resize(size, size).png().toFile(file)
  console.log('wrote', file)
}
