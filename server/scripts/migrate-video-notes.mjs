import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import mysql from 'mysql2/promise';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const serverDir = path.resolve(scriptDir, '..');
const dryRun = process.argv.includes('--dry-run');
const migrateAll = process.argv.includes('--all');

async function loadEnv() {
  const envPath = path.join(serverDir, '.env');
  let contents;
  try {
    contents = await fs.readFile(envPath, 'utf8');
  } catch {
    return;
  }
  for (const line of contents.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const separator = trimmed.indexOf('=');
    if (separator <= 0) continue;
    const key = trimmed.slice(0, separator).trim();
    let value = trimmed.slice(separator + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
}

function parseDataUrl(dataUrl) {
  const match = String(dataUrl).match(/^data:([^;,\s]+)(?:;.*)?;base64,(.+)$/);
  if (!match) throw new Error('Некорректный data URL');
  return {
    mime: match[1],
    buffer: Buffer.from(match[2], 'base64'),
  };
}

function runFfmpeg(inputPath, outputPath) {
  const args = [
    '-y',
    '-hide_banner',
    '-loglevel',
    'error',
    '-i',
    inputPath,
    '-map',
    '0:v:0',
    '-map',
    '0:a?',
    '-vf',
    'crop=min(iw\\,ih):min(iw\\,ih),scale=360:360:flags=lanczos,fps=24,format=yuv420p',
    '-c:v',
    'libx264',
    '-preset',
    'fast',
    '-crf',
    '29',
    '-profile:v',
    'baseline',
    '-level',
    '3.0',
    '-tag:v',
    'avc1',
    '-movflags',
    '+faststart',
    '-c:a',
    'aac',
    '-b:a',
    '48k',
    '-map_metadata',
    '-1',
    outputPath,
  ];
  return new Promise((resolve, reject) => {
    const child = spawn('ffmpeg', args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let errorText = '';
    child.stderr.on('data', (chunk) => {
      errorText += String(chunk);
    });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(errorText.trim() || `ffmpeg завершился с кодом ${code}`));
    });
  });
}

await loadEnv();

if (!process.env.DATABASE_URL) {
  throw new Error('DATABASE_URL не задан в server/.env');
}

const connection = await mysql.createConnection({
  uri: process.env.DATABASE_URL,
  dateStrings: true,
});
const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'brenks-video-notes-'));

try {
  const [rows] = await connection.execute(
    `SELECT id, media_data_url, media_mime_type
       FROM messages
      WHERE media_kind = 'video_note'
        AND media_data_url IS NOT NULL
        ${
          migrateAll
            ? ''
            : "AND (media_mime_type IS NULL OR media_mime_type NOT LIKE 'video/mp4%')"
        }
      ORDER BY created_at`
  );

  if (rows.length === 0) {
    console.log('Кружков для миграции нет.');
    process.exitCode = 0;
  } else {
    const backupDir =
      process.env.VIDEO_MIGRATION_BACKUP_DIR || path.join(serverDir, 'data');
    await fs.mkdir(backupDir, { recursive: true });
    const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
    const backupPath = path.join(
      backupDir,
      `video-notes-before-mp4-${stamp}.json`
    );
    await fs.writeFile(backupPath, JSON.stringify(rows), { mode: 0o600 });
    await fs.chmod(backupPath, 0o600);
    console.log(`Резервная копия: ${backupPath}`);

    const converted = [];
    const failed = [];
    for (const [index, row] of rows.entries()) {
      try {
        const parsed = parseDataUrl(row.media_data_url);
        const inputExt = parsed.mime.includes('webm') ? 'webm' : 'video';
        const inputPath = path.join(tempDir, `${index}.${inputExt}`);
        const outputPath = path.join(tempDir, `${index}.mp4`);
        await fs.writeFile(inputPath, parsed.buffer);
        await runFfmpeg(inputPath, outputPath);
        const output = await fs.readFile(outputPath);
        const dataUrl = `data:video/mp4;base64,${output.toString('base64')}`;
        if (dataUrl.length > 14_000_000) {
          throw new Error('результат превышает лимит размера');
        }
        converted.push({ id: String(row.id), dataUrl });
        console.log(`Подготовлено ${index + 1}/${rows.length}: ${row.id}`);
      } catch (error) {
        const reason = error instanceof Error ? error.message : String(error);
        failed.push({ id: String(row.id), reason });
        console.warn(`Пропущено ${index + 1}/${rows.length}: ${row.id} (${reason})`);
      }
    }

    if (dryRun) {
      console.log(`Проверка завершена: ${converted.length} кружков готовы к миграции.`);
    } else if (converted.length > 0) {
      await connection.beginTransaction();
      try {
        for (const item of converted) {
          await connection.execute(
            `UPDATE messages
                SET media_data_url = ?, media_mime_type = 'video/mp4'
              WHERE id = ? AND media_kind = 'video_note'`,
            [item.dataUrl, item.id]
          );
        }
        await connection.commit();
      } catch (error) {
        await connection.rollback();
        throw error;
      }
      console.log(`Готово: ${converted.length} кружков сохранены в MP4.`);
    }
    if (failed.length > 0) {
      console.warn(
        `Не удалось восстановить ${failed.length} повреждённых кружков: ${failed
          .map((item) => item.id)
          .join(', ')}`
      );
    }
  }
} finally {
  await connection.end();
  await fs.rm(tempDir, { recursive: true, force: true });
}
