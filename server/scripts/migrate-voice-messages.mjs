import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import mysql from 'mysql2/promise';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const serverDir = path.resolve(scriptDir, '..');
const dryRun = process.argv.includes('--dry-run');

async function loadEnv() {
  try {
    const contents = await fs.readFile(path.join(serverDir, '.env'), 'utf8');
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
  } catch {
    // Environment variables may already be provided by the service host.
  }
}

function parseDataUrl(dataUrl) {
  const match = String(dataUrl).match(/^data:([^;,\s]+)(?:;.*)?;base64,(.+)$/);
  if (!match) throw new Error('Некорректный data URL');
  return Buffer.from(match[2], 'base64');
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
    '0:a:0',
    '-vn',
    '-c:a',
    'aac',
    '-b:a',
    '56k',
    '-movflags',
    '+faststart',
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
if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL не задан');

const connection = await mysql.createConnection({
  uri: process.env.DATABASE_URL,
  dateStrings: true,
});
const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'brenks-voice-'));

try {
  const [rows] = await connection.execute(
    `SELECT id, media_data_url, media_mime_type
       FROM messages
      WHERE media_kind = 'voice'
        AND media_data_url IS NOT NULL
      ORDER BY created_at`
  );
  if (rows.length === 0) {
    console.log('Голосовых для миграции нет.');
  } else {
    const backupDir =
      process.env.VOICE_MIGRATION_BACKUP_DIR || path.join(serverDir, 'data');
    await fs.mkdir(backupDir, { recursive: true });
    const stamp = new Date().toISOString().replaceAll(':', '-').replaceAll('.', '-');
    const backupPath = path.join(
      backupDir,
      `voice-messages-before-mp4-${stamp}.json`
    );
    await fs.writeFile(backupPath, JSON.stringify(rows), { mode: 0o600 });
    await fs.chmod(backupPath, 0o600);
    console.log(`Резервная копия: ${backupPath}`);

    const converted = [];
    const failed = [];
    for (const [index, row] of rows.entries()) {
      try {
        const inputPath = path.join(tempDir, `${index}.audio`);
        const outputPath = path.join(tempDir, `${index}.m4a`);
        await fs.writeFile(inputPath, parseDataUrl(row.media_data_url));
        await runFfmpeg(inputPath, outputPath);
        const output = await fs.readFile(outputPath);
        const dataUrl = `data:audio/mp4;base64,${output.toString('base64')}`;
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
      console.log(`Проверка завершена: ${converted.length} записей готовы.`);
    } else if (converted.length > 0) {
      await connection.beginTransaction();
      try {
        for (const item of converted) {
          await connection.execute(
            `UPDATE messages
                SET media_data_url = ?, media_mime_type = 'audio/mp4'
              WHERE id = ? AND media_kind = 'voice'`,
            [item.dataUrl, item.id]
          );
        }
        await connection.commit();
      } catch (error) {
        await connection.rollback();
        throw error;
      }
      console.log(`Готово: ${converted.length} голосовых сохранены в MP4/AAC.`);
    }
    if (failed.length > 0) {
      console.warn(`Не удалось обработать: ${failed.map((item) => item.id).join(', ')}`);
    }
  }
} finally {
  await connection.end();
  await fs.rm(tempDir, { recursive: true, force: true });
}
