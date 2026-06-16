process.on('uncaughtException', (err) => {
  require('fs').appendFileSync('C:\\Temp\\nokta-crash.txt', `ERR: ${err.stack}\n`);
});

const { app, BrowserWindow, Tray, Menu, nativeImage, shell, ipcMain, dialog } = require('electron');
const path = require('path');
const { fork } = require('child_process');
const fs = require('fs');
const { autoUpdater } = require('electron-updater');

autoUpdater.autoDownload = true;
autoUpdater.autoInstallOnAppQuit = true;

autoUpdater.on('update-downloaded', () => {
  dialog.showMessageBox({
    type: 'info',
    title: 'Actualización lista',
    message: 'Hay una nueva versión de Nokta Studio lista para instalar. Se instalará al cerrar la app.',
    buttons: ['Instalar ahora', 'Más tarde'],
  }).then(({ response }) => {
    if (response === 0) autoUpdater.quitAndInstall();
  });
});

// Simple persistent store using JSON file
const storePath = path.join(app.getPath('userData'), 'window-state.json');
const store = {
  get: (key, def) => { try { return JSON.parse(fs.readFileSync(storePath,'utf8'))[key] ?? def; } catch { return def; } },
  set: (key, val) => { try { const d = fs.existsSync(storePath) ? JSON.parse(fs.readFileSync(storePath,'utf8')) : {}; d[key]=val; fs.writeFileSync(storePath, JSON.stringify(d)); } catch {} },
};

let mainWindow = null;
let tray = null;
let serverProcess = null;
let serverPort = null;

// ── Start embedded Express server ───────────────────────────
function startServer() {
  return new Promise((resolve, reject) => {
    const serverPath = path.join(__dirname, 'server', 'app.js');
    const envPath = path.join(__dirname, 'server', '.env');

    serverProcess = fork(serverPath, [], {
      env: {
        ...process.env,
        DOTENV_CONFIG_PATH: envPath,
        NODE_ENV: 'production',
      },
      cwd: path.join(__dirname, 'server'),
      silent: false,
    });

    serverProcess.on('message', (msg) => {
      if (msg?.type === 'ready') {
        serverPort = msg.port;
        resolve(serverPort);
      }
    });

    serverProcess.on('error', reject);

    // Fallback timeout — try default port
    setTimeout(() => {
      if (!serverPort) resolve(3000);
    }, 15000);
  });
}

// ── Ventana principal ────────────────────────────────────────
function createWindow(port) {
  const bounds = store.get('windowBounds', { width: 1280, height: 800, x: undefined, y: undefined });

  mainWindow = new BrowserWindow({
    width: bounds.width,
    height: bounds.height,
    x: bounds.x,
    y: bounds.y,
    minWidth: 960,
    minHeight: 640,
    title: 'Nokta Studio',
    icon: path.join(__dirname, 'assets', 'icon.png'),
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
    },
    backgroundColor: '#1C1C1A',
    show: false,
  });

  Menu.setApplicationMenu(null);

  // Clear session cookies on every startup so login is always shown
  // (localStorage with saved credentials is preserved separately)
  mainWindow.webContents.session.clearStorageData({ storages: ['cookies'] }).then(() => {
    mainWindow.loadURL(`http://127.0.0.1:${port}/admin`);
  });

  mainWindow.once('ready-to-show', () => mainWindow.show());

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });

  mainWindow.on('close', (e) => {
    store.set('windowBounds', mainWindow.getBounds());
    e.preventDefault();
    mainWindow.hide();
  });

  mainWindow.on('closed', () => { mainWindow = null; });
}

// ── Bandeja del sistema ──────────────────────────────────────
function createTray(port) {
  const iconPath = path.join(__dirname, 'assets', 'icon.png');
  const icon = nativeImage.createFromPath(iconPath).resize({ width: 16, height: 16 });
  tray = new Tray(icon);

  const show = () => {
    if (mainWindow) { mainWindow.show(); mainWindow.focus(); }
  };

  tray.setToolTip('Nokta Studio');
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Abrir Nokta Studio', click: show },
    { type: 'separator' },
    { label: 'Abrir en navegador', click: () => shell.openExternal(`http://127.0.0.1:${port}/admin`) },
    { type: 'separator' },
    { label: 'Salir', click: () => { app.exit(0); } },
  ]));

  tray.on('double-click', show);
}

// ── Auto-inicio con Windows ──────────────────────────────────
function setAutoLaunch() {
  app.setLoginItemSettings({
    openAtLogin: true,
    name: 'Nokta Studio',
    path: process.execPath,
  });
}

// ── App events ───────────────────────────────────────────────
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) { mainWindow.show(); mainWindow.focus(); }
  });

  app.whenReady().then(async () => {
    const port = await startServer();
    createWindow(port);
    createTray(port);
    setAutoLaunch();
    // Check for updates silently in background (only in packaged app)
    if (app.isPackaged) autoUpdater.checkForUpdatesAndNotify();
  });
}

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') return;
  app.quit();
});

app.on('activate', () => {
  if (!mainWindow && serverPort) createWindow(serverPort);
  else if (mainWindow) { mainWindow.show(); mainWindow.focus(); }
});

app.on('before-quit', () => {
  if (serverProcess) serverProcess.kill();
});

ipcMain.on('quit-app', () => app.exit(0));
