# Windows installer для БренксЧат

Это установщик для Flutter desktop-приложения, не Electron-обёртки.

## Требования на Windows

1. Flutter SDK с включённым Windows desktop:
   ```powershell
   flutter config --enable-windows-desktop
   flutter doctor
   ```
2. Visual Studio Build Tools или Visual Studio с компонентом Desktop development with C++.
3. Inno Setup 6:
   https://jrsoftware.org/isdl.php

## Сборка установщика

Из PowerShell:

```powershell
cd "...\messengercursor\desktop\installer\windows"
.\build-installer.ps1 -ApiUrl "https://api.brenkschat.ru"
```

Готовые файлы будут здесь:

```text
desktop\release\windows\BrenksChatSetup-0.1.0.exe
desktop\release\windows\latest.json
```

`latest.json` нужен для автообновления. В нём указана последняя версия и ссылка на `.exe`.

## Как дать установщик другу без команд

### Вариант 1. Просто отправить файл

Отправьте другу:

```text
BrenksChatSetup-0.1.0.exe
```

Друг открывает файл, нажимает `Далее`, после установки запускает `БренксЧат`, вводит логин и пароль.

### Вариант 2. Дать ссылку на скачивание

Загрузите на сервер два файла:

```text
BrenksChatSetup-0.1.0.exe
latest.json
```

Они должны лежать по адресу:

```text
https://brenkschat.ru/desktop/windows/
```

Тогда другу можно дать ссылку:

```text
https://brenkschat.ru/desktop/windows/BrenksChatSetup-0.1.0.exe
```

После установки приложение будет само проверять:

```text
https://brenkschat.ru/desktop/windows/latest.json
```

Если там появится версия новее, БренксЧат покажет окно обновления и скачает новый установщик.

## Как обновлять пользователей

Текущий установщик ставится в:

```text
%LOCALAPPDATA%\Programs\BrenksChat
```

Новый установщик с большей версией можно запускать поверх старого — он обновит файлы приложения.

Автообновление использует manifest:

```text
https://brenkschat.ru/desktop/windows/latest.json
```

Пример лежит в `latest.example.json`. Скрипт `build-installer.ps1` создаёт актуальный `latest.json` автоматически.

## Как выпустить новую версию

1. Поднимите версию в `desktop/pubspec.yaml`, например:
   ```yaml
   version: 0.1.1+2
   ```
2. Соберите новый установщик:
   ```powershell
   .\build-installer.ps1 -ApiUrl "https://api.brenkschat.ru"
   ```
3. Загрузите новый `BrenksChatSetup-0.1.1.exe` и новый `latest.json` на сервер в `/desktop/windows/`.
4. Пользователи увидят обновление при следующем запуске приложения.
