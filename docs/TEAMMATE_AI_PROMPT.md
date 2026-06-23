# Короткий промпт для ИИ второго разработчика

Скопируй этот текст в чат с ИИ друга перед началом работы.

```text
Ты помогаешь разрабатывать BrenksChat — мессенджер с веб-версией, backend, desktop-приложением и будущим mobile-приложением.

Структура проекта:
- client/ — веб-версия: React + TypeScript + Vite.
- server/ — backend: Node.js + Express + Socket.IO, авторизация, чаты, сообщения, почта, сессии, MySQL/хранилище.
- desktop/ — Flutter desktop-приложение для Windows и macOS.
- mobile/ — зона для будущего Android/iOS приложения.
- docs/ — документация команды.
- deploy/ — скрипты и конфиги деплоя.

Правила:
1. Работай только в папках, которые относятся к задаче.
2. Если задача про mobile, не меняй client/, desktop/ и server/ без явного согласования.
3. Если нужно изменить API или Socket.IO события, сначала опиши контракт: endpoint/event, request, response, какие клиенты затронет.
4. Не коммить секреты: .env, пароли, API keys, токены, доступы к VPS.
5. Не коммить node_modules/, build/, dist/, временные архивы и локальные сборки.
6. Не пушь напрямую в main. Работай в отдельной ветке и делай Pull Request.
7. Перед изменениями изучи docs/PROJECT_STRUCTURE.md и docs/TEAM_WORKFLOW.md.

Типовой процесс:
git checkout main
git pull origin main
git checkout -b feature/mobile-login

После работы:
git status
git add <нужные файлы>
git commit -m "Коротко описать изменение"
git push -u origin feature/mobile-login

Для проверки:
- web/server: npm run build
- server tests: npm run test -w server
- desktop/mobile Flutter: flutter analyze и flutter test

Текущая задача: <сюда вставить конкретную задачу>
Ограничения по файлам: <сюда вставить папки, которые можно менять>
Ожидаемый результат: <что должно заработать>
```

