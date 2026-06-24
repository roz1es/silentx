# Самый простой способ залить мобильную версию BrenksChat

Если обычная инструкция не получается, используй этот вариант.

## Что важно понять

GitHub не хранит пустые папки. Если какая-то папка не залилась, но внутри неё нет файлов, это нормально.

Папки сборки тоже не должны заливаться:

```text
build/
.dart_tool/
.gradle/
android/.gradle/
android/app/build/
ios/Pods/
```

Если они не попали в GitHub, это хорошо.

Мобильное приложение нужно класть только сюда:

```text
mobile/
```

## Вариант 1. Через GitHub Desktop

Это самый удобный вариант, если команды в терминале путаются.

1. Установи GitHub Desktop:

   <https://desktop.github.com/>

2. Войди в свой GitHub-аккаунт.

3. Нажми `File` -> `Clone repository`.

4. Выбери репозиторий:

   ```text
   roz1es/silentx
   ```

5. Выбери папку, куда скачать проект.

6. После скачивания нажми сверху `Current Branch`.

7. Нажми `New Branch`.

8. Назови ветку:

   ```text
   mobile/android-app
   ```

9. Открой папку проекта на компьютере.

10. Перенеси свой Android/Flutter проект внутрь папки:

    ```text
    mobile/
    ```

    После переноса должно быть примерно так:

    ```text
    mobile/
    ├── android/
    ├── lib/
    ├── pubspec.yaml
    └── README.md
    ```

11. Вернись в GitHub Desktop.

12. Слева должны появиться изменённые файлы.

13. Внизу в поле `Summary` напиши:

    ```text
    Add Android mobile app
    ```

14. Нажми `Commit to mobile/android-app`.

15. Нажми `Publish branch`.

16. После этого на GitHub появится кнопка `Compare & pull request`.

17. Нажми её и создай Pull Request.

## Вариант 2. Через терминал

```bash
git clone git@github.com:roz1es/silentx.git
cd silentx
git checkout -b mobile/android-app
```

Дальше перенеси Android/Flutter проект в папку `mobile/`.

Потом выполни:

```bash
git status
git add mobile
git commit -m "Add Android mobile app"
git push -u origin mobile/android-app
```

После этого открой Pull Request на GitHub.

## Какая ссылка правильная

Ссылка на ветку обычно выглядит так:

```text
https://github.com/roz1es/silentx/tree/mobile/android-app
```

Это просто просмотр файлов ветки.

Ссылка на создание Pull Request должна выглядеть примерно так:

```text
https://github.com/roz1es/silentx/compare/main...mobile/android-app
```

Если GitHub открыл страницу с `/tree/`, это не ошибка. Просто это страница просмотра ветки, а Pull Request создаётся через кнопку `Compare & pull request`.

## Если половина папок не залилась

Это нормально, если не залились:

```text
build/
.dart_tool/
.gradle/
android/.gradle/
android/app/build/
ios/Pods/
```

Это плохо, если не залились:

```text
mobile/lib/
mobile/android/
mobile/pubspec.yaml
mobile/assets/
```

Тогда нужно проверить:

```bash
git status --ignored
```

Если нужные файлы почему-то игнорируются, нужно написать владельцу проекта и не делать `force push`.

## Самый надёжный запасной вариант

Если GitHub совсем не получается:

1. Удали из мобильного проекта папки `build`, `.dart_tool`, `.gradle`.
2. Сделай архив `.zip`.
3. Передай архив владельцу проекта.
4. Владелец сам добавит проект в папку `mobile/` и зальёт в Git.

