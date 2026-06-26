# BrenksChat Desktop

Native Flutter desktop client for BrenksChat. This is not an Electron wrapper and does not render the web app. It talks to the existing BrenksChat server through HTTP API and Socket.IO.

## First setup

Install Flutter SDK, then generate platform folders:

```bash
cd desktop
flutter create . --platforms=macos,windows
flutter pub get
```

## Run

```bash
flutter run -d macos --dart-define=BRENKS_API_URL=https://api.brenkschat.ru
```

For local server:

```bash
flutter run -d macos --dart-define=BRENKS_API_URL=http://127.0.0.1:3002
```

## Build

```bash
flutter build macos --dart-define=BRENKS_API_URL=https://api.brenkschat.ru
flutter build windows --dart-define=BRENKS_API_URL=https://api.brenkschat.ru
```

The first MVP includes login, email login confirmation, chat list, message list, text sending, live incoming messages, and chat updates.
