Shell скрипт для автоматизации процесса получения VLESS ключей через API мобильного приложения Aeza Security.

В данный момент поддерживается получение ключей **только** для бесплатных локаций.

> [!WARNING]
> Автор скрипта не несёт ответственности за использование скрипта, получение доступа к API, нарушение условий использования или любые правовые последствия, связанные с его применением

- [Зависимости](#зависимости)
- [Рекомендации](#рекомендации)
- [Использование](#использование)
- [Вклад в разработку](#вклад-в-разработку)
- [TODO](#todo)

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

Если вашей системы нет в списке, то установите зависимости самостоятельно или используйте Docker контейнер.

## Рекомендации

#### Почты

Для успешной генерации требуется трастовый email (google, mail.ru, yandex и т.д.), с временными почтами скрипт работать не будет.

Если вы не хотите использовать свою почту, то можете воспользоваться сервисом `Kopeechka`: [реферальная ссылка](https://kopeechka.store/?ref=8331), [обычная](https://kopeechka.store/). 

#### Прокси

Если вы используете трастовую почту, но всё равно получаете ошибку - то стоит использовать прокси. Поддерживается работа как с IPv4, так и с IPv6.

- `proxy.family`: IPv6 прокси от 0.26 руб. [Реферальная ссылка](https://www.proxy.family/?r=218785), [обычная](https://proxy.family/)
- `PROXY6`: IPv6 прокси от 2.88 руб. [Реферальная ссылка](https://proxy6.net/?r=329875), [обычная](https://proxy6.net/)

#### Использование с прокси

Перед использованием скрипта нужно ввести следующие команды:

```bash
export https_proxy=protocol://login:password@ip:port
```

Пример для HTTP прокси с авторизацией:

```bash
export https_proxy=http://Cubr9y:yJS8zL@46.18.219.157:41282
```

Прокси без авторизации:

```bash
export https_proxy=http://46.18.219.157:41282
```

> [!NOTE]
> Поддерживаемые протоколы: `http`, `https`, `socks4`, `socks5`

После использования скрипта стоит отключить прокси:

```bash
unset https_proxy
```

> [!IMPORTANT]
> Один ключ - один IP. Поэтому стоит использовать дешёвые IPv6 прокси

## Использование

Скрипт можно запустить на Linux сервере с поддерживаемой операционной системой, в Docker контейнере, либо использовать временные серверы:

- https://h2.nexus/cli (выбрать Linux)
- https://terminator.aeza.net/ru/ (выбрать Debian)

В процессе выполнения скрипт будет логгировать все свои действия в файл `log.txt`, а после завершения своей работы создаст директорию `output` с JSON файлом, в котором будут все данные от аккаунта:

- Email
- API токен
- ID устройства
- VLESS ключ
- Локация VLESS ключа

> [!IMPORTANT]
> **API токен** и **ID устройства** потребуются в будущем, когда в скрипт будет добавлено управление аккаунтами

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
./aeza-vless-generator.sh
```

## Вклад в разработку

Если у вас есть идеи для улучшения скрипта, вы нашли баг или хотите предложить новую функциональность - не стесняйтесь создавать [issues](https://github.com/vernette/aeza-vless-generator/issues) или отправлять [pull requests](https://github.com/vernette/aeza-vless-generator/pulls).

## TODO

- [ ] Менеджер аккаунтов
- [x] Поддержка прокси
- [ ] Определение типа аккаунта и получение доступных для него локаций
- [x] Загрузка файла с данными от аккаунта на bashupload.com
- [x] Dockerfile
- [x] Сохранение результатов в файл
