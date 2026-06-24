# Как залить Android-версию BrenksChat в GitHub

Эта инструкция для разработчика мобильной версии. Android/iOS-код должен лежать в папке `mobile/`, чтобы не смешивать его с веб-версией, сервером и desktop-приложением.

## 1. Получить доступ к репозиторию

Владелец репозитория должен добавить тебя в GitHub:

1. Открыть репозиторий `roz1es/silentx`.
2. Перейти в `Settings` -> `Collaborators`.
3. Добавить твой GitHub-аккаунт.
4. Ты принимаешь приглашение на почте или в уведомлениях GitHub.

## 2. Склонировать проект

```bash
git clone git@github.com:roz1es/silentx.git
cd silentx
```

Если SSH не настроен, можно временно использовать HTTPS:

```bash
git clone https://github.com/roz1es/silentx.git
cd silentx
```

## 3. Создать отдельную ветку

Нельзя сразу работать в `main`. Для Android-версии создай свою ветку:

```bash
git checkout -b mobile/android-app
```

## 4. Положить Android-проект в правильную папку

Если мобильное приложение уже создано отдельно, перенеси его содержимое в папку:

```text
mobile/
```

Для Flutter-проекта структура обычно должна выглядеть так:

```text
mobile/
├── android/
├── ios/
├── lib/
├── test/
├── assets/
├── pubspec.yaml
└── README.md
```

Не нужно добавлять в Git временные и тяжёлые папки:

```text
mobile/build/
mobile/.dart_tool/
mobile/.idea/
mobile/.gradle/
mobile/android/.gradle/
```

## 5. Проверить, что добавляется в Git

```bash
git status
```

Если видишь `build/`, `.dart_tool/`, `.gradle/`, их лучше не коммитить. Они должны быть в `.gitignore`.

## 6. Проверить мобильный проект

Для Flutter:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
cd ..
```

Если тестов ещё нет, команда `flutter test` может быть пропущена, но `flutter analyze` желательно выполнить.

## 7. Сделать коммит

```bash
git add mobile
git commit -m "Add Android mobile app"
```

Если менялся `.gitignore` или документация:

```bash
git add .gitignore docs mobile
git commit -m "Add Android mobile app"
```

## 8. Отправить ветку на GitHub

```bash
git push -u origin mobile/android-app
```

## 9. Открыть Pull Request

После push GitHub предложит открыть Pull Request. Нужно выбрать:

```text
base: main
compare: mobile/android-app
```

В описании Pull Request написать:

```text
Добавлена мобильная Android-версия BrenksChat.

Что сделано:
- добавлена структура мобильного приложения;
- подключён экран входа;
- начата интеграция с API https://silentx.ru;
- добавлены основные зависимости.

Проверка:
- flutter pub get;
- flutter analyze.
```

## 10. Как обновлять свою ветку дальше

Перед новой работой подтяни свежий `main`:

```bash
git checkout main
git pull
git checkout mobile/android-app
git merge main
```

После изменений:

```bash
git add mobile
git commit -m "Update Android app"
git push
```

