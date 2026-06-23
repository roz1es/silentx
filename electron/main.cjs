const { app, BrowserWindow, dialog } = require('electron');
const net = require('node:net');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { autoUpdater } = require('electron-updater');

const isDev = process.env.ELECTRON_DEV === '1';
const serverPort = Number(process.env.PORT) || 3002;
const serverHost = '127.0.0.1';
const serverUrl = `http://${serverHost}:${serverPort}`;
const devClientUrl = process.env.ELECTRON_START_URL || 'http://127.0.0.1:5173';
const remoteUrl = process.env.ELECTRON_REMOTE_URL || '';
const autoUpdateUrl = process.env.ELECTRON_AUTOUPDATE_URL || '';

async function waitForTcpReady(host, port, timeoutMs = 15000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const ok = await new Promise((resolve) => {
      const socket = net.createConnection({ host, port }, () => {
        socket.end();
        resolve(true);
      });
      socket.setTimeout(900);
      socket.on('timeout', () => {
        socket.destroy();
        resolve(false);
      });
      socket.on('error', () => resolve(false));
    });
    if (ok) return;
    await new Promise((r) => setTimeout(r, 180));
  }
  throw new Error(`Server is not ready on ${host}:${port}`);
}

async function startServerForProduction() {
  if (remoteUrl) return;
  if (isDev) return;
  const rootDir = path.resolve(__dirname, '..');
  const serverEntry = path.join(rootDir, 'server', 'dist', 'index.js');
  process.env.NODE_ENV = 'production';
  process.env.HOST = serverHost;
  process.env.PORT = String(serverPort);
  await import(pathToFileURL(serverEntry).href);
  await waitForTcpReady(serverHost, serverPort);
}

function createWindow(targetUrl) {
  const win = new BrowserWindow({
    width: 1380,
    height: 860,
    minWidth: 1120,
    minHeight: 700,
    backgroundColor: '#0b1220',
    autoHideMenuBar: true,
    webPreferences: {
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  win.loadURL(targetUrl);
  return win;
}

function setupAutoUpdates(win) {
  if (isDev) return;
  if (process.env.DISABLE_AUTO_UPDATE === '1') return;

  if (autoUpdateUrl) {
    autoUpdater.setFeedURL({
      provider: 'generic',
      url: autoUpdateUrl,
    });
  }

  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;

  autoUpdater.on('error', (err) => {
    console.warn('[updater] error:', err?.message ?? err);
  });

  autoUpdater.on('update-downloaded', async () => {
    const result = await dialog.showMessageBox(win, {
      type: 'info',
      buttons: ['Перезапустить сейчас', 'Позже'],
      defaultId: 0,
      cancelId: 1,
      title: 'Обновление готово',
      message: 'Скачана новая версия БренксЧат.',
      detail: 'Приложение перезапустится для установки обновления.',
    });
    if (result.response === 0) {
      autoUpdater.quitAndInstall();
    }
  });

  // Сразу при старте и далее периодически.
  autoUpdater.checkForUpdates().catch(() => {});
  setInterval(() => {
    autoUpdater.checkForUpdates().catch(() => {});
  }, 30 * 60 * 1000);
}

app.whenReady()
  .then(async () => {
    const targetUrl = isDev ? devClientUrl : remoteUrl || serverUrl;
    if (!isDev) await startServerForProduction();
    const win = createWindow(targetUrl);
    setupAutoUpdates(win);
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        const w = createWindow(targetUrl);
        setupAutoUpdates(w);
      }
    });
  })
  .catch((err) => {
    console.error('[electron] startup failed', err);
    app.quit();
  });

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
