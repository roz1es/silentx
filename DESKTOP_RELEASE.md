# BrenksChat Desktop: release, updates, signing, friend access

## 1) Build installers

- macOS DMG:
  - `npm run desktop:pack:mac`
- Windows EXE (NSIS):
  - `npm run desktop:pack:win`

Artifacts are created in `release/`.

Current tested artifacts:

- `release/BrenksChat-1.0.0-mac.dmg`
- `release/BrenksChat-1.0.0-win.exe` (x64)

## 2) Auto-update (generic provider)

App is configured for `electron-updater` and checks updates on startup and every 30 minutes.

By default, `package.json` points to:

- `https://example.com/brenkschat-updates`

Before release, host update files on your server/CDN and set real URL:

- update `build.publish[0].url` in `package.json`

For runtime override you can use:

- `ELECTRON_AUTOUPDATE_URL=https://your-domain.com/brenkschat-updates`

You need to upload these files from `release/` to the update URL:

- for Windows: `BrenksChat-*.exe`, `latest.yml`, `*.blockmap`
- for macOS: `BrenksChat-*.dmg`, `latest-mac.yml`, `*.blockmap`

## 3) macOS signing + notarization

To produce a properly trusted app on macOS, provide Apple cert + API key env vars:

- `CSC_LINK` (base64 or file path to `.p12`)
- `CSC_KEY_PASSWORD`
- `APPLE_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`
- `APPLE_TEAM_ID`

Then run:

- `npm run desktop:pack:mac`

Without these, DMG builds but remains unsigned.

## 4) Windows code signing

For trusted EXE/installer:

- `WIN_CSC_LINK` (base64 or file path to `.pfx`)
- `WIN_CSC_KEY_PASSWORD`

Then run:

- `npm run desktop:pack:win`

## 5) How your friend can connect and everything works

If you send your friend installer as-is, they get local standalone backend on their own PC.
To work together in one app space, both of you must connect to one shared server.

### Recommended setup

1. Deploy backend + frontend to one public domain, for example:
   - `https://chat.yourdomain.com`
2. Build desktop app that opens this URL:
   - set env before run/build:
   - `ELECTRON_REMOTE_URL=https://chat.yourdomain.com`
3. Optionally disable local bundled server logic by always using remote URL in production builds.

Current app already supports `ELECTRON_REMOTE_URL`. If it is set, Electron opens remote app and does not start local server.

Example for friend-ready build:

- macOS:
  - `ELECTRON_REMOTE_URL=https://chat.yourdomain.com npm run desktop:pack:mac`
- Windows:
  - `ELECTRON_REMOTE_URL=https://chat.yourdomain.com npm run desktop:pack:win`

