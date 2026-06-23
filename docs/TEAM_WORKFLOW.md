# Как работать вдвоём через GitHub

Документ описывает простой рабочий процесс для BrenksChat, чтобы два разработчика могли параллельно делать веб, desktop и mobile-версии без постоянных конфликтов.

## Главная идея

Ветка `main` должна быть стабильной. В неё нельзя напрямую вносить большие изменения. Каждая задача делается в отдельной ветке и попадает в `main` через Pull Request.

## Роли

Пример распределения:

| Роль | Что делает | Основные папки |
| --- | --- | --- |
| ПК-версия | Windows/macOS приложение, установщик, desktop UI | `desktop/` |
| Мобильная версия | Android/iOS приложение, мобильный UI, push на телефоне | `mobile/` |
| Backend | API, Socket.IO, база данных, авторизация | `server/` |
| Web | Веб-версия, дизайн, модалки, чаты | `client/` |

Если один человек меняет backend, второй должен знать об этом заранее, потому что backend влияет на все клиенты.

## Названия веток

Используйте понятные имена:

```text
feature/desktop-login
feature/desktop-macos-camera
feature/mobile-auth
feature/mobile-chat-list
feature/server-mysql-migration
fix/windows-auth-loading
fix/voice-message-duration
design/profile-modal
```

## Как начать задачу

Перед началом всегда обновить `main`:

```bash
git checkout main
git pull origin main
```

Создать ветку:

```bash
git checkout -b feature/mobile-auth
```

Работать только в файлах своей задачи. Например, если задача про мобильную версию, не трогать `desktop/` и `server/` без необходимости.

## Как сохранить изменения

Проверить, что изменилось:

```bash
git status
```

Добавить файлы:

```bash
git add mobile/
```

Сделать коммит:

```bash
git commit -m "Add mobile login screen"
```

Отправить ветку на GitHub:

```bash
git push -u origin feature/mobile-auth
```

После этого на GitHub создать Pull Request из `feature/mobile-auth` в `main`.

## Как проверять Pull Request

Перед merge нужно проверить:

1. Код относится к заявленной задаче.
2. Нет случайно добавленных `.env`, `node_modules`, `build`, `dist`.
3. Проект запускается локально.
4. Если менялся `server/`, второй разработчик понимает, как это влияет на web/desktop/mobile.
5. Если менялся UI, приложить скриншот.

## Как обновить свою ветку, если main изменился

Если второй разработчик уже смержил свою задачу:

```bash
git checkout main
git pull origin main
git checkout feature/mobile-auth
git merge main
```

Если возник конфликт, его нужно решить вручную, потом:

```bash
git add .
git commit
git push
```

## Что нельзя делать

Нельзя пушить большие изменения сразу в `main`.

Нельзя одновременно делать разные задачи в одной ветке. Например, не стоит в одной ветке чинить звонки, менять дизайн профиля и переносить базу данных.

Нельзя коммитить секреты:

```text
server/.env
RESEND_API_KEY
SMTP_PASS
пароли от VPS
токены GitHub
```

Нельзя удалять чужие изменения через `git reset --hard`, `git checkout -- файл` или замену всей папки проекта архивом.

## Как делить задачи между двумя ИИ

Если у каждого разработчика своя ИИ, лучше давать ей задачу с ограничением по папкам.

Пример для ПК-версии:

```text
Работай только в папке desktop/. Не изменяй client/ и server/.
Задача: исправить загрузку аватарок в macOS/Windows приложении.
После изменений запусти flutter analyze и flutter test.
```

Пример для мобильной версии:

```text
Работай только в папке mobile/. Не изменяй desktop/, client/ и server/.
Задача: сделать экран входа Android/iOS в стиле BrenksChat.
Если нужен новый API endpoint, сначала опиши его, но не меняй server/.
```

Пример для backend:

```text
Работай только в server/. Задача: добавить endpoint поиска пользователя по username.
После изменений опиши контракт API: метод, путь, body, response.
```

## Рекомендуемые задачи на старт

### Разработчик ПК-версии

- Довести `desktop/` до дизайна веб-версии.
- Проверить авторизацию на Windows/macOS.
- Починить загрузку аватарок и медиа.
- Сделать отдельную сборку `.exe` и `.app`.
- Добавить нормальные страницы ошибки подключения.

### Разработчик мобильной версии

- Создать папку `mobile/`.
- Настроить Flutter для Android/iOS.
- Сделать экраны входа и подтверждения почты.
- Сделать список чатов.
- Сделать экран переписки.
- Подключить API и Socket.IO.

### Общие задачи

- Описать API-контракты.
- Решить, какие данные должны храниться в MySQL.
- Вынести общие модели в документацию или общий пакет.
- Настроить issues и labels в GitHub.

## Labels для GitHub Issues

Рекомендуемые метки:

```text
web
server
desktop
mobile
windows
macos
android
ios
bug
design
security
database
calls
media
priority-high
```

