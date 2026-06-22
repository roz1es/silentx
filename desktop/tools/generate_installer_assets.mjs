import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs/promises';
import sharp from 'sharp';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..', '..');
const logoPath = path.join(root, 'client', 'public', 'icon-512.png');
const outDir = path.join(root, 'desktop', 'installer', 'windows', 'assets');

await fs.mkdir(outDir, { recursive: true });

await sharp(logoPath)
  .resize(92, 92)
  .extend({
    top: 14,
    bottom: 14,
    left: 14,
    right: 14,
    background: { r: 255, g: 255, b: 255, alpha: 0 },
  })
  .png()
  .toFile(path.join(outDir, 'wizard-small.png'));

const sidebarSvg = `
<svg width="164" height="314" viewBox="0 0 164 314" fill="none" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="10" y1="0" x2="164" y2="314" gradientUnits="userSpaceOnUse">
      <stop stop-color="#eef2ff"/>
      <stop offset="0.42" stop-color="#cfd6e7"/>
      <stop offset="1" stop-color="#747b8d"/>
    </linearGradient>
    <linearGradient id="glass" x1="42" y1="58" x2="132" y2="194" gradientUnits="userSpaceOnUse">
      <stop stop-color="white" stop-opacity="0.86"/>
      <stop offset="1" stop-color="#d9deeb" stop-opacity="0.38"/>
    </linearGradient>
    <filter id="shadow" x="-20" y="-20" width="220" height="360" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">
      <feDropShadow dx="0" dy="18" stdDeviation="18" flood-color="#111827" flood-opacity="0.28"/>
    </filter>
  </defs>
  <rect width="164" height="314" rx="0" fill="url(#bg)"/>
  <circle cx="132" cy="34" r="70" fill="white" fill-opacity="0.22"/>
  <circle cx="6" cy="278" r="88" fill="#111827" fill-opacity="0.16"/>
  <g filter="url(#shadow)">
    <rect x="28" y="52" width="108" height="108" rx="28" fill="url(#glass)" stroke="white" stroke-opacity="0.66" stroke-width="2"/>
  </g>
  <text x="24" y="211" fill="#111827" font-family="Inter, Segoe UI, Arial" font-weight="800" font-size="20">Бренкс</text>
  <text x="24" y="235" fill="#111827" font-family="Inter, Segoe UI, Arial" font-weight="800" font-size="20">Чат</text>
  <text x="24" y="260" fill="#374151" font-family="Inter, Segoe UI, Arial" font-weight="600" font-size="10" letter-spacing="1.6">DESKTOP</text>
</svg>`;

await sharp(Buffer.from(sidebarSvg))
  .composite([
    {
      input: await sharp(logoPath).resize(88, 88).png().toBuffer(),
      left: 38,
      top: 62,
    },
  ])
  .png()
  .toFile(path.join(outDir, 'wizard-sidebar.png'));
