# Lampa

Android-клиент Lampa / Хоттабыч VPN на базе v2rayNG.

## Сборка

1. Установите Android SDK и JDK 17.
2. Создайте локальный `local.properties` с путём `sdk.dir`.
3. Выполните `./gradlew assembleDebug` или `./gradlew assembleRelease`.

Файлы подписи и пароли не хранятся в репозитории. Для публикации релиза настройте release signing локально или через секреты CI.

## Лицензия

Проект наследует условия исходного проекта v2rayNG. См. файл `LICENSE`.
