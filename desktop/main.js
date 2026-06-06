const { app, BrowserWindow, ipcMain, Tray, Menu, Notification, nativeImage } = require('electron');
const path = require('path');

let mainWindow = null;
let tray = null;
let isQuitting = false;

const isDev = !app.isPackaged;
const APP_VERSION = '1.0.0';

function createTray() {
  // 创建一个简单的 16x16 图标
  const icon = nativeImage.createEmpty();
  tray = new Tray(icon);
  
  const contextMenu = Menu.buildFromTemplate([
    {
      label: '显示窗口',
      click: () => {
        if (mainWindow) {
          mainWindow.show();
          mainWindow.focus();
        }
      }
    },
    {
      label: '隐藏窗口',
      click: () => {
        if (mainWindow) {
          mainWindow.hide();
        }
      }
    },
    { type: 'separator' },
    {
      label: '退出',
      click: () => {
        isQuitting = true;
        app.quit();
      }
    }
  ]);

  tray.setToolTip('股票分析系统');
  tray.setContextMenu(contextMenu);

  tray.on('double-click', () => {
    if (mainWindow) {
      if (mainWindow.isVisible()) {
        mainWindow.hide();
      } else {
        mainWindow.show();
        mainWindow.focus();
      }
    }
  });
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 900,
    minHeight: 600,
    title: '股票分析系统',
    backgroundColor: '#1a1a2e',
    icon: nativeImage.createEmpty(),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  });

  if (isDev) {
    mainWindow.loadURL('http://localhost:5173');
    mainWindow.webContents.openDevTools({ mode: 'detach' });
  } else {
    mainWindow.loadFile(path.join(__dirname, 'dist', 'index.html'));
  }

  mainWindow.on('close', (event) => {
    if (!isQuitting) {
      event.preventDefault();
      mainWindow.hide();
      
      // Windows 下显示通知
      if (process.platform === 'win32') {
        new Notification({
          title: '股票分析系统',
          body: '应用已最小化到系统托盘，双击托盘图标可重新打开'
        }).show();
      }
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// IPC 处理函数
function setupIPC() {
  ipcMain.handle('get-app-version', () => {
    return APP_VERSION;
  });

  ipcMain.on('show-notification', (event, { title, body }) => {
    if (Notification.isSupported()) {
      const notification = new Notification({ title, body });
      notification.show();
    }
  });

  ipcMain.on('minimize-to-tray', () => {
    if (mainWindow) {
      mainWindow.hide();
    }
  });
}

app.whenReady().then(() => {
  setupIPC();
  createWindow();
  createTray();

  app.on('activate', () => {
    if (mainWindow === null) {
      createWindow();
    } else {
      mainWindow.show();
    }
  });
});

app.on('before-quit', () => {
  isQuitting = true;
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});