# Деплой BrenksChat на VPS

Деплой выполняется только после того, как изменения попали в ветку `main`.

## Основной порядок

```text
feature branch -> Pull Request -> merge в main -> деплой на VPS
```

Не деплоить незаконченные ветки напрямую на production.

## Что должно быть на сервере

На VPS рабочая папка проекта:

```text
/var/www/brenkschat
```

Внутри должен быть git-репозиторий, подключенный к GitHub:

```bash
cd /var/www/brenkschat
git remote -v
```

Также на сервере должен существовать файл:

```text
/var/www/brenkschat/server/.env
```

Его нельзя коммитить в GitHub. Там хранятся секреты: JWT, SMTP, Resend, MySQL и другие переменные.

## Команда деплоя

После merge в `main` зайти на сервер:

```bash
ssh root@91.229.10.132
```

Запустить:

```bash
cd /var/www/brenkschat
./deploy/production-deploy.sh
```

Скрипт делает:

1. Проверяет, что папка является git-репозиторием.
2. Проверяет, что нет локальных tracked-изменений на сервере.
3. Проверяет наличие `server/.env`.
4. Забирает свежий `main` из GitHub.
5. Устанавливает зависимости через `npm ci`.
6. Собирает `client` и `server` через `npm run build`.
7. Перезапускает systemd-сервис `brenkschat`.
8. Проверяет и перезагружает nginx.

## Запуск с тестами

Если перед деплоем нужно прогнать server-тесты:

```bash
cd /var/www/brenkschat
RUN_TESTS=1 ./deploy/production-deploy.sh
```

## Полезные переменные

Можно переопределить параметры:

```bash
APP_DIR=/var/www/brenkschat \
BRANCH=main \
SERVICE=brenkschat \
RUN_TESTS=1 \
./deploy/production-deploy.sh
```

| Переменная | По умолчанию | Назначение |
| --- | --- | --- |
| `APP_DIR` | `/var/www/brenkschat` | Папка проекта на сервере |
| `BRANCH` | `main` | Ветка для деплоя |
| `REMOTE` | `origin` | Git remote |
| `SERVICE` | `brenkschat` | systemd-сервис backend |
| `RUN_TESTS` | `0` | Запускать ли тесты перед сборкой |
| `SKIP_NGINX_RELOAD` | `0` | Не перезагружать nginx |

## Проверка после деплоя

```bash
systemctl status brenkschat --no-pager
journalctl -u brenkschat -n 80 --no-pager
curl -I https://silentx.ru
```

Если сайт открылся и сервис активен, деплой прошёл успешно.

## Если деплой остановился

Если скрипт пишет, что есть локальные изменения:

```bash
git status
```

Нельзя сразу делать `reset --hard`, пока не понятно, что это за изменения. Нужно проверить, не лежат ли там важные серверные правки.

Если упала сборка:

```bash
npm run build
```

Если упал сервис:

```bash
journalctl -u brenkschat -n 120 --no-pager
```

Если ошибка в nginx:

```bash
nginx -t
```

