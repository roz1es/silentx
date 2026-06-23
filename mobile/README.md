# BrenksChat Mobile

Мобильный клиент BrenksChat для **Android** (и iOS) на Flutter. Дизайн и логика
повторяют веб-версию и desktop-клиент: тёмная/светлая тема BrenksChat, список
чатов, переписка, голосовые, реакции, ответы, вложения, онлайн-статусы и
индикатор печати в реальном времени через Socket.IO.

Приложение **не меняет backend** — оно использует уже существующие HTTP- и
Socket.IO-эндпоинты сервера `https://silentx.ru` (см. раздел «Контракт API»).

## Возможности

- Вход, регистрация и сброс пароля с подтверждением кодом из письма (как в вебе).
- «Запомнить меня», переключение тёмной/светлой темы.
- Список чатов: поиск, непрочитанные, закрепление, mute, онлайн-индикатор.
- Создание личного чата, группы и канала.
- Переписка: текст, фото/файлы, голосовые сообщения, реакции, ответы,
  редактирование/удаление, закреплённое сообщение, индикатор «печатает…».
- Постоянное Socket.IO-соединение через общий `MessengerController`.

## Архитектура

```text
mobile/
├── lib/
│   ├── main.dart                 # бутстрап, авторизация, тема
│   ├── config.dart               # адрес сервера (BRENKS_API_URL)
│   ├── models.dart               # User / Chat / Message (общие с desktop)
│   ├── format.dart               # форматирование времени, превью медиа
│   ├── theme/app_theme.dart      # палитра BrenksChat (тёмная/светлая)
│   ├── services/
│   │   ├── api_client.dart        # REST: вход/регистрация/чаты/сообщения
│   │   ├── socket_service.dart    # Socket.IO события
│   │   ├── auth_store.dart        # токен/тема (shared_preferences)
│   │   ├── audio_message_service.dart  # запись/воспроизведение голосовых
│   │   └── messenger_controller.dart   # состояние мессенджера (ChangeNotifier)
│   ├── screens/
│   │   ├── login_screen.dart      # вход/регистрация/сброс
│   │   ├── chat_list_screen.dart  # список чатов
│   │   └── chat_screen.dart       # экран переписки
│   └── widgets/                   # аватар, плитка чата, пузырь, композер и т.д.
├── test/widget_test.dart
└── pubspec.yaml
```

Модели, тема и сервисы намеренно совпадают с `desktop/lib`, чтобы поведение на
всех клиентах было одинаковым. Навигация адаптирована под телефон: список чатов и
экран переписки — отдельные роуты, а не сплит-вью desktop.

## Требования

- Flutter SDK (stable, тот же, что и для desktop — Dart `>=3.4.0`).
- Android Studio / Android SDK с платформой и эмулятором или устройство с USB-отладкой.

> ⚠️ В среде, где готовился этот коммит, Flutter SDK отсутствовал, поэтому
> `flutter pub get`, `flutter analyze` и `flutter test` **не запускались здесь**.
> Их нужно выполнить локально (шаги ниже). Dart-код написан под линты
> `flutter_lints` и ревизию Flutter stable, совпадающую с desktop.

## Первичная настройка

В папке `mobile/` уже есть `lib/`, `pubspec.yaml`, `test/` и конфиги. Не хватает
только платформенных папок `android/` и `ios/` (их генерирует Flutter — бинарные
файлы вроде gradle-wrapper нельзя хранить в этом коммите).

```bash
cd mobile

# 1. Сгенерировать платформенные раннеры (android/, ios/).
flutter create --org ru.silentx --project-name brenkschat_mobile --platforms=android,ios .

# 2. flutter create может перезаписать наши lib/pubspec шаблоном — вернём свои файлы.
git checkout -- lib pubspec.yaml analysis_options.yaml test README.md

# 3. Установить зависимости.
flutter pub get
```

### Правки Android (нужны один раз, после `flutter create`)

1. **`android/app/src/main/AndroidManifest.xml`** — внутри `<manifest>` (до `<application>`)
   добавьте разрешения для интернета и записи голосовых:

   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   <uses-permission android:name="android.permission.RECORD_AUDIO"/>
   ```

   И задайте подпись приложения у тега `<application ... android:label="БренксЧат">`.

2. **`android/app/build.gradle`** (или `build.gradle.kts`) — пакет `record`
   требует Android 6.0+. Установите:

   ```gradle
   minSdkVersion 23
   ```

> Для iOS в `ios/Runner/Info.plist` добавьте `NSMicrophoneUsageDescription`
> (текст с пояснением, зачем нужен микрофон).

## Запуск и сборка

```bash
flutter run                       # на подключённом устройстве/эмуляторе
flutter build apk --release       # релизный APK
flutter build appbundle --release # бандл для Google Play

flutter analyze                   # статический анализ
flutter test                      # тесты
```

## Конфигурация сервера

По умолчанию используется `https://silentx.ru`. Переопределить можно при сборке:

```bash
flutter run --dart-define=BRENKS_API_URL=https://silentx.ru
```

## Контракт API (используется, без изменений на сервере)

REST (`server/src/index.ts`):

| Метод | Путь | Назначение |
| --- | --- | --- |
| POST | `/api/login` | вход → `{user,token}` либо `{emailCodeRequired,ticket,emailMasked}` |
| POST | `/api/login/confirm` | подтверждение кода входа |
| POST | `/api/register` | регистрация → код на почту |
| POST | `/api/register/confirm` | подтверждение регистрации |
| POST | `/api/password-reset/request` | запрос сброса пароля |
| POST | `/api/password-reset/confirm` | новый пароль по коду |
| GET | `/api/me` | текущий пользователь |
| GET | `/api/chats` | список чатов |
| GET | `/api/chats/:id/messages` | сообщения чата |
| GET | `/api/users/directory` | список людей для нового чата |
| POST | `/api/chats/direct` \| `/group` \| `/channel` | создание чата |
| POST | `/api/chats/:id/mute` \| `/pin-top` \| `/pin-message` \| `/clear` | действия с чатом |
| DELETE | `/api/chats/:id` | удалить чат |

Socket.IO (`server/src/socketHandlers.ts`), путь `/socket.io`, авторизация через
`auth.token`:

- **Входящие от сервера:** `message`, `chat_updated`, `message_deleted`,
  `message_edited`, `chat_deleted`, `messages_cleared`, `presence`, `typing`.
- **Исходящие от клиента:** `join_chat`, `send_message`, `edit_message`,
  `delete_message`, `toggle_reaction`, `typing`, `mark_read`.

## Что пока не реализовано

Аудио-/видеозвонки и push-уведомления — следующий этап (на сервере есть основа:
`/api/calls/ice-servers`, web-push). В этом клиенте они не подключены.
