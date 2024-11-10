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

Скрипт можно запустить на Linux сервере с поддерживаемой операционной системой, либо использовать временные серверы:

- https://h2.nexus/cli (выбрать Linux)
- https://terminator.aeza.net/ru/ (выбрать Debian)

После завершения своей работы скрипт выведет QR-код для подключения, а также сам VLESS ключ. Будет создана директория `output`, в которой будет создан JSON файл со всеми данными от аккаунта.

#### curl

```bash
curl -s https://raw.githubusercontent.com/vernette/aeza-vless-generator/master/aeza-vless-generator.sh | bash
```

#### wget

```bash
wget -qO- https://raw.githubusercontent.com/vernette/aeza-vless-generator/master/aeza-vless-generator.sh | bash
```

#### Ручной запуск

```bash
git clone https://github.com/vernette/aeza-vless-generator.git
cd aeza-vless-generator
chmod +x aeza-vless-generator.sh
./aeza-vless-generator.sh
```

## TODO

- [ ] Менеджер аккаунтов
- [x] Сохранение результатов в файл
