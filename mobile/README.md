# BrenksChat Mobile

Папка зарезервирована под мобильное приложение BrenksChat для Android и iOS.

## Назначение

Здесь должна находиться мобильная версия мессенджера:

```text
mobile/
├── android/      # Android platform runner
├── ios/          # iOS platform runner
├── lib/          # основной код приложения
├── test/         # тесты
├── pubspec.yaml  # зависимости Flutter
└── README.md
```

## Ответственность

Разработчик мобильной версии работает в первую очередь здесь. Он не должен менять `desktop/`, `client/` и `server/` без отдельного согласования.

## Рекомендуемый старт

Если мобильная версия будет на Flutter:

```bash
cd mobile
flutter create . --platforms=android,ios
flutter pub get
```

После создания проекта нужно подключить API `https://silentx.ru`, экран входа, список чатов, экран переписки и Socket.IO.

## Важно

Пока в этой папке нет рабочего приложения. Это место для будущей Android/iOS-разработки.

