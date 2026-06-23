#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { spawn } from 'node:child_process';
import { createGzip } from 'node:zlib';

const APP_DIR = '/var/www/brenkschat';
const BACKUP_ROOT = '/root/backups';
const RETENTION_DAYS = 7;

function readEnv(text) {
  const values = {};
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq <= 0) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

function run(command, args, options = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ['ignore', 'inherit', 'inherit'],
      ...options,
    });
    child.once('error', reject);
    child.once('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} exited with code ${code}`));
    });
  });
}

async function sha256(filePath) {
  const hash = createHash('sha256');
  await pipeline(createReadStream(filePath), hash);
  return hash.digest('hex');
}

async function dumpMysql(databaseUrl, outputPath) {
  const db = new URL(databaseUrl);
  const output = createWriteStream(outputPath, { mode: 0o600 });
  const dump = spawn(
    'mysqldump',
    [
      '--single-transaction',
      '--quick',
      '--no-tablespaces',
      '--skip-lock-tables',
      '--set-gtid-purged=OFF',
      '-h',
      db.hostname,
      '-P',
      db.port || '3306',
      '-u',
      decodeURIComponent(db.username),
      decodeURIComponent(db.pathname.replace(/^\//, '')),
    ],
    {
      env: {
        ...process.env,
        MYSQL_PWD: decodeURIComponent(db.password),
      },
      stdio: ['ignore', 'pipe', 'inherit'],
    }
  );
  const completed = new Promise((resolve, reject) => {
    dump.once('error', reject);
    dump.once('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`mysqldump exited with code ${code}`));
    });
  });
  await Promise.all([
    pipeline(dump.stdout, createGzip({ level: 9 }), output),
    completed,
  ]);
}

async function removeExpiredBackups() {
  const entries = await fs.readdir(BACKUP_ROOT, { withFileTypes: true });
  const cutoff = Date.now() - RETENTION_DAYS * 24 * 60 * 60 * 1000;
  for (const entry of entries) {
    if (!entry.isDirectory() || !entry.name.startsWith('daily-')) continue;
    const fullPath = path.join(BACKUP_ROOT, entry.name);
    const stat = await fs.stat(fullPath);
    if (stat.mtimeMs < cutoff) {
      await fs.rm(fullPath, { recursive: true, force: true });
    }
  }
}

async function main() {
  const env = readEnv(
    await fs.readFile(path.join(APP_DIR, 'server', '.env'), 'utf8')
  );
  if (!env.DATABASE_URL) throw new Error('DATABASE_URL is missing');

  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  const finalDir = path.join(BACKUP_ROOT, `daily-${stamp}`);
  const tempDir = `${finalDir}.tmp`;
  await fs.mkdir(BACKUP_ROOT, { recursive: true, mode: 0o700 });
  await fs.rm(tempDir, { recursive: true, force: true });
  await fs.mkdir(tempDir, { mode: 0o700 });

  try {
    const mysqlPath = path.join(tempDir, 'mysql.sql.gz');
    const sourcePath = path.join(tempDir, 'app-source.tar.gz');
    await dumpMysql(env.DATABASE_URL, mysqlPath);
    await run(
      'tar',
      [
        '--exclude=./node_modules',
        '--exclude=./client/dist',
        '--exclude=./server/dist',
        '--exclude=./server/data',
        '--exclude=./.git',
        '-czf',
        sourcePath,
        '.',
      ],
      { cwd: APP_DIR }
    );

    const configFiles = [
      '/etc/nginx/sites-available/silentx.ru',
      '/etc/nginx/.pma_htpasswd',
      '/etc/turnserver.conf',
      '/etc/ssh/sshd_config',
      '/etc/ssh/sshd_config.d/00-brenkschat-hardening.conf',
      '/etc/systemd/system/brenkschat.service',
      '/etc/systemd/system/brenkschat-backup.service',
      '/etc/systemd/system/brenkschat-backup.timer',
      '/etc/phpmyadmin/config.inc.php',
      '/etc/mysql/mysql.conf.d/mysqld.cnf',
    ];
    const configDir = path.join(tempDir, 'config');
    const files = [mysqlPath, sourcePath];
    await fs.mkdir(configDir, { mode: 0o700 });
    for (const file of configFiles) {
      try {
        const destination = path.join(configDir, file.replaceAll('/', '__'));
        await fs.copyFile(file, destination);
        files.push(destination);
      } catch (error) {
        if (error?.code !== 'ENOENT') throw error;
      }
    }

    const checksums = [];
    for (const file of files) {
      const stat = await fs.stat(file);
      if (stat.size === 0) throw new Error(`${path.basename(file)} is empty`);
      checksums.push(`${await sha256(file)}  ${path.relative(tempDir, file)}`);
    }
    await fs.writeFile(
      path.join(tempDir, 'SHA256SUMS'),
      `${checksums.join('\n')}\n`,
      { mode: 0o600 }
    );
    await fs.writeFile(
      path.join(tempDir, 'metadata.json'),
      `${JSON.stringify(
        {
          createdAt: new Date().toISOString(),
          hostname: process.env.HOSTNAME ?? null,
          retentionDays: RETENTION_DAYS,
        },
        null,
        2
      )}\n`,
      { mode: 0o600 }
    );
    await fs.rename(tempDir, finalDir);
    await fs.chmod(finalDir, 0o700);
    await removeExpiredBackups();
    console.log(finalDir);
  } catch (error) {
    await fs.rm(tempDir, { recursive: true, force: true });
    throw error;
  }
}

await main();
