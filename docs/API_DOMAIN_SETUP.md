# Отдельный API-домен BrenksChat

Цель: оставить `https://brenkschat.ru` для сайта и веб-клиента, а приложения macOS, Windows, Android и iOS подключать к отдельному серверному адресу `https://api.brenkschat.ru`.

## Что меняется

- `brenkschat.ru` — сайт, веб-версия, страница загрузки установщиков.
- `api.brenkschat.ru` — только backend: REST API `/api/...` и Socket.IO `/socket.io/...`.
- Desktop и mobile по умолчанию используют `BRENKS_API_URL=https://api.brenkschat.ru`.
- Веб-клиент может работать и по-старому через относительные `/api`, и через `VITE_API_URL=https://api.brenkschat.ru`.

## DNS в Reg.ru

В DNS-зоне домена нужно добавить запись:

| Тип | Имя/поддомен | Значение |
| --- | --- | --- |
| A | `api` | `91.229.10.132` |

После сохранения проверить:

```bash
dig +short api.brenkschat.ru A
```

Ожидаемый ответ:

```text
91.229.10.132
```

## SSL-сертификат

После появления DNS-записей нужно выпустить или расширить сертификат:

```bash
ssh -i ~/.ssh/silentx_server -o IdentitiesOnly=yes root@91.229.10.132
certbot --nginx --expand -d brenkschat.ru -d www.brenkschat.ru -d api.brenkschat.ru
nginx -t
systemctl reload nginx
```

Проверка сертификата:

```bash
openssl x509 -in /etc/letsencrypt/live/brenkschat.ru/fullchain.pem -noout -text | grep -A1 "Subject Alternative Name"
```

В списке должен быть `DNS:api.brenkschat.ru`.

## Nginx

Шаблон находится в `deploy/nginx/brenkschat.ru.conf`.

В нем:

- основной блок `brenkschat.ru www.brenkschat.ru` обслуживает сайт и веб-клиент;
- отдельный блок `api.brenkschat.ru` проксирует `/api/` и `/socket.io/` на `127.0.0.1:3002`;
- любые остальные пути на `api.brenkschat.ru` возвращают `404`.

## Сборка клиентов

Desktop:

```bash
cd desktop
flutter build macos --dart-define=BRENKS_API_URL=https://api.brenkschat.ru
flutter build windows --dart-define=BRENKS_API_URL=https://api.brenkschat.ru
```

Mobile:

```bash
cd mobile
flutter build apk --release --dart-define=BRENKS_API_URL=https://api.brenkschat.ru
```

Web:

```bash
cd client
VITE_API_URL=https://api.brenkschat.ru npm run build
```

Если `VITE_API_URL` не задан, веб-клиент продолжит использовать `/api` и `/socket.io` на текущем домене.

## Проверка

```bash
curl -I https://brenkschat.ru
curl -I https://api.brenkschat.ru/api/me
```

Для `/api/me` без авторизации нормальный результат — `401 Unauthorized`. Это значит, что API отвечает.
