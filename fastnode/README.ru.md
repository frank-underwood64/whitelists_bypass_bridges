# FastNode

```
███████╗ █████╗ ███████╗████████╗███╗   ██╗ ██████╗ ██████╗ ███████╗
██╔════╝██╔══██╗██╔════╝╚══██╔══╝████╗  ██║██╔═══██╗██╔══██╗██╔════╝
█████╗  ███████║███████╗   ██║   ██╔██╗ ██║██║   ██║██║  ██║█████╗
██╔══╝  ██╔══██║╚════██║   ██║   ██║╚██╗██║██║   ██║██║  ██║██╔══╝
██║     ██║  ██║███████║   ██║   ██║ ╚████║╚██████╔╝██████╔╝███████╗
╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝
  Инструментарий для нод Remnawave  ·  v1.0.0         by @underwood642
```

Один bash-скрипт с интерактивным меню и CLI: готовит чистый VPS на Ubuntu/Debian под ноду
[Remnawave](https://docs.rw/). BBR и тюнинг ядра, Docker, файрвол, **self-steal** сайт с настоящим сертификатом
Let's Encrypt, compose ноды и команда `doctor`, которая объясняет, почему нода тормозит.

[English version](README.md)

## Что делает

| Шаг | Что происходит |
|---|---|
| **Тюнинг** | BBR + `fq`, разумные TCP-буферы/очереди/keepalive, `nofile=1048576` (система, systemd и Docker). Проверяет, что значения реально применились, и называет файл, который их перебивает |
| **Docker** | Официальный Docker Engine + плагин compose, ротация логов, ulimit `nofile`. Работающие контейнеры не перезапускает |
| **Файрвол** | `ufw`: SSH (определяется сам, вы себя не заблокируете), 80, 443 и порт ноды **только для IP панели**. Не включит `ufw`, если он отрежет другие публичные сервисы, пока вы не разрешите |
| **Self-steal** | nginx на `127.0.0.1:8443` с настоящим сертификатом вашего домена: `dest` Reality - ваш собственный сайт. Страница-заглушка **генерируется при каждой установке** (4 шаблона, случайные название, цвет, favicon), поэтому у нод нет общего отпечатка. Свой сайт: `--site-dir` |
| **Нода** | compose в `/opt/remnanode` (`network_mode: host`, ulimits) и `.env`; либо compose из панели через `--compose-file`. Уже настроенную ноду не трогает |
| **Doctor** | ~30 проверок: BBR, расхождения sysctl, лимиты контейнера, время, порты, файрвол, TLS 1.3/h2/X25519 у dest, срок сертификата, Reality fallback, выход по IPv4/IPv6, задержка DNS, MTU, ретрансмиты TCP |

Всё идемпотентно: запускайте повторно сколько нужно. Перезаписываемые файлы сохраняются в `/var/backups/fastnode/<время>/`.

## Быстрый старт

1. Создайте **A-запись** домена на IP сервера (*DNS only*, без проксирования Cloudflare).
2. Если у хостера есть внешний файрвол / security group - откройте там **80** и **443**.
3. Создайте ноду в панели Remnawave и скопируйте её `SECRET_KEY`.

```bash
curl -fsSL https://raw.githubusercontent.com/frank-underwood64/whitelists_bypass_bridges/main/fastnode/fastnode.sh -o fastnode.sh
less fastnode.sh              # скрипт работает от root - сначала прочитайте
sudo bash fastnode.sh         # откроется меню
```

Без меню:

```bash
echo 'ВАШ_SECRET_KEY' > /root/node.key && chmod 600 /root/node.key
sudo bash fastnode.sh install \
  --domain node1.example.com --email you@example.com \
  --panel-ip 203.0.113.5 --secret-key-file /root/node.key
```

Посмотреть, что будет сделано, ничего не меняя: добавьте `--dry-run`.

## Команды

```
fastnode                 интерактивное меню
fastnode install         полная установка
fastnode tune            BBR + sysctl + лимиты
fastnode docker          Docker + compose
fastnode firewall        правила ufw
fastnode selfsteal       nginx + сертификат + сайт-заглушка
fastnode node            compose/.env + запуск ноды
fastnode doctor          диагностика (код возврата 1, если что-то упало)
fastnode status          что установлено
fastnode logs            лог без цветов (прикладывайте к issue)
```

Все параметры: `fastnode --help`. После `install` скрипт ставит себя как `/usr/local/bin/fastnode`.
Язык интерфейса берётся из `$LANG` (русский или английский); переключение - в меню (`l`) или `--lang ru|en`.

## После скрипта: настройка в панели

```jsonc
// Config Profile -> Reality-инбаунд (порт 443)
"dest": "127.0.0.1:8443",
"serverNames": ["node1.example.com"],
"xver": 0
// privateKey / shortIds - свои (xray x25519, openssl rand -hex 8)
```

* **Host** этой ноды: `sni = node1.example.com`.
* **Нода**: адрес = IP сервера, порт = `2222` (или ваш `--node-port`).
* Затем `fastnode doctor`. Проверка *Reality fallback* подтверждает, что посторонние на `:443` получают вашу заглушку.

## Статус

v1.0.0. Проверено на Ubuntu 24.04: интерактивное меню и мастер (настоящий pty), `doctor`, `--dry-run`, валидация параметров
и весь путь self-steal (генерация сайтов, конфиг nginx, TLS 1.3 / h2 / X25519 на loopback-dest,
идемпотентные повторные запуски, бэкапы). Шаги тюнинга, файрвола и установки Docker переиспользуют логику прежнего скрипта,
работавшего на боевых серверах, но в этой версии целиком ещё не прогонялись. Если заметите что-то странное - напишите в issue.

## Платформы

| ОС | Статус |
|---|---|
| Ubuntu 24.04 LTS и новее, Debian 12 и новее | поддерживаются; эталонная платформа - 24.04 |
| Более старые Ubuntu / Debian | работает с предупреждением |
| Другие дистрибутивы на apt | работает с предупреждением (не проверялось) |
| Без `apt` / systemd | отказ, пока нет `--force-os` |

Контейнеры (LXC/OpenVZ) используют ядро хостера: sysctl-тюнинг, включая BBR, там может не примениться. Скрипт и `doctor` об этом сообщат.

## Безопасность и прозрачность

* **Какие файлы пишет:** `/etc/sysctl.d/99-zz-fastnode.conf`, `/etc/modules-load.d/fastnode-bbr.conf`,
  `/etc/security/limits.d/99-fastnode.conf`, `/etc/systemd/system.conf.d/99-fastnode.conf`,
  `/etc/docker/daemon.json` (только если его нет), правила `ufw` (с комментарием `FastNode: ...`),
  `/etc/nginx/sites-available/fastnode`, `/var/www/fastnode`, `/opt/remnanode/*`,
  `/etc/fastnode/fastnode.conf` (только настройки, **без секретов**), `/var/log/fastnode.log`.
* **Не трогает** настройки SSH, пользователей, другие сайты nginx и существующий `daemon.json`.
* **Секреты:** `SECRET_KEY` берётся из файла, переменной `FASTNODE_SECRET_KEY` или скрытого ввода и пишется только в `/opt/remnanode/.env` (права 600). `--secret-key` работает, но предупреждает: ключ окажется в истории shell.
* **Сетевые обращения:** apt, `get.docker.com`, Let's Encrypt, `api.ipify.org` / `ifconfig.me` (публичный IP), `1.1.1.1` (проверка DNS). `doctor` дополнительно пингует `1.1.1.1` и обращается к `api64.ipify.org`.
* Скрипт меняет файрвол, ядро и сетевые настройки той машины, где запущен. Используйте его на своих серверах, в рамках правил хостера и местного законодательства. Прочитайте [лицензию](LICENSE): гарантий нет.

## Участие

Откройте issue с выводом `fastnode doctor` и `fastnode logs`. Pull request'ы приветствуются; CI запускает `shellcheck`.

## Лицензия

[MIT](LICENSE) © 2026 @underwood642
