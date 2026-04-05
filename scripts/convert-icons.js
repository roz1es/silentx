import sharp from 'sharp';
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const publicDir = join(__dirname, '..', 'client', 'public');

async function convertIcons() {
  const sourceFile = join(publicDir, 'icon-source.webp');
  const icon192 = join(publicDir, 'icon-192.png');
  const icon512 = join(publicDir, 'icon-512.png');
  const badge = join(publicDir, 'badge-72.png');

  // Create 192x192 icon
  await sharp(sourceFile)
    .resize(192, 192, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toFile(icon192);
  console.log('Created icon-192.png');

  // Create 512x512 icon
  await sharp(sourceFile)
    .resize(512, 512, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toFile(icon512);
  console.log('Created icon-512.png');

  // Create 72x72 badge (smaller version for notifications)
  await sharp(sourceFile)
    .resize(72, 72, { fit: 'contain', background: { r: 0, g: 0, b: 0, alpha: 0 } })
    .png()
    .toFile(badge);
  console.log('Created badge-72.png');

  console.log('All icons created successfully!');
}

convertIcons().catch(console.error);
