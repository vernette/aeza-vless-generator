Shell скрипт для автоматизации процесса получения VLESS ключей через API мобильного приложения Aeza Security.

В данным момент поддерживается получение ключей **только** для бесплатных локаций.

> [!WARNING]
> Автор скрипта не несёт ответственности за использование скрипта, получение доступа к API, нарушение условий использования или любые правовые последствия, связанные с его применением

## Зависимости

| Название | Назначение               |
| -------- | ------------------------ |
| curl     | Выполнение HTTP запросов |
| jq       | Работа с JSON            |
| qrencode | Генерация QR-кодов       |
| openssl  | Генерация уникальных id  |

В настоящий момент скрипт поддерживает автоматическую установку зависимостей для следующих операционных систем:

- Debian
- Ubuntu
- Arch Linux
- Fedora

Если вашей системы нет в списке, то установите зависимости самостоятельно.

## Использование

Скрипт можно запустить на Linux сервере с поддерживаемой операционной системой, в Docker контейнере, либо использовать временные серверы:

- https://h2.nexus/cli (выбрать Linux)
- https://terminator.aeza.net/ru/ (выбрать Debian)

После завершения своей работы скрипт создаст директорию `output` с JSON файлом со всеми данными от аккаунта.

После этого скрипт выведет QR-код для подключения, VLESS ключ и одноразовую ссылку на скачивание вышеупомянутого JSON файла.

#### curl

```bash
curl -s https://raw.githubusercontent.com/vernette/aeza-vless-generator/master/aeza-vless-generator.sh | bash
```

#### wget

```bash
wget -qO- https://raw.githubusercontent.com/vernette/aeza-vless-generator/master/aeza-vless-generator.sh | bash
```

#### Docker

```bash
git clone https://github.com/vernette/aeza-vless-generator.git
cd aeza-vless-generator
docker build -t aeza-vless-generator .
docker run --rm -it aeza-vless-generator
```

## TODO

- [ ] Менеджер аккаунтов
- [x] Загрузка файла с данными от аккаунта на bashupload.com
- [x] Dockerfile
- [x] Сохранение результатов в файл
