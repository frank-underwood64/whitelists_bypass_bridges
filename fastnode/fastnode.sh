#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
#  FastNode — Remnawave node bootstrap & tuning toolkit
#  by @underwood642 · MIT License
# ══════════════════════════════════════════════════════════════════════════════
#   sudo ./fastnode.sh                       interactive menu
#   sudo ./fastnode.sh install --domain node1.example.com --email me@example.com \
#                              --panel-ip 203.0.113.5
#   sudo ./fastnode.sh doctor                diagnostics
#   ./fastnode.sh --help                     all commands and options
# ══════════════════════════════════════════════════════════════════════════════

[ -n "${BASH_VERSION:-}" ] || { echo "FastNode: run it with bash:  bash $0" >&2; exit 1; }
if (( BASH_VERSINFO[0] < 4 )); then echo "FastNode needs bash >= 4 (found $BASH_VERSION)" >&2; exit 1; fi

set -Eeuo pipefail

readonly APP="FastNode" AUTHOR="@underwood642" VERSION="1.0.0"
SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"

readonly CONF_DIR=/etc/fastnode CONF=/etc/fastnode/fastnode.conf
readonly LOG=/var/log/fastnode.log BACKUP_ROOT=/var/backups/fastnode
readonly NODE_DIR=/opt/remnanode WEBROOT=/var/www/fastnode
readonly SITE_AVAIL=/etc/nginx/sites-available/fastnode SITE_ENAB=/etc/nginx/sites-enabled/fastnode
readonly SYSCTL_FILE=/etc/sysctl.d/99-zz-fastnode.conf
readonly CLI_PATH=/usr/local/bin/fastnode
RUN_TS="$(date +%Y%m%d-%H%M%S)"; readonly RUN_TS

# ───────────────────────────── settings ─────────────────────────────
DOMAIN="" EMAIL="" PANEL_IP="" NODE_PORT=2222 STEAL_PORT=8443 NODE_TAG=latest NODE_TAG_SET=0 LANG_CODE=en
SECRET_KEY="" SECRET_KEY_FILE="" COMPOSE_FILE="" SITE_DIR="" UFW_ALLOW=""
DRY_RUN=0 ASSUME_YES=0 FORCE_OS=0 FORCE_FW=0 REGEN_SITE=0
SKIP_DNS=0 SKIP_TUNE=0 SKIP_DOCKER=0 SKIP_FW=0 SKIP_SELFSTEAL=0 SKIP_NODE=0
WANT_HELP=0 WANT_VERSION=0 CMD="" APT_UPDATED=0 INSTALL_FLAGS=0
OS_ID="" OS_VER="" OS_NAME="" KERNEL="$(uname -r)"
CONF_KEYS=(DOMAIN EMAIL PANEL_IP NODE_PORT STEAL_PORT NODE_TAG LANG_CODE)

export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

# ───────────────────────────── logo ─────────────────────────────
IFS= read -r -d '' LOGO_UTF <<'LOGO' || true
███████╗ █████╗ ███████╗████████╗███╗   ██╗ ██████╗ ██████╗ ███████╗
██╔════╝██╔══██╗██╔════╝╚══██╔══╝████╗  ██║██╔═══██╗██╔══██╗██╔════╝
█████╗  ███████║███████╗   ██║   ██╔██╗ ██║██║   ██║██║  ██║█████╗
██╔══╝  ██╔══██║╚════██║   ██║   ██║╚██╗██║██║   ██║██║  ██║██╔══╝
██║     ██║  ██║███████║   ██║   ██║ ╚████║╚██████╔╝██████╔╝███████╗
╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝
LOGO
IFS= read -r -d '' LOGO_ASCII <<'LOGO' || true
 _____              _    _   _             _
|  ___|  __ _  ___ | |_ | \ | |  ___    __| |  ___
| |_    / _` |/ __|| __||  \| | / _ \  / _` | / _ \
|  _|  | (_| |\__ \| |_ | |\  || (_) || (_| ||  __/
|_|     \__,_||___/ \__||_| \_| \___/  \__,_| \___|
LOGO

# ───────────────────────────── i18n ─────────────────────────────
declare -A EN=() RU=()
m() { EN[$1]=$2; RU[$1]=$3; }
# shellcheck disable=SC2059
t() { local k=$1 f; shift; if [[ $LANG_CODE == ru ]]; then f=${RU[$k]-$k}; else f=${EN[$k]-$k}; fi; printf -- "$f" "$@"; }

m tagline "Remnawave node toolkit" "Инструментарий для нод Remnawave"
m err_root "Run as root: sudo %s" "Запустите от root: sudo %s"
m err_unexpected "Unexpected error at line %s (exit %s): %s" "Непредвиденная ошибка в строке %s (код %s): %s"
m err_log "Details: %s   (fastnode logs)" "Подробности: %s   (fastnode logs)"
m interrupted "Interrupted" "Прервано"
m err_locked "Another FastNode instance is running" "Уже запущен другой экземпляр FastNode"
m invalid "Invalid value, try again" "Некорректное значение, попробуйте ещё раз"
m no_input "No input (stdin closed)" "Нет ввода (stdin закрыт)"
m press_enter "Press Enter to return to the menu..." "Нажмите Enter, чтобы вернуться в меню..."
m unknown_cmd "Unknown command: %s (see --help)" "Неизвестная команда: %s (см. --help)"
m unknown_opt "Unknown option: %s (see --help)" "Неизвестный параметр: %s (см. --help)"
m opt_needs "Option %s needs a value" "Параметру %s нужно значение"
m bad_val "Invalid value for %s: %s" "Некорректное значение для %s: %s"
m port_clash "STEAL_PORT must differ from 80, 443 and the node port" "Порт self-steal должен отличаться от 80, 443 и порта ноды"
m need_dom_email "--domain and --email are required (or use the menu / wizard)" "Нужны --domain и --email (или запустите меню / мастер)"
m dry_note "DRY-RUN: nothing will be changed" "DRY-RUN: ничего не будет изменено"
m aborted "Aborted" "Отменено"
m confirm_go "Proceed?" "Продолжить?"
m plan "Plan" "План"

m os_unsupported "Unsupported system: %s. FastNode needs an apt-based distribution (Ubuntu / Debian) with systemd. Override with --force-os." "Неподдерживаемая система: %s. FastNode требует дистрибутив на apt (Ubuntu / Debian) с systemd. Обойти: --force-os."
m os_older "%s is older than the tested range (Ubuntu 24.04+ / Debian 12+) - continuing, some steps may need manual attention" "%s старее проверенного диапазона (Ubuntu 24.04+ / Debian 12+) - продолжаю, некоторые шаги могут потребовать ручной правки"
m os_untested "%s is not Ubuntu/Debian but uses apt - untested, continuing" "%s - не Ubuntu/Debian, но использует apt: не проверялось, продолжаю"
m os_forced "Unsupported OS (%s) - continuing because of --force-os" "Неподдерживаемая ОС (%s) - продолжаю из-за --force-os"
m virt_warn "Virtualization '%s': the kernel belongs to the host, sysctl tuning (BBR) may be unavailable" "Виртуализация '%s': ядро принадлежит хостеру, sysctl-тюнинг (BBR) может быть недоступен"
m kernel_old "Kernel %s is too old for BBR (needs 4.9+)" "Ядро %s слишком старое для BBR (нужно 4.9+)"

m s_preflight "Pre-flight checks" "Предварительные проверки"
m s_dns "DNS check for %s" "Проверка DNS для %s"
m s_tune "Kernel tuning: BBR + sysctl" "Тюнинг ядра: BBR + sysctl"
m s_limits "File descriptor limits" "Лимиты файловых дескрипторов"
m s_docker "Docker" "Docker"
m s_fw "Firewall (ufw)" "Файрвол (ufw)"
m s_steal "Self-steal: nginx + certificate for %s" "Self-steal: nginx + сертификат для %s"
m s_site "Stub site" "Сайт-заглушка"
m s_node "Remnawave node (%s)" "Нода Remnawave (%s)"
m s_cli "'fastnode' command" "Команда 'fastnode'"
m s_doctor "Doctor - diagnostics" "Doctor - диагностика"
m s_status "Status" "Статус"

m installing "Installing: %s" "Устанавливаю: %s"
m apt_fail "apt-get update failed. On end-of-life Ubuntu the mirrors are gone (use 24.04 LTS or point apt to old-releases.ubuntu.com). Also check network and DNS." "apt-get update завершился ошибкой. На снятых с поддержки Ubuntu зеркал нет (используйте 24.04 LTS или перенаправьте apt на old-releases.ubuntu.com). Проверьте также сеть и DNS."
m ip_info "Server IP: %s   A record: %s" "IP сервера: %s   A-запись: %s"
m dns_no_a "%s has no A record. Create it (DNS only - no Cloudflare proxy) and wait for propagation, or use --skip-dns-check" "У %s нет A-записи. Создайте её (DNS only, без проксирования Cloudflare) и подождите обновления DNS, либо используйте --skip-dns-check"
m dns_mismatch "A record (%s) does not match this server (%s). If DNS is on Cloudflare, turn the orange cloud off. Override: --skip-dns-check" "A-запись (%s) не совпадает с IP сервера (%s). Если DNS на Cloudflare - выключите оранжевое облако. Обойти: --skip-dns-check"
m dns_noip "Cannot detect this server's public IP (no internet?). Override: --skip-dns-check" "Не удалось определить публичный IP сервера (нет интернета?). Обойти: --skip-dns-check"
m dns_aaaa_bad "%s has an AAAA record (%s) but this server has no matching global IPv6. Let's Encrypt validates over IPv6 first and would fail - remove the AAAA record or fix IPv6. Override: --skip-dns-check" "У %s есть AAAA-запись (%s), но у сервера нет совпадающего глобального IPv6. Let's Encrypt проверяет по IPv6 в первую очередь и упадёт - удалите AAAA-запись или почините IPv6. Обойти: --skip-dns-check"
m dns_ok "DNS looks good" "DNS в порядке"
m bbr_on "BBR active: congestion=%s qdisc=%s" "BBR активен: congestion=%s qdisc=%s"
m bbr_off "BBR did not activate (congestion=%s qdisc=%s) - container virtualization or old kernel?" "BBR не включился (congestion=%s qdisc=%s) - контейнерная виртуализация или старое ядро?"
m sysctl_partial "sysctl --system reported errors (partially applied)" "sysctl --system вернул ошибки (применилось частично)"
m sysctl_diff "%s: wanted '%s', got '%s'%s" "%s: ожидалось '%s', сейчас '%s'%s"
m sysctl_by " (overridden by %s)" " (перекрыто файлом %s)"
m sysctl_more "...and %s more values differ (see: fastnode doctor)" "...и ещё значений, которые отличаются: %s (см.: fastnode doctor)"
m sysctl_ok "All %s sysctl values applied" "Все значения sysctl применены (%s)"
m limits_ok "nofile=1048576 for new sessions and services (the container gets it from compose)" "nofile=1048576 для новых сессий и сервисов (контейнеру лимит задаётся в compose)"
m docker_have "Docker already installed: %s" "Docker уже установлен: %s"
m docker_restart_later "Containers are running - Docker was NOT restarted. The new daemon.json (log rotation, ulimits) applies after: systemctl restart docker" "Контейнеры запущены - Docker НЕ перезапущен. Новый daemon.json (ротация логов, ulimits) применится после: systemctl restart docker"
m docker_keep "/etc/docker/daemon.json exists - left untouched" "/etc/docker/daemon.json уже есть - не трогаю"
m docker_nocompose "docker compose plugin not found" "плагин docker compose не найден"
m fw_ssh "SSH port(s): %s" "SSH-порт(ы): %s"
m fw_panel_ok "Node port %s is open for %s only" "Порт ноды %s открыт только для %s"
m fw_panel_none "--panel-ip is not set: node port %s stays closed and the panel cannot reach the node. Later: ufw allow from <PANEL_IP> to any port %s proto tcp" "--panel-ip не задан: порт ноды %s закрыт, панель не достучится. Позже: ufw allow from <IP_ПАНЕЛИ> to any port %s proto tcp"
m fw_foreign "Other public services are listening: %s. Enabling ufw would block them." "Слушают другие публичные сервисы: %s. Включение ufw их заблокирует."
m fw_skip "Firewall step skipped. Re-run with --ufw-allow PORTS (e.g. 8080/tcp,51820/udp) to allow them, or --force-firewall to block them anyway." "Шаг файрвола пропущен. Запустите снова с --ufw-allow ПОРТЫ (например 8080/tcp,51820/udp), чтобы их разрешить, или --force-firewall, чтобы заблокировать всё равно."
m fw_ask_allow "Allow these ports too?" "Разрешить и эти порты?"
m fw_done "ufw is active: SSH, 80, 443" "ufw активен: SSH, 80, 443"
m fw_host_note "If your hosting provider has an external firewall / security group, open 80 and 443 there too." "Если у хостера есть внешний файрвол / security group - откройте там 80 и 443 тоже."
m port_busy "Port %s is already used by: %s" "Порт %s уже занят: %s"
m port80_busy "Port 80 is used by '%s', not nginx - free it first (Let's Encrypt needs it)" "Порт 80 занят процессом '%s', а не nginx - освободите его (нужен для Let's Encrypt)"
m port443_note "Port 443 is used by '%s' - the node (Xray) needs it" "Порт 443 занят процессом '%s' - он нужен ноде (Xray)"
m nginx_others "Other nginx sites detected - FastNode leaves them and the stock default site alone" "Обнаружены другие сайты nginx - FastNode их и стандартный default не трогает"
m nginx_bad "nginx config test failed (see above)" "Проверка конфига nginx не прошла (см. выше)"
m nginx_start_fail "nginx failed to start" "nginx не запустился"
m nginx_no80 "nginx is not listening on :80" "nginx не слушает :80"
m cert_have "Certificate already present - skipping issue" "Сертификат уже есть - выпуск пропускаю"
m cert_fail "certbot could not issue a certificate. Check: the A record, port 80 reachable from the internet (also at the hosting provider), no Cloudflare proxy, Let's Encrypt rate limits." "certbot не смог выпустить сертификат. Проверьте: A-запись, доступность порта 80 из интернета (в т.ч. у хостера), нет ли проксирования Cloudflare, лимиты Let's Encrypt."
m cert_timer "Auto-renewal timer: %s" "Таймер автопродления: %s"
m site_new "Generated stub site: %s (template '%s')" "Сгенерирован сайт-заглушка: %s (шаблон '%s')"
m site_keep "Stub site already present - kept (use --regen-site for a new one)" "Сайт-заглушка уже есть - оставил (--regen-site сгенерирует новый)"
m site_custom "Copied your site from %s" "Скопирован твой сайт из %s"
m site_bad_dir "--site-dir %s must be a directory with index.html" "--site-dir %s должен быть каталогом с index.html"
m dest_check "dest check (127.0.0.1:%s)" "Проверка dest (127.0.0.1:%s)"
m dest_ok "TLS 1.3 + h2 + X25519 - dest is suitable for Reality" "TLS 1.3 + h2 + X25519 - dest подходит для Reality"
m dest_bad "dest failed the TLS1.3 / h2 / X25519 check (got: %s / %s / %s) - see nginx -t and journalctl -xeu nginx" "dest не прошёл проверку TLS1.3 / h2 / X25519 (получено: %s / %s / %s) - смотрите nginx -t и journalctl -xeu nginx"
m node_keep "Existing %s kept (pass --node-tag or --compose-file to replace it)" "Существующий %s оставлен (чтобы заменить - укажите --node-tag или --compose-file)"
m node_uptodate "Node is up and nothing changed - left running" "Нода работает, изменений нет - не трогаю"
m node_compose "Using the compose file from --compose-file" "Использую compose-файл из --compose-file"
m node_nokey "No SECRET_KEY given - compose is prepared but the node was not started. Put the key into %s/.env (SECRET_KEY=...) and run: cd %s && docker compose up -d" "SECRET_KEY не передан - compose подготовлен, но нода не запущена. Впишите ключ в %s/.env (SECRET_KEY=...) и выполните: cd %s && docker compose up -d"
m node_key_weird "SECRET_KEY does not look like a Remnawave key (too short) - double-check it" "SECRET_KEY не похож на ключ Remnawave (слишком короткий) - перепроверьте"
m node_key_cli "--secret-key stays in shell history and the process list; prefer --secret-key-file, FASTNODE_SECRET_KEY or the hidden prompt" "--secret-key остаётся в истории shell и списке процессов; лучше --secret-key-file, FASTNODE_SECRET_KEY или скрытый ввод"
m node_wait "Waiting for the node to listen on port %s..." "Жду, пока нода начнёт слушать порт %s..."
m node_listen "Node is listening on port %s" "Нода слушает порт %s"
m node_nolisten "Node does not listen on %s yet - check: docker logs remnanode" "Нода пока не слушает %s - проверьте: docker logs remnanode"
m node_need_docker "Docker is not installed - run the Docker step first" "Docker не установлен - сначала выполните шаг Docker"
m cli_ok "Run 'fastnode' any time to open the menu" "Запускайте 'fastnode' в любой момент, чтобы открыть меню"
m cli_skip "Not installed as a command (the script is not a regular file)" "Как команда не установлен (скрипт не является обычным файлом)"

m sum_title "DONE" "ГОТОВО"
m sum_1 "Remaining steps in the Remnawave panel:" "Что осталось в панели Remnawave:"
m sum_2 "1) Config Profile -> Reality inbound (port 443):" "1) Config Profile -> Reality-инбаунд (порт 443):"
m sum_3 "privateKey / shortIds - your own (xray x25519 / openssl rand -hex 8)" "privateKey / shortIds - свои (xray x25519 / openssl rand -hex 8)"
m sum_4 "2) Host of this node:  sni = %s" "2) Host этой ноды:  sni = %s"
m sum_5 "3) Node: address = server IP, port = %s, SECRET_KEY from the node card" "3) Нода: адрес = IP сервера, порт = %s, SECRET_KEY из карточки ноды"
m sum_6 "Check:" "Проверка:"

m q_domain "Domain for self-steal (A record -> this server)" "Домен для self-steal (A-запись -> этот сервер)"
m q_email "E-mail for Let's Encrypt" "E-mail для Let's Encrypt"
m q_panel "Panel server IP (opens the node port for it; empty = skip)" "IP сервера с панелью (ему откроется порт ноды; пусто = пропустить)"
m q_nport "Node port (panel <-> node)" "Порт ноды (панель <-> нода)"
m q_key "SECRET_KEY from the node card (hidden; empty = later)" "SECRET_KEY из карточки ноды (ввод скрыт; пусто = позже)"
m q_lang "Language: 1) English  2) Русский" "Язык: 1) English  2) Русский"

m mn_1 "Full setup wizard" "Полная установка (мастер)"
m mn_1d "tuning + Docker + self-steal + firewall + node" "тюнинг + Docker + self-steal + файрвол + нода"
m mn_2 "Kernel tuning" "Тюнинг ядра"
m mn_2d "BBR + fq, sysctl, file limits" "BBR + fq, sysctl, лимиты файлов"
m mn_3 "Docker" "Docker"
m mn_3d "engine + compose plugin" "движок + плагин compose"
m mn_4 "Self-steal site" "Self-steal сайт"
m mn_4d "nginx + Let's Encrypt + stub on loopback" "nginx + Let's Encrypt + заглушка на loopback"
m mn_5 "Firewall" "Файрвол"
m mn_5d "ufw: SSH, 80, 443, node port for the panel" "ufw: SSH, 80, 443, порт ноды для панели"
m mn_6 "Remnawave node" "Нода Remnawave"
m mn_6d "compose + .env, set SECRET_KEY, start" "compose + .env, ввод SECRET_KEY, запуск"
m mn_7 "Doctor" "Doctor"
m mn_7d "diagnostics: BBR, limits, TLS, IPv6, DNS, MTU..." "диагностика: BBR, лимиты, TLS, IPv6, DNS, MTU..."
m mn_8 "New stub site" "Новый сайт-заглушка"
m mn_8d "regenerate the self-steal page" "перегенерировать страницу self-steal"
m mn_9 "Show log" "Показать лог"
m mn_9d "last 100 lines of the FastNode log" "последние 100 строк лога FastNode"
m mn_l "Language / Язык" "Language / Язык"
m mn_0 "Exit" "Выход"
m mn_choose "Choose" "Выбор"
m mn_bad "No such item" "Нет такого пункта"
m mn_failed "The action failed - details above and in %s" "Действие завершилось ошибкой - детали выше и в %s"

m st_bbr "BBR" "BBR"
m st_docker "Docker" "Docker"
m st_nginx "nginx" "nginx"
m st_ufw "ufw" "ufw"
m st_node "Node" "Нода"
m st_cert "Cert" "Серт"
m st_cfg "Config" "Конфиг"
m st_nodomain "(not set)" "(не задан)"

m d_sys "System" "Система"
m d_tune "Tuning" "Тюнинг"
m d_svc "Services" "Сервисы"
m d_net "Ports and firewall" "Порты и файрвол"
m d_steal "Self-steal" "Self-steal"
m d_egress "Egress and path quality" "Выход в интернет и качество канала"
m d_os "Operating system" "Операционная система"
m d_kernel "Kernel" "Ядро"
m d_virt "Virtualization" "Виртуализация"
m d_time "Clock sync" "Синхронизация времени"
m d_time_ok "synchronized" "синхронизировано"
m d_time_bad "clock is not synchronized - Reality may reject clients (maxTimeDiff)" "часы не синхронизированы - Reality может отклонять клиентов (maxTimeDiff)"
m d_bbr "BBR + fq" "BBR + fq"
m d_bbr_bad "run: fastnode tune" "выполните: fastnode tune"
m d_sysctl "sysctl values" "Значения sysctl"
m d_sysctl_none "FastNode sysctl file not found - run: fastnode tune" "файл sysctl FastNode не найден - выполните: fastnode tune"
m d_sysctl_diff "%s differ from FastNode values (see fastnode tune)" "%s значений отличаются от заданных FastNode (см. fastnode tune)"
m d_nofile "nofile limit" "Лимит nofile"
m d_nofile_ctr "container: %s, shell: %s" "контейнер: %s, shell: %s"
m d_docker "Docker engine" "Docker"
m d_docker_bad "not installed or not running" "не установлен или не запущен"
m d_node "Node container" "Контейнер ноды"
m d_node_bad "container 'remnanode' is not running" "контейнер 'remnanode' не запущен"
m d_node_loop "restarted %s times - check SECRET_KEY and docker logs remnanode" "перезапускался %s раз - проверьте SECRET_KEY и docker logs remnanode"
m d_node_errs "%s error lines in the last 15 min (docker logs remnanode)" "%s строк с ошибками за 15 мин (docker logs remnanode)"
m d_nginx "nginx" "nginx"
m d_timer "certbot renew timer" "Таймер продления certbot"
m d_chrony "chrony" "chrony"
m d_chrony_alt "not running, but the clock is synced by another service" "не запущен, но время синхронизирует другой сервис"
m d_p443 "Port 443" "Порт 443"
m d_p443_none "nothing listens - node not started or profile not applied" "никто не слушает - нода не запущена или профиль не применён"
m d_p443_nginx "owned by nginx - Xray is not on 443" "занят nginx - Xray не на 443"
m d_pnode "Node port %s" "Порт ноды %s"
m d_psteal "Self-steal port %s" "Порт self-steal %s"
m d_ufw "ufw" "ufw"
m d_ufw_off "inactive - run: fastnode firewall" "не активен - выполните: fastnode firewall"
m d_ufw_rule "node-port rule" "Правило порта ноды"
m d_ufw_rule_bad "no rule for port %s found" "правило для порта %s не найдено"
m d_nodomain "domain unknown - pass --domain or run the wizard" "домен неизвестен - укажите --domain или запустите мастер"
m d_tls "dest TLS 1.3 + h2 + X25519" "dest: TLS 1.3 + h2 + X25519"
m d_http "stub site answers" "Сайт-заглушка отвечает"
m d_cert "Certificate" "Сертификат"
m d_cert_days "%s days left" "осталось дней: %s"
m d_cert_none "no certificate for %s" "нет сертификата для %s"
m d_fallback "Reality fallback via 443" "Reality fallback через 443"
m d_fallback_ok "unauthenticated visitors get the stub site" "посторонние посетители получают сайт-заглушку"
m d_fallback_bad "got HTTP %s instead of the stub" "получен HTTP %s вместо заглушки"
m d_v4 "IPv4 egress" "Выход по IPv4"
m d_v4_bad "no IPv4 connectivity" "нет связи по IPv4"
m d_v6 "IPv6 egress" "Выход по IPv6"
m d_v6_none "no global IPv6 address (fine)" "глобального IPv6-адреса нет (нормально)"
m d_v6_bad "IPv6 address present but egress is broken - set Xray freedom domainStrategy to UseIPv4 (or disable IPv6); this makes sites load slowly" "IPv6-адрес есть, но выход не работает - поставьте в Xray freedom domainStrategy UseIPv4 (или отключите IPv6); из-за этого сайты грузятся медленно"
m d_dns "DNS resolver latency" "Задержка DNS-резолвера"
m d_dns_slow "slow resolver - set explicit DNS servers in the Xray profile / system" "медленный резолвер - задайте явные DNS в профиле Xray / системе"
m d_mtu "Path MTU" "MTU пути"
m d_mtu_low "path MTU is below 1500 (1400 passes) - tcp_mtu_probing is on, ok" "MTU пути ниже 1500 (1400 проходит) - tcp_mtu_probing включён, нормально"
m d_mtu_unk "ICMP probes blocked - cannot judge" "ICMP-пробы заблокированы - оценить нельзя"
m d_retr "TCP retransmits (since boot)" "Повторные отправки TCP (с момента загрузки)"
m d_retr_high "high loss on the path - consider BBR tuning or another route" "высокие потери на пути - подумайте о другом маршруте/провайдере"
m d_summary "Result" "Итог"
m d_pass "ok" "ок"
m d_warn "warnings" "предупреждения"
m d_fail "failures" "ошибки"

m usage "Usage: fastnode [command] [options]

Commands:
  (none)       interactive menu (when run in a terminal)
  install      full setup: tuning + docker + firewall + self-steal + node
  tune         BBR + fq, sysctl, file limits
  docker       install Docker + compose plugin
  firewall     ufw: SSH, 80, 443, node port from the panel IP only
  selfsteal    nginx + Let's Encrypt + stub site on 127.0.0.1:PORT
  node         write compose/.env and start the Remnawave node
  doctor       diagnostics: BBR, limits, TLS dest, IPv6, DNS, MTU, errors
  status       what is installed
  logs         show the FastNode log
  version      print the version

Options (install and single steps):
  --domain D            self-steal domain (A record -> this server, DNS only)
  --email E             e-mail for Let's Encrypt
  --panel-ip IP         panel server IP/CIDR: node port is opened for it only
  --node-port N         panel <-> node port (default 2222)
  --steal-port N        loopback port of the stub site (default 8443)
  --secret-key-file F   file with the node SECRET_KEY (or env FASTNODE_SECRET_KEY)
  --secret-key K        SECRET_KEY on the command line (visible in history, avoid)
  --node-tag TAG        remnawave/node image tag (default latest)
  --compose-file F      use the compose file copied from the panel
  --site-dir DIR        use your own site (needs index.html) instead of a generated one
  --regen-site          generate a new stub site
  --ufw-allow LIST      extra ports to allow, e.g. 8080/tcp,51820/udp
  --force-firewall      enable ufw even if other public services would be blocked
  --skip-dns-check  --skip-tune  --skip-docker  --skip-firewall
  --skip-selfsteal  --skip-node
  --force-os            run on an unsupported OS
  --dry-run             show what would be done, change nothing
  -y, --yes             do not ask for confirmation
  --lang en|ru          interface language
  -h, --help  /  --version

by %s" "Использование: fastnode [команда] [параметры]

Команды:
  (пусто)      интерактивное меню (в терминале)
  install      полная установка: тюнинг + docker + файрвол + self-steal + нода
  tune         BBR + fq, sysctl, лимиты файлов
  docker       установка Docker + плагин compose
  firewall     ufw: SSH, 80, 443, порт ноды только с IP панели
  selfsteal    nginx + Let's Encrypt + сайт-заглушка на 127.0.0.1:ПОРТ
  node         записать compose/.env и запустить ноду Remnawave
  doctor       диагностика: BBR, лимиты, TLS dest, IPv6, DNS, MTU, ошибки
  status       что установлено
  logs         показать лог FastNode
  version      версия

Параметры (install и отдельные шаги):
  --domain D            домен self-steal (A-запись -> этот сервер, DNS only)
  --email E             e-mail для Let's Encrypt
  --panel-ip IP         IP/CIDR сервера с панелью: порт ноды откроется только ему
  --node-port N         порт панель <-> нода (по умолчанию 2222)
  --steal-port N        loopback-порт сайта-заглушки (по умолчанию 8443)
  --secret-key-file F   файл с SECRET_KEY ноды (или переменная FASTNODE_SECRET_KEY)
  --secret-key K        SECRET_KEY в командной строке (остаётся в истории, лучше не надо)
  --node-tag TAG        тег образа remnawave/node (по умолчанию latest)
  --compose-file F      взять compose-файл, скопированный из панели
  --site-dir DIR        свой сайт (нужен index.html) вместо сгенерированного
  --regen-site          сгенерировать новый сайт-заглушку
  --ufw-allow СПИСОК    дополнительные порты, например 8080/tcp,51820/udp
  --force-firewall      включить ufw, даже если заблокирует другие публичные сервисы
  --skip-dns-check  --skip-tune  --skip-docker  --skip-firewall
  --skip-selfsteal  --skip-node
  --force-os            запуск на неподдерживаемой ОС
  --dry-run             показать, что будет сделано, ничего не менять
  -y, --yes             не спрашивать подтверждения
  --lang en|ru          язык интерфейса
  -h, --help  /  --version

by %s"

# ───────────────────────────── UI ─────────────────────────────
IS_TTY=0; [[ -t 1 ]] && IS_TTY=1
UTF=0 COLS=80 HAS256=0
C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN=""
SYM_ARROW=">" SYM_OK="+" SYM_WARN="!" SYM_ERR="x" SYM_DOT="*" SYM_OFF="o" SYM_MID="-"

setup_ui() {
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) UTF=1 ;; esac
  COLS=${COLUMNS:-0}
  if (( COLS == 0 )); then COLS=$(tput cols 2>/dev/null || echo 80); fi
  if (( UTF )); then
    SYM_ARROW="▸" SYM_OK="✔" SYM_WARN="▲" SYM_ERR="✖" SYM_DOT="●" SYM_OFF="○" SYM_MID="·"
  fi
  if (( IS_TTY )) && [[ -z ${NO_COLOR:-} && ${TERM:-dumb} != dumb ]]; then
    C_RESET=$'\e[0m' C_BOLD=$'\e[1m' C_DIM=$'\e[2m'
    C_RED=$'\e[31m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_CYAN=$'\e[36m'
    if [[ ${TERM:-} == *256color* || -n ${COLORTERM:-} ]]; then HAS256=1; fi
  fi
}

hr() {
  local n=${1:-66} ch="─"
  if (( ! UTF )); then ch="-"; fi
  printf '  %s' "$C_DIM"
  local i; for ((i = 0; i < n; i++)); do printf '%s' "$ch"; done
  printf '%s\n' "$C_RESET"
}

step() { printf '\n%s%s%s%s %s%s\n' "$C_CYAN" "$C_BOLD" "$SYM_ARROW" "$C_RESET" "$C_BOLD$*" "$C_RESET"; }
ok()   { printf '  %s%s%s %s\n' "$C_GREEN" "$SYM_OK" "$C_RESET" "$*"; }
info() { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
warn() { printf '  %s%s%s %s\n' "$C_YELLOW" "$SYM_WARN" "$C_RESET" "$*" >&2; }
die()  { printf '\n  %s%s%s %s\n' "$C_RED" "$SYM_ERR" "$C_RESET" "$*" >&2; exit 1; }

on_err() {
  local rc=$? line=$1 cmd=$2
  trap - ERR
  printf '\n  %s%s%s %s\n' "$C_RED" "$SYM_ERR" "$C_RESET" "$(t err_unexpected "$line" "$rc" "$cmd")" >&2
  printf '    %s\n' "$(t err_log "$LOG")" >&2
}
arm_trap() { trap 'on_err "$LINENO" "$BASH_COMMAND"' ERR; }
arm_trap
trap 'printf "\n"; die "$(t interrupted)"' INT TERM

banner() {
  local -a pal=(51 45 39 33 63 99); local logo line i=0 left right pad W
  if (( UTF && COLS >= 72 )); then logo=$LOGO_UTF
  elif (( ! UTF && COLS >= 56 )); then logo=$LOGO_ASCII
  else logo=""; fi
  if [[ -n $logo ]]; then
    logo=${logo%$'\n'}
    while IFS= read -r line; do
      if (( HAS256 )); then printf '  \e[38;5;%sm%s\e[0m\n' "${pal[i % 6]}" "$line"
      else printf '  %s%s%s\n' "$C_CYAN" "$line" "$C_RESET"; fi
      i=$((i + 1))
    done <<<"$logo"
  else
    printf '  %s%sFastNode%s\n' "$C_CYAN" "$C_BOLD" "$C_RESET"
  fi
  left="$(t tagline)  $SYM_MID  v$VERSION"; right="by $AUTHOR"
  W=66; (( COLS - 4 < W )) && W=$((COLS - 4))
  pad=$((W - $(strlen "$left") - $(strlen "$right"))); (( pad < 1 )) && pad=1
  printf '  %s%s%s%*s%s%s%s\n' "$C_DIM" "$left" "$C_RESET" "$pad" "" "$C_BOLD" "$right" "$C_RESET"
}

have()       { command -v "$1" >/dev/null 2>&1; }
# visible length of a UTF-8 string, independent of the server locale (counts non-continuation bytes)
strlen() { local n; n=$(printf '%s' "$1" | LC_ALL=C sed 's/[\x80-\xbf]//g' | LC_ALL=C wc -c); echo $((n)); }
padr() { local s=$1 n=$2 pad; pad=$((n - $(strlen "$s"))); if (( pad < 0 )); then pad=0; fi; printf '%s%*s' "$s" "$pad" ""; }
svc_active() { systemctl is-active --quiet "$1" 2>/dev/null; }

# ───────────────────────────── helpers ─────────────────────────────
run() {
  if (( DRY_RUN )); then info "[dry-run] $*" >&2; return 0; fi
  "$@"
}

# quiet CMD... : hide the (very noisy) output of apt/docker installers unless the command fails
quiet() {
  local out rc=0
  if (( DRY_RUN )); then info "[dry-run] $*" >&2; return 0; fi
  out=$("$@" 2>&1) || rc=$?
  if (( rc )); then printf '%s\n' "$out" >&2; fi
  return "$rc"
}

backup() {
  local f=$1 d="$BACKUP_ROOT/$RUN_TS"
  if (( DRY_RUN )); then return 0; fi
  mkdir -p "$d$(dirname "$f")"
  cp -a "$f" "$d$f"
}

PUT_CHANGED=0
# put FILE [MODE] < content : write only if changed; back up the old file; honors --dry-run
put() {
  local f=$1 mode=${2:-644} tmp
  tmp=$(mktemp)
  cat >"$tmp"
  if [[ -f $f ]] && cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
  if (( DRY_RUN )); then info "[dry-run] write $f" >&2; rm -f "$tmp"; return 0; fi
  if [[ -f $f ]]; then backup "$f"; fi
  mkdir -p "$(dirname "$f")"
  install -m "$mode" "$tmp" "$f"
  PUT_CHANGED=1
  rm -f "$tmp"
}

apt_update_once() {
  if (( APT_UPDATED )); then return 0; fi
  if ! run apt-get update -qq; then die "$(t apt_fail)"; fi
  APT_UPDATED=1
}

pkg_installed() { [[ $(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true) == "install ok installed" ]]; }

ensure_pkgs() {
  local -a missing=(); local p
  for p in "$@"; do
    if ! pkg_installed "$p"; then missing+=("$p"); fi
  done
  if (( ${#missing[@]} == 0 )); then return 0; fi
  apt_update_once
  info "$(t installing "${missing[*]}")"
  quiet apt-get install -y -qq "${missing[@]}"
}

valid_domain() { [[ $1 =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]; }
valid_email()  { [[ $1 =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; }
valid_port()   { [[ $1 =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }
valid_ipv4() {
  local ip=${1%%/*} o
  [[ $ip =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  for o in "${BASH_REMATCH[@]:1}"; do (( 10#$o <= 255 )) || return 1; done
  if [[ $1 == */* ]]; then [[ ${1#*/} =~ ^[0-9]{1,2}$ ]] && (( 10#${1#*/} <= 32 )) || return 1; fi
  return 0
}
valid_ip()     { valid_ipv4 "$1" || [[ $1 == *:* && $1 =~ ^[0-9A-Fa-f:]+(/[0-9]{1,3})?$ ]]; }
valid_ip_opt() { [[ -z $1 ]] || valid_ip "$1"; }

ask() { # ask VAR "prompt" [default] [validator]
  local __var=$1 __prompt=$2 __def=${3:-} __fn=${4:-} __ans
  while true; do
    if [[ -n $__def ]]; then read -rp "  $__prompt [$__def]: " __ans || die "$(t no_input)"; __ans=${__ans:-$__def}
    else read -rp "  $__prompt: " __ans || die "$(t no_input)"; fi
    if [[ -z $__fn ]] || "$__fn" "$__ans"; then printf -v "$__var" '%s' "$__ans"; return 0; fi
    warn "$(t invalid)"
  done
}

ask_secret() { # ask_secret VAR "prompt"
  local __var=$1 __ans
  read -rsp "  $2: " __ans || die "$(t no_input)"; printf '\n'
  printf -v "$__var" '%s' "$__ans"
}

confirm() { # confirm "question" [y|n default]
  local def=${2:-y} ans hint
  if (( ASSUME_YES )); then return 0; fi
  if [[ $def == y ]]; then hint="[Y/n]"; else hint="[y/N]"; fi
  read -rp "  $1 $hint " ans || die "$(t no_input)"
  ans=${ans:-$def}
  case $ans in [yYдД]*) return 0 ;; *) return 1 ;; esac
}

# ───────────────────────────── config file ─────────────────────────────
load_conf() {
  [[ -r $CONF ]] || return 0
  local k v
  while IFS='=' read -r k v; do
    case " ${CONF_KEYS[*]} " in
      *" $k "*) if [[ $v =~ ^[A-Za-z0-9._:/@+-]*$ ]]; then printf -v "$k" '%s' "$v"; fi ;;
    esac
  done <"$CONF"
}

save_conf() {
  if (( DRY_RUN )); then return 0; fi
  mkdir -p "$CONF_DIR"
  local k
  { for k in "${CONF_KEYS[@]}"; do printf '%s=%s\n' "$k" "${!k:-}"; done; } >"$CONF"
  chmod 600 "$CONF"
}

# ───────────────────────────── system probes ─────────────────────────────
# read a key from /etc/os-release without sourcing it (sourcing clobbers our own VERSION)
osr() { awk -F= -v k="$1" '$1 == k { v = $0; sub(/^[^=]*=/, "", v); gsub(/^["\047]|["\047]$/, "", v); print v }' /etc/os-release 2>/dev/null; }

os_detect() {
  if [[ -r /etc/os-release ]]; then
    OS_ID=$(osr ID); OS_VER=$(osr VERSION_ID); OS_NAME=$(osr PRETTY_NAME)
  fi
}


# ok = Ubuntu >= 24.04 or Debian >= 12 | older = same families, older | other = another apt-based distro | unsupported = no apt
os_status() {
  if ! have apt-get || ! have dpkg; then echo unsupported; return 0; fi
  case $OS_ID in
    ubuntu) if ver_ge "${OS_VER:-0}" 24.04; then echo ok; else echo older; fi ;;
    debian) if ver_ge "${OS_VER:-0}" 12; then echo ok; else echo older; fi ;;
    *) echo other ;;
  esac
}

check_os() {
  os_detect
  case $(os_status) in
    ok) ;;
    older) warn "$(t os_older "$OS_NAME")" ;;
    other) warn "$(t os_untested "$OS_NAME")" ;;
    *) if (( FORCE_OS )); then warn "$(t os_forced "${OS_NAME:-unknown}")"; else die "$(t os_unsupported "${OS_NAME:-unknown}")"; fi ;;
  esac
}

have_ipv6_global() { [[ -n $(ip -6 -o addr show scope global 2>/dev/null || true) ]]; }

port_owner() { # names of processes listening on a TCP port (any address)
  ss -H -tlnp "sport = :$1" 2>/dev/null | sed -nE 's/.*users:\(\("([^"]*)".*/\1/p' | sort -u | tr '\n' ' ' || true
}

public_ports() { # public_ports tcp|udp : listening ports on non-loopback addresses
  local flag=-tln; if [[ $1 == udp ]]; then flag=-uln; fi
  ss -H "$flag" 2>/dev/null | awk '{a=$4; p=a; sub(/.*:/,"",p); h=a; sub(/:[0-9]+$/,"",h);
    if (h ~ /^127\./ || h == "[::1]" || h == "::1") next; print p}' | sort -un || true
}

is_bbr()       { [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true) == bbr ]]; }
node_running() { have docker && [[ $(docker inspect -f '{{.State.Running}}' remnanode 2>/dev/null || true) == true ]]; }
ufw_active()   { have ufw && [[ $(LC_ALL=C ufw status 2>/dev/null || true) == "Status: active"* ]]; }

cert_days() { # days until the certificate of $DOMAIN expires
  local f=/etc/letsencrypt/live/${DOMAIN:-_}/fullchain.pem end
  [[ -n ${DOMAIN:-} && -f $f ]] || return 1
  end=$(openssl x509 -enddate -noout -in "$f" 2>/dev/null | cut -d= -f2) || return 1
  [[ -n $end ]] || return 1
  echo $(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
}

TLS_PROTO="" TLS_ALPN="" TLS_KEY=""
tls_probe() { # tls_probe HOST PORT SNI -> sets TLS_PROTO / TLS_ALPN / TLS_KEY
  local out
  out=$(echo | timeout 8 openssl s_client -connect "$1:$2" -servername "$3" -tls1_3 -alpn h2 2>/dev/null | tr -d '\0' || true)
  TLS_PROTO=""; TLS_ALPN=""; TLS_KEY=""
  if [[ $out == *"TLSv1.3"* ]]; then TLS_PROTO="TLSv1.3"; fi
  TLS_ALPN=$(awk -F': ' '/^ALPN protocol/{print $2; exit}' <<<"$out")
  TLS_KEY=$(awk -F': ' '/Server Temp Key/{print $2; exit}' <<<"$out")
  TLS_KEY=${TLS_KEY%%,*}
}

verify_sysctl() { # verify_sysctl [quiet] -> SYSCTL_TOTAL / SYSCTL_DIFFS
  SYSCTL_TOTAL=0 SYSCTL_DIFFS=0
  [[ -f $SYSCTL_FILE ]] || return 0
  local k v want got by q=${1:-} plain=0 hidden=0
  while IFS='=' read -r k v; do
    k=${k//[[:space:]]/}
    if [[ -z $k || $k == \#* ]]; then continue; fi
    want=$(tr -s '[:space:]' ' ' <<<"$v" | sed 's/^ //;s/ $//')
    got=$(sysctl -n "$k" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//') || got="?"
    SYSCTL_TOTAL=$((SYSCTL_TOTAL + 1))
    if [[ $want != "$got" ]]; then
      SYSCTL_DIFFS=$((SYSCTL_DIFFS + 1))
      if [[ $q != quiet ]]; then
        by=$(grep -lE "^[[:space:]]*${k//./\\.}[[:space:]]*=" /etc/sysctl.d/*.conf /etc/sysctl.conf /usr/lib/sysctl.d/*.conf 2>/dev/null | grep -vF "$SYSCTL_FILE" | tr '\n' ' ' || true)
        if [[ -n $by ]]; then
          warn "$(t sysctl_diff "$k" "$want" "$got" "$(t sysctl_by "${by% }")")"   # a named culprit is always shown
        elif (( plain < 3 )); then
          plain=$((plain + 1)); warn "$(t sysctl_diff "$k" "$want" "$got" "")"
        else
          hidden=$((hidden + 1))
        fi
      fi
    fi
  done <"$SYSCTL_FILE"
  if (( hidden > 0 )); then warn "$(t sysctl_more "$hidden")"; fi
}

# ───────────────────────────── install steps ─────────────────────────────
step_preflight() {
  step "$(t s_preflight)"
  check_os
  ok "$OS_NAME  $SYM_MID  kernel $KERNEL"
}

step_dns() {
  step "$(t s_dns "$DOMAIN")"
  ensure_pkgs curl ca-certificates bind9-dnsutils iproute2
  local my_ip dom_ips aaaa ip bad=0 v6
  my_ip=$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || curl -4 -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)
  dom_ips=$(dig +short A "$DOMAIN" @1.1.1.1 2>/dev/null | grep -E '^[0-9.]+$' || true)
  info "$(t ip_info "${my_ip:-?}" "$(tr '\n' ' ' <<<"${dom_ips:-none}")")"
  if (( DRY_RUN )); then return 0; fi
  [[ -n $dom_ips ]] || die "$(t dns_no_a "$DOMAIN")"
  [[ -n $my_ip ]] || die "$(t dns_noip)"
  while read -r ip; do
    if [[ -n $ip && $ip != "$my_ip" ]]; then bad=1; fi
  done <<<"$dom_ips"
  if (( bad )); then die "$(t dns_mismatch "$(tr '\n' ' ' <<<"$dom_ips")" "$my_ip")"; fi
  aaaa=$(dig +short AAAA "$DOMAIN" @1.1.1.1 2>/dev/null | grep -E '^[0-9a-fA-F:]+$' || true)
  if [[ -n $aaaa ]]; then
    v6=$(ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
    bad=1
    while read -r ip; do
      if [[ -n $ip ]] && grep -qxF "$ip" <<<"$v6"; then bad=0; fi
    done <<<"$aaaa"
    if (( bad )); then die "$(t dns_aaaa_bad "$DOMAIN" "$(tr '\n' ' ' <<<"$aaaa")")"; fi
  fi
  ok "$(t dns_ok)"
}

step_tune() {
  step "$(t s_tune)"
  local kmaj=${KERNEL%%.*} kmin virt
  kmin=${KERNEL#*.}; kmin=${kmin%%.*}
  if [[ $kmaj =~ ^[0-9]+$ && $kmin =~ ^[0-9]+$ ]] && (( kmaj < 4 || (kmaj == 4 && kmin < 9) )); then warn "$(t kernel_old "$KERNEL")"; fi
  virt=$(systemd-detect-virt 2>/dev/null || true)
  case $virt in openvz|lxc|lxc-libvirt|docker|podman) warn "$(t virt_warn "$virt")" ;; esac

  run modprobe tcp_bbr 2>/dev/null || true
  put /etc/modules-load.d/fastnode-bbr.conf 644 <<<"tcp_bbr"
  put "$SYSCTL_FILE" 644 <<'EOF'
# FastNode - kernel tuning for a proxy node. Named 99-zz-* so it loads after other 99-* files.
# BBR + fq (fq provides the pacing BBR needs): the main win
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Latency / stability for long-lived tunnels
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_syncookies = 1

# Buffers: headroom for long paths (BDP of RU<->EU is ~5 MB), no excess
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 131072 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

# Queues
net.core.somaxconn = 8192
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 10240 65535

# Keepalive: drop dead mobile connections sooner
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5

# Kernel-wide file limits
fs.file-max = 1048576
fs.nr_open = 1048576
EOF
  run sysctl --system >/dev/null 2>&1 || warn "$(t sysctl_partial)"
  if (( ! DRY_RUN )); then
    local cc qd
    cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "?")
    qd=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "?")
    if [[ $cc == bbr && $qd == fq ]]; then ok "$(t bbr_on "$cc" "$qd")"; else warn "$(t bbr_off "$cc" "$qd")"; fi
    verify_sysctl
    if (( SYSCTL_DIFFS == 0 )); then ok "$(t sysctl_ok "$SYSCTL_TOTAL")"; fi
  fi

  step "$(t s_limits)"
  put /etc/security/limits.d/99-fastnode.conf 644 <<'EOF'
*    soft nofile 1048576
*    hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
  put /etc/systemd/system.conf.d/99-fastnode.conf 644 <<'EOF'
[Manager]
DefaultLimitNOFILE=1048576
EOF
  run systemctl daemon-reexec || true
  ok "$(t limits_ok)"
}

step_docker() {
  step "$(t s_docker)"
  if have docker; then
    ok "$(t docker_have "$(docker --version)")"
  else
    ensure_pkgs curl ca-certificates
    local tmp; tmp=$(mktemp)
    run curl -fsSL https://get.docker.com -o "$tmp"
    quiet sh "$tmp"
    rm -f "$tmp"
  fi
  if [[ -f /etc/docker/daemon.json ]]; then
    info "$(t docker_keep)"
  else
    put /etc/docker/daemon.json 644 <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "default-ulimits": { "nofile": { "Name": "nofile", "Soft": 1048576, "Hard": 1048576 } }
}
EOF
    if have docker; then
      if [[ -z $(docker ps -q 2>/dev/null || true) ]]; then run systemctl restart docker
      else warn "$(t docker_restart_later)"; fi
    fi
  fi
  run systemctl enable --now docker >/dev/null 2>&1 || true
  if (( ! DRY_RUN )); then
    if docker compose version >/dev/null 2>&1; then ok "$(docker compose version)"; else warn "$(t docker_nocompose)"; fi
  fi
}

step_firewall() {
  step "$(t s_fw)"
  ensure_pkgs ufw iproute2
  local -a ssh_ports=() foreign=(); local p allowed f
  mapfile -t ssh_ports < <(sshd -T 2>/dev/null | awk '$1=="port"{print $2}' || true)
  if [[ -n ${SSH_CONNECTION:-} ]]; then ssh_ports+=("${SSH_CONNECTION##* }"); fi
  if (( ${#ssh_ports[@]} == 0 )); then ssh_ports=(22); fi
  mapfile -t ssh_ports < <(printf '%s\n' "${ssh_ports[@]}" | sort -un)
  info "$(t fw_ssh "${ssh_ports[*]}")"

  allowed=" ${ssh_ports[*]} 80 443 $NODE_PORT "
  # shellcheck disable=SC2086
  for p in ${UFW_ALLOW//,/ }; do allowed+=" ${p%%/*} "; done
  while read -r p; do
    if [[ -n $p && $allowed != *" $p "* ]]; then foreign+=("$p/tcp"); fi
  done < <(public_ports tcp)
  while read -r p; do
    if [[ -n $p && $p != 68 && $p != 546 && $allowed != *" $p "* ]]; then foreign+=("$p/udp"); fi
  done < <(public_ports udp)

  if (( ${#foreign[@]} )) && ! ufw_active && (( ! FORCE_FW )); then
    warn "$(t fw_foreign "${foreign[*]}")"
    if [[ -t 0 ]] && (( ! ASSUME_YES )) && confirm "$(t fw_ask_allow)" n; then
      for f in "${foreign[@]}"; do UFW_ALLOW+=",$f"; done
    else
      warn "$(t fw_skip)"
      return 0
    fi
  fi

  for p in "${ssh_ports[@]}"; do run ufw allow "$p/tcp" comment 'FastNode: SSH' >/dev/null; done
  run ufw allow 80/tcp  comment 'FastNode: ACME + stub site' >/dev/null
  run ufw allow 443/tcp comment 'FastNode: Xray' >/dev/null
  # shellcheck disable=SC2086
  for f in ${UFW_ALLOW//,/ }; do run ufw allow "$f" comment 'FastNode: extra' >/dev/null; done
  if [[ -n $PANEL_IP ]]; then
    run ufw allow from "$PANEL_IP" to any port "$NODE_PORT" proto tcp comment 'FastNode: panel -> node' >/dev/null
    ok "$(t fw_panel_ok "$NODE_PORT" "$PANEL_IP")"
  else
    warn "$(t fw_panel_none "$NODE_PORT" "$NODE_PORT")"
  fi
  run ufw --force enable >/dev/null
  if (( ! DRY_RUN )); then ok "$(t fw_done)"; fi
  warn "$(t fw_host_note)"
}

# ───────────── self-steal: stub site generator ─────────────
pick() { local -a a=("$@"); printf '%s' "${a[RANDOM % ${#a[@]}]}"; }

site_head() {
  cat <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$NAME</title>
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<style>
:root{--a:$ACCENT}
EOF
}

site_studio() {
  site_head
  cat <<EOF
body{margin:0;font:16px/1.6 system-ui,-apple-system,"Segoe UI",sans-serif;color:#222;background:#fafafa}
header{padding:26px 8vw;background:#fff;border-bottom:1px solid #eee;font-weight:600;letter-spacing:.06em;text-transform:uppercase;color:var(--a)}
main{max-width:860px;margin:9vh auto;padding:0 8vw}
h1{font-size:2.3rem;line-height:1.2;margin:0 0 .5em}
.g{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:18px;margin-top:2.4em}
.c{background:#fff;border:1px solid #eee;border-radius:10px;padding:6px 18px}
.c b{color:var(--a)}
footer{padding:30px 8vw;color:#999;font-size:.85rem}
</style></head><body>
<header>$NAME</header>
<main><h1>$H1</h1><p>$P1</p>
<div class="g"><div class="c"><p><b>Identity</b><br>Logos, type and colour systems.</p></div>
<div class="c"><p><b>Editorial</b><br>Books, magazines and long reads.</p></div>
<div class="c"><p><b>Web</b><br>Small, fast, careful websites.</p></div></div></main>
<footer>&copy; $YEAR $NAME</footer>
</body></html>
EOF
}

site_cafe() {
  site_head
  cat <<EOF
body{margin:0;font:17px/1.7 Georgia,"Times New Roman",serif;color:#2b2420;background:#fbf7f2;text-align:center}
header{padding:44px 6vw 10px;font-size:1.5rem;letter-spacing:.12em;text-transform:uppercase;color:var(--a)}
main{max-width:560px;margin:5vh auto;padding:0 6vw}
h1{font-weight:400;font-size:2.1rem;margin:.2em 0 .6em}
table{margin:2em auto;border-collapse:collapse}
td{padding:4px 16px;border-bottom:1px solid #e8dfd3}
footer{padding:30px;color:#9a8f82;font-size:.85rem}
</style></head><body>
<header>$NAME</header>
<main><h1>$H1</h1><p>$P1</p>
<table><tr><td>Mon - Fri</td><td>8:00 - 18:00</td></tr><tr><td>Sat - Sun</td><td>9:00 - 16:00</td></tr></table></main>
<footer>&copy; $YEAR $NAME</footer>
</body></html>
EOF
}

site_consult() {
  site_head
  cat <<EOF
body{margin:0;font:16px/1.65 system-ui,-apple-system,"Segoe UI",sans-serif;color:#1d2530;background:#fff;display:flex;min-height:100vh}
nav{width:220px;background:var(--a);color:#fff;padding:36px 24px;font-weight:600;letter-spacing:.04em}
nav small{display:block;margin-top:2em;font-weight:400;opacity:.8}
main{flex:1;max-width:720px;padding:9vh 7vw}
h1{font-size:2.1rem;line-height:1.25;margin:0 0 .6em}
.k{display:flex;gap:28px;margin-top:2em;color:var(--a)}
.k div{flex:1;border-top:3px solid var(--a);padding-top:8px}
footer{margin-top:5em;color:#8893a0;font-size:.85rem}
@media(max-width:640px){body{display:block}nav{width:auto}}
</style></head><body>
<nav>$NAME<small>Advisory &amp; research</small></nav>
<main><h1>$H1</h1><p>$P1</p>
<div class="k"><div>Strategy</div><div>Operations</div><div>Analytics</div></div>
<footer>&copy; $YEAR $NAME. All rights reserved.</footer></main>
</body></html>
EOF
}

site_journal() {
  site_head
  cat <<EOF
body{margin:0;font:18px/1.75 Georgia,serif;color:#222;background:#fff}
main{max-width:640px;margin:10vh auto;padding:0 6vw}
h1{font-size:1.9rem;margin:0 0 .2em}
.s{color:#888;font:14px system-ui,sans-serif;margin-bottom:2.4em}
article{margin-bottom:1.8em}
article a{color:var(--a);text-decoration:none;font-weight:700}
article span{display:block;color:#999;font:13px system-ui,sans-serif}
footer{margin-top:4em;color:#aaa;font:13px system-ui,sans-serif}
</style></head><body>
<main><h1>$NAME</h1><div class="s">$H1</div>
<article><a href="#">$T1</a><span>$YEAR</span></article>
<article><a href="#">$T2</a><span>$YEAR</span></article>
<article><a href="#">$T3</a><span>$YEAR</span></article>
<footer>&copy; $YEAR $NAME</footer></main>
</body></html>
EOF
}

gen_site() {
  local tpl=$((RANDOM % 4)) a b NAME ACCENT YEAR H1 P1 T1 T2 T3 INITIAL hue kind
  local -a first=(Northlight Alder Fieldnote Marlow Kestrel Oakridge Bluebird Hartwell Juniper Solace Lumen Harbor Willow Atlas Ember Meridian Quill Saffron)
  a=${first[RANDOM % ${#first[@]}]}
  hue=$((RANDOM % 360)); YEAR=$(date +%Y); ACCENT="hsl($hue,55%,38%)"
  case $tpl in
    0) kind=studio;  b=$(pick Studio Atelier Works Collective)
       H1=$(pick "Design that feels like home" "Thoughtful brand and web design" "A small studio with careful hands")
       P1=$(pick "We are a small independent studio working on identity, editorial and web projects. A new portfolio is on its way." "Independent design practice. Selected work will be published here soon.") ;;
    1) kind=cafe;    b=$(pick Coffee Roasters Bakery Kitchen)
       H1=$(pick "Slow mornings, good coffee" "Baked fresh every day" "Neighbourhood coffee since 2014")
       P1=$(pick "Small-batch roasting and a short menu made with seasonal produce. Come by for a cup." "We roast in-house and bake before sunrise. Takeaway and tables available.") ;;
    2) kind=consult; b=$(pick Advisory Partners Consulting Group)
       H1=$(pick "Clear thinking for complex decisions" "Practical advice for growing companies" "Research-led strategy, plainly delivered")
       P1=$(pick "We help mid-sized teams with planning, operations and measurement. Engagements are small, senior and short." "An independent advisory firm. Case studies are available on request.") ;;
    *) kind=journal; b=Journal
       H1=$(pick "Notes on work, travel and books" "Small essays, irregularly" "Things I learned this year")
       P1=""
       T1=$(pick "What I read this winter" "On keeping a notebook" "A week without a phone")
       T2=$(pick "Slow travel, a short guide" "Making coffee at home" "Why I moved to plain text")
       T3=$(pick "Autumn in the mountains" "A small list of good tools" "Letters I never sent") ;;
  esac
  NAME="$a $b"; INITIAL=${a:0:1}
  put "$WEBROOT/index.html" 644 < <("site_$kind")
  put "$WEBROOT/favicon.svg" 644 <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><rect width="32" height="32" rx="8" fill="$ACCENT"/><text x="16" y="22" font-size="18" text-anchor="middle" fill="#fff" font-family="sans-serif">$INITIAL</text></svg>
EOF
  put "$WEBROOT/404.html" 644 <<EOF
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Page not found - $NAME</title><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="font-family:system-ui,sans-serif;max-width:520px;margin:18vh auto;padding:0 6vw;color:#333"><h1>404</h1><p>The page you are looking for does not exist.</p><p><a href="/" style="color:$ACCENT">Back to the front page</a></p></body></html>
EOF
  put "$WEBROOT/robots.txt" 644 <<'EOF'
User-agent: *
Allow: /
EOF
  ok "$(t site_new "$WEBROOT" "$kind")"
}

site_prepare() {
  step "$(t s_site)"
  run mkdir -p "$WEBROOT"
  if [[ -n $SITE_DIR ]]; then
    [[ -f $SITE_DIR/index.html ]] || die "$(t site_bad_dir "$SITE_DIR")"
    run cp -a "$SITE_DIR"/. "$WEBROOT"/
    ok "$(t site_custom "$SITE_DIR")"
  elif [[ ! -f $WEBROOT/index.html ]] || (( REGEN_SITE )); then
    gen_site
  else
    info "$(t site_keep)"
  fi
}

# ───────────── self-steal: nginx ─────────────
V6LINE=""

nginx_version() { nginx -v 2>&1 | sed -nE 's#.*/([0-9]+\.[0-9]+\.[0-9]+).*#\1#p' || true; }
ver_ge() { [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | sed -n 1p) == "$2" ]]; }

nginx_conf_http() {
  cat <<EOF
server {
    listen 80;
$V6LINE
    server_name $DOMAIN;
    root $WEBROOT;
    index index.html;
    location /.well-known/acme-challenge/ { root $WEBROOT; }
    location / { try_files \$uri \$uri/ =404; }
    error_page 404 /404.html;
}
EOF
}

nginx_conf_full() {
  local listen_ssl http2_line=""
  if [[ -n $(nginx_version) ]] && ver_ge "$(nginx_version)" 1.25.1; then
    listen_ssl="listen 127.0.0.1:$STEAL_PORT ssl;"; http2_line="    http2 on;"
  else
    listen_ssl="listen 127.0.0.1:$STEAL_PORT ssl http2;"
  fi
  cat <<EOF
# FastNode: public side (ACME + redirect, like any ordinary website)
server {
    listen 80;
$V6LINE
    server_name $DOMAIN;
    root $WEBROOT;
    location /.well-known/acme-challenge/ { root $WEBROOT; }
    location / { return 301 https://$DOMAIN\$request_uri; }
}

# FastNode: loopback site - the Reality "dest"
server {
    $listen_ssl
$http2_line
    server_name $DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ecdh_curve      X25519:prime256v1;
    ssl_prefer_server_ciphers off;

    root $WEBROOT;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
    error_page 404 /404.html;
}
EOF
}

nginx_apply() {
  if (( DRY_RUN )); then info "[dry-run] nginx -t && reload" >&2; return 0; fi
  local out
  if ! out=$(nginx -t 2>&1); then printf '%s\n' "$out" >&2; die "$(t nginx_bad)"; fi
  if svc_active nginx; then
    systemctl reload nginx
  else
    systemctl enable nginx >/dev/null 2>&1 || true
    if ! systemctl restart nginx; then journalctl -xeu nginx.service --no-pager 2>/dev/null | tail -15 >&2 || true; die "$(t nginx_start_fail)"; fi
  fi
}

nginx_prepare() {
  local others
  others=$(find /etc/nginx/sites-enabled /etc/nginx/conf.d -mindepth 1 -maxdepth 1 \
    ! -name default ! -name fastnode ! -name 00-fastnode-tokens.conf 2>/dev/null | wc -l || true)
  if (( others == 0 )); then
    run rm -f /etc/nginx/sites-enabled/default
  else
    info "$(t nginx_others)"
  fi
  if grep -rqE '^[[:space:]]*server_tokens[[:space:]]' /etc/nginx/nginx.conf /etc/nginx/conf.d/ 2>/dev/null \
     && [[ ! -f /etc/nginx/conf.d/00-fastnode-tokens.conf ]]; then
    :
  elif [[ ! -f /etc/nginx/conf.d/00-fastnode-tokens.conf ]]; then
    put /etc/nginx/conf.d/00-fastnode-tokens.conf 644 <<<"server_tokens off;"
  fi
}

step_selfsteal() {
  [[ -n $DOMAIN && -n $EMAIL ]] || die "$(t need_dom_email)"
  step "$(t s_steal "$DOMAIN")"
  ensure_pkgs nginx certbot openssl curl iproute2
  local o
  o=$(port_owner 80);          if [[ -n $o && $o != *nginx* ]]; then die "$(t port80_busy "${o% }")"; fi
  o=$(port_owner "$STEAL_PORT"); if [[ -n $o && $o != *nginx* ]]; then die "$(t port_busy "$STEAL_PORT" "${o% }")"; fi
  o=$(port_owner 443);         if [[ -n $o && $o != *xray* ]]; then warn "$(t port443_note "${o% }")"; fi

  if have_ipv6_global; then V6LINE="    listen [::]:80;"; fi
  nginx_prepare
  site_prepare

  local cert=/etc/letsencrypt/live/$DOMAIN/fullchain.pem
  if [[ -f $cert ]]; then
    info "$(t cert_have)"
  else
    put "$SITE_AVAIL" 644 < <(nginx_conf_http)
    run ln -sf "$SITE_AVAIL" "$SITE_ENAB"
    nginx_apply
    if (( ! DRY_RUN )); then
      o=$(port_owner 80); [[ $o == *nginx* ]] || die "$(t nginx_no80)"
    fi
    run certbot certonly --webroot -w "$WEBROOT" -d "$DOMAIN" \
      --agree-tos -m "$EMAIL" --no-eff-email --non-interactive || die "$(t cert_fail)"
  fi

  if (( ! DRY_RUN )) || [[ -f $cert ]]; then
    put "$SITE_AVAIL" 644 < <(nginx_conf_full)
  else
    info "[dry-run] write $SITE_AVAIL (full config with loopback :$STEAL_PORT)" >&2
  fi
  run ln -sf "$SITE_AVAIL" "$SITE_ENAB"
  nginx_apply

  put /etc/letsencrypt/renewal-hooks/deploy/fastnode-reload-nginx.sh 755 <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF
  run systemctl enable --now certbot.timer >/dev/null 2>&1 || true
  if (( ! DRY_RUN )); then
    if svc_active certbot.timer; then ok "$(t cert_timer active)"; else warn "$(t cert_timer inactive)"; fi
    step "$(t dest_check "$STEAL_PORT")"
    tls_probe 127.0.0.1 "$STEAL_PORT" "$DOMAIN"
    info "Protocol: ${TLS_PROTO:--} | ALPN: ${TLS_ALPN:--} | Key: ${TLS_KEY:--}"
    if [[ $TLS_PROTO == TLSv1.3 && $TLS_ALPN == h2 && $TLS_KEY == X25519* ]]; then ok "$(t dest_ok)"
    else warn "$(t dest_bad "${TLS_PROTO:--}" "${TLS_ALPN:--}" "${TLS_KEY:--}")"; fi
  fi
}

# ───────────── Remnawave node ─────────────
clean_key() {
  local k=$1
  k=${k#SECRET_KEY=}; k=${k//[$'\r\n\t ']/}; k=${k#[\"\']}; k=${k%[\"\']}
  printf '%s' "$k"
}

resolve_key() { # fills SECRET_KEY from file / env / CLI; prompts only in the interactive flow
  if [[ -n $SECRET_KEY_FILE ]]; then
    [[ -r $SECRET_KEY_FILE ]] || die "$(t bad_val --secret-key-file "$SECRET_KEY_FILE")"
    SECRET_KEY=$(<"$SECRET_KEY_FILE")
  elif [[ -z $SECRET_KEY && -n ${FASTNODE_SECRET_KEY:-} ]]; then
    SECRET_KEY=$FASTNODE_SECRET_KEY
  fi
  if [[ -n $SECRET_KEY ]]; then SECRET_KEY=$(clean_key "$SECRET_KEY"); fi
}

step_node() {
  step "$(t s_node "$NODE_DIR")"
  have docker || { if (( DRY_RUN )); then :; else die "$(t node_need_docker)"; fi; }
  resolve_key
  run mkdir -p "$NODE_DIR"
  PUT_CHANGED=0
  local have_compose=0 keep=0 started=0
  if [[ -f $NODE_DIR/docker-compose.yml ]]; then have_compose=1; fi

  if [[ -n $COMPOSE_FILE ]]; then
    [[ -r $COMPOSE_FILE ]] || die "$(t bad_val --compose-file "$COMPOSE_FILE")"
    put "$NODE_DIR/docker-compose.yml" 600 <"$COMPOSE_FILE"
    info "$(t node_compose)"
  elif (( have_compose && ! NODE_TAG_SET )); then
    keep=1
    info "$(t node_keep "$NODE_DIR/docker-compose.yml")"
  else
    put "$NODE_DIR/docker-compose.yml" 600 <<EOF
services:
  remnanode:
    image: remnawave/node:$NODE_TAG
    container_name: remnanode
    hostname: remnanode
    restart: always
    network_mode: host
    env_file: .env
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
EOF
  fi

  if [[ -n $COMPOSE_FILE ]]; then
    started=1                       # the panel's compose carries its own environment
  elif [[ -n $SECRET_KEY ]]; then
    if (( ${#SECRET_KEY} < 40 )); then warn "$(t node_key_weird)"; fi
    put "$NODE_DIR/.env" 600 <<EOF
NODE_PORT=$NODE_PORT
SECRET_KEY=$SECRET_KEY
EOF
    started=1
  elif (( keep )); then
    started=1                       # existing node setup (its own .env / inline env) - do not touch
  else
    if [[ ! -f $NODE_DIR/.env ]]; then
      put "$NODE_DIR/.env" 600 <<<"NODE_PORT=$NODE_PORT"
    elif (( ! DRY_RUN && ! keep )); then
      if grep -q '^NODE_PORT=' "$NODE_DIR/.env"; then sed -i "s/^NODE_PORT=.*/NODE_PORT=$NODE_PORT/" "$NODE_DIR/.env"; else echo "NODE_PORT=$NODE_PORT" >>"$NODE_DIR/.env"; fi
    fi
    if grep -qE '^SECRET_KEY=.{20,}' "$NODE_DIR/.env" 2>/dev/null; then started=1; fi
  fi

  if (( ! started )); then
    warn "$(t node_nokey "$NODE_DIR" "$NODE_DIR")"
    return 0
  fi
  if (( DRY_RUN )); then info "[dry-run] docker compose pull && up -d (only if something changed)" >&2; return 0; fi

  if (( PUT_CHANGED )) || ! node_running; then
    (cd "$NODE_DIR" && docker compose pull -q && docker compose up -d)
    info "$(t node_wait "$NODE_PORT")"
    local i
    for ((i = 0; i < 20; i++)); do
      if [[ -n $(port_owner "$NODE_PORT") ]]; then break; fi
      sleep 1
    done
    if [[ -n $(port_owner "$NODE_PORT") ]]; then ok "$(t node_listen "$NODE_PORT")"; else warn "$(t node_nolisten "$NODE_PORT")"; fi
  else
    ok "$(t node_uptodate)"
  fi
}

step_cli() {
  step "$(t s_cli)"
  if [[ -f $SELF && $SELF != "$CLI_PATH" ]]; then
    run install -m 755 "$SELF" "$CLI_PATH"
    ok "$(t cli_ok)"
  elif [[ $SELF == "$CLI_PATH" ]]; then
    ok "$(t cli_ok)"
  else
    info "$(t cli_skip)"
  fi
}

print_summary() {
  printf '\n'; hr
  printf '  %s%s%s%s\n\n' "$C_GREEN" "$C_BOLD" "$(t sum_title)" "$C_RESET"
  printf '  %s\n' "$(t sum_1)"
  printf '   %s\n' "$(t sum_2)"
  printf '        "dest": "127.0.0.1:%s",\n        "serverNames": ["%s"],\n        "xver": 0,\n        %s\n' "$STEAL_PORT" "$DOMAIN" "$(t sum_3)"
  printf '   %s\n' "$(t sum_4 "$DOMAIN")"
  printf '   %s\n\n' "$(t sum_5 "$NODE_PORT")"
  printf '  %s\n' "$(t sum_6)"
  printf '    fastnode doctor\n    curl -sI https://%s\n' "$DOMAIN"
  hr
}

do_install() {
  if (( DRY_RUN )); then warn "$(t dry_note)"; fi
  step_preflight
  if (( ! SKIP_SELFSTEAL )) && [[ -z $DOMAIN || -z $EMAIL ]]; then die "$(t need_dom_email)"; fi
  save_conf
  if (( ! SKIP_DNS && ! SKIP_SELFSTEAL )); then step_dns; fi
  if (( ! SKIP_TUNE ));      then step_tune; fi
  if (( ! SKIP_DOCKER ));    then step_docker; fi
  if (( ! SKIP_FW ));        then step_firewall; fi
  if (( ! SKIP_SELFSTEAL )); then step_selfsteal; fi
  if (( ! SKIP_NODE ));      then step_node; fi
  step_cli
  print_summary
}

# ───────────────────────────── doctor ─────────────────────────────
D_PASS=0 D_WARN=0 D_FAIL=0
sect() { printf '\n  %s%s%s\n' "$C_BOLD" "$1" "$C_RESET"; }
chk() { # chk pass|warn|fail|info "name" "detail"
  local sym col
  case $1 in
    pass) sym=$SYM_OK;   col=$C_GREEN;  D_PASS=$((D_PASS + 1)) ;;
    warn) sym=$SYM_WARN; col=$C_YELLOW; D_WARN=$((D_WARN + 1)) ;;
    fail) sym=$SYM_ERR;  col=$C_RED;    D_FAIL=$((D_FAIL + 1)) ;;
    *)    sym=$SYM_MID;  col=$C_DIM ;;
  esac
  printf '  %s%s%s %s %s%s%s\n' "$col" "$sym" "$C_RESET" "$(padr "$2" 32)" "$C_DIM" "${3:-}" "$C_RESET"
}

doctor() {
  D_PASS=0 D_WARN=0 D_FAIL=0
  step "$(t s_doctor)"
  local v o n

  sect "$(t d_sys)"
  os_detect
  case $(os_status) in
    ok)     chk pass "$(t d_os)" "$OS_NAME" ;;
    older)  chk warn "$(t d_os)" "$(t os_older "$OS_NAME")" ;;
    other)  chk warn "$(t d_os)" "$(t os_untested "$OS_NAME")" ;;
    *)      chk fail "$(t d_os)" "$OS_NAME" ;;
  esac
  chk info "$(t d_kernel)" "$KERNEL  $SYM_MID  $(nproc) vCPU  $SYM_MID  $(awk '/MemTotal/{printf "%.1f GB", $2/1048576}' /proc/meminfo)"
  v=$(systemd-detect-virt 2>/dev/null || true)
  case $v in
    openvz|lxc|lxc-libvirt|docker|podman) chk warn "$(t d_virt)" "$(t virt_warn "$v")" ;;
    *) chk pass "$(t d_virt)" "${v:-none}" ;;
  esac
  if [[ $(timedatectl show -p NTPSynchronized --value 2>/dev/null || true) == yes ]]; then chk pass "$(t d_time)" "$(t d_time_ok)"
  else chk warn "$(t d_time)" "$(t d_time_bad)"; fi

  sect "$(t d_tune)"
  if is_bbr && [[ $(sysctl -n net.core.default_qdisc 2>/dev/null || true) == fq ]]; then chk pass "$(t d_bbr)" "bbr + fq"
  else chk fail "$(t d_bbr)" "$(t d_bbr_bad)"; fi
  if [[ -f $SYSCTL_FILE ]]; then
    verify_sysctl quiet
    if (( SYSCTL_DIFFS == 0 )); then chk pass "$(t d_sysctl)" "$SYSCTL_TOTAL / $SYSCTL_TOTAL"
    else chk warn "$(t d_sysctl)" "$(t d_sysctl_diff "$SYSCTL_DIFFS / $SYSCTL_TOTAL")"; fi
  else
    chk warn "$(t d_sysctl)" "$(t d_sysctl_none)"
  fi
  o=$(ulimit -n)
  if node_running; then
    n=$(docker exec remnanode sh -c 'ulimit -n' 2>/dev/null || echo "?")
    if [[ $n =~ ^[0-9]+$ ]] && (( n >= 65536 )); then chk pass "$(t d_nofile)" "$(t d_nofile_ctr "$n" "$o")"
    else chk warn "$(t d_nofile)" "$(t d_nofile_ctr "$n" "$o")"; fi
  else
    chk info "$(t d_nofile)" "shell: $o"
  fi

  sect "$(t d_svc)"
  if have docker && svc_active docker; then chk pass "$(t d_docker)" "$(docker --version | sed 's/Docker version //')"
  else chk fail "$(t d_docker)" "$(t d_docker_bad)"; fi
  if node_running; then
    n=$(docker inspect -f '{{.RestartCount}}' remnanode 2>/dev/null || echo 0)
    if (( n > 3 )); then chk warn "$(t d_node)" "$(t d_node_loop "$n")"; else chk pass "$(t d_node)" "running"; fi
    n=$(docker logs --since 15m remnanode 2>&1 | grep -ciE 'error|panic|fatal' || true)
    if (( n > 0 )); then chk warn "$(t d_node)" "$(t d_node_errs "$n")"; fi
  else
    chk warn "$(t d_node)" "$(t d_node_bad)"
  fi
  if svc_active nginx; then chk pass "$(t d_nginx)" "active"; else chk warn "$(t d_nginx)" "inactive"; fi
  if svc_active certbot.timer; then chk pass "$(t d_timer)" "active"; else chk warn "$(t d_timer)" "inactive"; fi
  if svc_active chrony || svc_active chronyd; then chk pass "$(t d_chrony)" "active"
  elif [[ $(timedatectl show -p NTPSynchronized --value 2>/dev/null || true) == yes ]]; then chk info "$(t d_chrony)" "$(t d_chrony_alt)"
  else chk warn "$(t d_chrony)" "inactive"; fi

  sect "$(t d_net)"
  o=$(port_owner 443)
  if [[ -z $o ]]; then chk warn "$(t d_p443)" "$(t d_p443_none)"
  elif [[ $o == *xray* ]]; then chk pass "$(t d_p443)" "xray"
  elif [[ $o == *nginx* ]]; then chk warn "$(t d_p443)" "$(t d_p443_nginx)"
  else chk fail "$(t d_p443)" "${o% }"; fi
  o=$(port_owner "$NODE_PORT")
  if [[ -n $o ]]; then chk pass "$(t d_pnode "$NODE_PORT")" "${o% }"
  elif node_running; then chk fail "$(t d_pnode "$NODE_PORT")" "not listening"
  else chk info "$(t d_pnode "$NODE_PORT")" "-"; fi
  o=$(port_owner "$STEAL_PORT")
  if [[ $o == *nginx* ]]; then chk pass "$(t d_psteal "$STEAL_PORT")" "nginx"
  elif [[ -z $DOMAIN ]]; then chk info "$(t d_psteal "$STEAL_PORT")" "-"
  else chk fail "$(t d_psteal "$STEAL_PORT")" "${o:-not listening}"; fi
  if ufw_active; then
    chk pass "$(t d_ufw)" "active"
    if [[ $(LC_ALL=C ufw status 2>/dev/null || true) == *"$NODE_PORT/tcp"* ]]; then chk pass "$(t d_ufw_rule)" "$NODE_PORT/tcp"
    else chk warn "$(t d_ufw_rule)" "$(t d_ufw_rule_bad "$NODE_PORT")"; fi
  else
    chk warn "$(t d_ufw)" "$(t d_ufw_off)"
  fi

  sect "$(t d_steal)"
  if [[ -z $DOMAIN ]]; then
    chk info "domain" "$(t d_nodomain)"
  else
    tls_probe 127.0.0.1 "$STEAL_PORT" "$DOMAIN"
    if [[ $TLS_PROTO == TLSv1.3 && $TLS_ALPN == h2 && $TLS_KEY == X25519* ]]; then chk pass "$(t d_tls)" "$TLS_PROTO / $TLS_ALPN / $TLS_KEY"
    else chk fail "$(t d_tls)" "${TLS_PROTO:--} / ${TLS_ALPN:--} / ${TLS_KEY:--}"; fi
    n=$(curl -sk --resolve "$DOMAIN:$STEAL_PORT:127.0.0.1" -o /dev/null -w '%{http_code}' --max-time 6 "https://$DOMAIN:$STEAL_PORT/" 2>/dev/null || true)
    if [[ $n == 200 ]]; then chk pass "$(t d_http)" "HTTP 200"; else chk fail "$(t d_http)" "HTTP ${n:-000}"; fi
    if n=$(cert_days); then
      if (( n > 14 )); then chk pass "$(t d_cert)" "$(t d_cert_days "$n")"
      elif (( n > 0 )); then chk warn "$(t d_cert)" "$(t d_cert_days "$n")"
      else chk fail "$(t d_cert)" "$(t d_cert_days "$n")"; fi
    else
      chk fail "$(t d_cert)" "$(t d_cert_none "$DOMAIN")"
    fi
    if [[ $(port_owner 443) == *xray* ]]; then
      n=$(curl -sk --resolve "$DOMAIN:443:127.0.0.1" -o /dev/null -w '%{http_code}' --max-time 6 "https://$DOMAIN/" 2>/dev/null || true)
      if [[ $n == 200 ]]; then chk pass "$(t d_fallback)" "$(t d_fallback_ok)"; else chk warn "$(t d_fallback)" "$(t d_fallback_bad "${n:-000}")"; fi
    fi
  fi

  sect "$(t d_egress)"
  if curl -4 -fsS --max-time 6 -o /dev/null https://api.ipify.org 2>/dev/null; then chk pass "$(t d_v4)" "ok"; else chk fail "$(t d_v4)" "$(t d_v4_bad)"; fi
  if have_ipv6_global; then
    if curl -6 -fsS --max-time 6 -o /dev/null https://api64.ipify.org 2>/dev/null; then chk pass "$(t d_v6)" "ok"; else chk warn "$(t d_v6)" "$(t d_v6_bad)"; fi
  else
    chk info "$(t d_v6)" "$(t d_v6_none)"
  fi
  local s e total=0 cnt=0 d ms
  for d in google.com cloudflare.com github.com; do
    s=$(date +%s%N); getent ahosts "fn$RANDOM$RANDOM.$d" >/dev/null 2>&1 || true; e=$(date +%s%N)
    total=$((total + (e - s) / 1000000)); cnt=$((cnt + 1))
  done
  ms=$((total / cnt))
  if (( ms > 1500 )); then chk fail "$(t d_dns)" "${ms} ms - $(t d_dns_slow)"
  elif (( ms > 300 )); then chk warn "$(t d_dns)" "${ms} ms - $(t d_dns_slow)"
  else chk pass "$(t d_dns)" "${ms} ms"; fi
  if ping -c 2 -W 2 -M "do" -s 1472 1.1.1.1 >/dev/null 2>&1; then chk pass "$(t d_mtu)" "1500"
  elif ping -c 2 -W 2 -M "do" -s 1372 1.1.1.1 >/dev/null 2>&1; then chk warn "$(t d_mtu)" "$(t d_mtu_low)"
  else chk info "$(t d_mtu)" "$(t d_mtu_unk)"; fi
  o=""; n=""
  read -r o n < <(awk '/^Tcp:/ { if (!h) { for (i = 1; i <= NF; i++) c[$i] = i; h = 1 } else { print $(c["OutSegs"]), $(c["RetransSegs"]) } }' /proc/net/snmp || true) || true
  if [[ ${o:-0} =~ ^[0-9]+$ && ${n:-0} =~ ^[0-9]+$ ]] && (( o > 1000 )); then
    ms=$(( n * 1000 / o ))
    if (( ms > 50 )); then chk warn "$(t d_retr)" "$((ms / 10)).$((ms % 10)) % - $(t d_retr_high)"
    else chk pass "$(t d_retr)" "$((ms / 10)).$((ms % 10)) %"; fi
  fi

  printf '\n'; hr
  printf '  %s:  %s%s %d%s   %s%s %d%s   %s%s %d%s\n' "$(t d_summary)" \
    "$C_GREEN" "$(t d_pass)" "$D_PASS" "$C_RESET" "$C_YELLOW" "$(t d_warn)" "$D_WARN" "$C_RESET" "$C_RED" "$(t d_fail)" "$D_FAIL" "$C_RESET"
  info "log: $LOG"
}

# ───────────────────────────── status / menu ─────────────────────────────
dot() { # dot ok|bad|off label [extra]
  local col=$C_DIM sym=$SYM_OFF
  case $1 in ok) col=$C_GREEN sym=$SYM_DOT ;; bad) col=$C_RED sym=$SYM_DOT ;; esac
  printf '%s%s%s %s%s  ' "$col" "$sym" "$C_RESET" "$2" "${3:+ $3}"
}

statusbar() {
  local d
  printf '  '
  if is_bbr; then dot ok "$(t st_bbr)"; else dot bad "$(t st_bbr)"; fi
  if have docker && svc_active docker; then dot ok "$(t st_docker)"; else dot bad "$(t st_docker)"; fi
  if svc_active nginx; then dot ok "$(t st_nginx)"; else dot bad "$(t st_nginx)"; fi
  if ufw_active; then dot ok "$(t st_ufw)"; else dot off "$(t st_ufw)"; fi
  if node_running; then dot ok "$(t st_node)"; else dot off "$(t st_node)"; fi
  if d=$(cert_days); then dot ok "$(t st_cert)" "${d}d"; else dot off "$(t st_cert)"; fi
  printf '\n'
}

sysline() {
  local ip ram
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1)}' || true)
  ram=$(awk '/MemTotal/{printf "%.1f GB", $2/1048576}' /proc/meminfo)
  os_detect
  info "${OS_NAME:-linux}  $SYM_MID  $(nproc) vCPU  $SYM_MID  $ram  $SYM_MID  ${ip:-?}"
}

show_status() {
  step "$(t s_status)"
  statusbar
  printf '\n'
  info "$(t st_cfg): $CONF"
  info "  domain=${DOMAIN:-$(t st_nodomain)}  node-port=$NODE_PORT  steal-port=$STEAL_PORT  panel-ip=${PANEL_IP:--}  lang=$LANG_CODE"
  info "  node dir: $NODE_DIR   webroot: $WEBROOT   log: $LOG"
}

show_logs() {
  if [[ ! -f $LOG ]]; then info "(no log yet: $LOG)"; return 0; fi
  sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' "$LOG" | tail -n "${1:-100}"
}

menu_item() { printf '   %s%s%s  %s %s%s%s\n' "$C_CYAN$C_BOLD" "$1" "$C_RESET" "$(padr "$(t "mn_$1")" 26)" "$C_DIM" "$(t "mn_${1}d")" "$C_RESET"; }

menu_draw() {
  if (( IS_TTY )); then printf '\e[H\e[2J'; fi
  printf '\n'; banner; hr; sysline; statusbar; hr
  local i; for i in 1 2 3 4 5 6 7 8 9; do menu_item "$i"; done
  printf '   %sl%s  %s\n' "$C_CYAN$C_BOLD" "$C_RESET" "$(t mn_l)"
  printf '   %s0%s  %s\n' "$C_CYAN$C_BOLD" "$C_RESET" "$(t mn_0)"
  hr
}

# run an action in a subshell so that die/errors return to the menu
run_action() {
  local rc=0
  trap - ERR
  set +e
  ( set -e; arm_trap; "$@" )
  rc=$?
  set -e
  arm_trap
  load_conf
  if (( rc != 0 )); then warn "$(t mn_failed "$LOG")"; fi
  return 0
}

collect_domain() {
  ask DOMAIN "$(t q_domain)" "$DOMAIN" valid_domain; DOMAIN=${DOMAIN,,}
  ask EMAIL  "$(t q_email)"  "$EMAIL"  valid_email
}
collect_node() {
  ask NODE_PORT "$(t q_nport)" "$NODE_PORT" valid_port
}
collect_panel() {
  ask PANEL_IP "$(t q_panel)" "$PANEL_IP" valid_ip_opt
}
collect_key() {
  if [[ -z $SECRET_KEY && -z $SECRET_KEY_FILE ]]; then ask_secret SECRET_KEY "$(t q_key)"; fi
}

wizard() {
  collect_domain; collect_panel; collect_node; collect_key
  printf '\n'; hr; info "$(t plan)"
  info "  domain=$DOMAIN  email=$EMAIL  panel-ip=${PANEL_IP:--}  node-port=$NODE_PORT  steal-port=$STEAL_PORT"
  hr
  if ! confirm "$(t confirm_go)" y; then info "$(t aborted)"; return 0; fi
  do_install
}

act_tune()      { step_preflight; step_tune; }
act_docker()    { step_preflight; step_docker; }
act_selfsteal() { step_preflight; collect_domain; save_conf; if (( ! SKIP_DNS )); then step_dns; fi; step_selfsteal; }
act_firewall()  { step_preflight; collect_panel; collect_node; save_conf; step_firewall; }
act_node()      { collect_node; collect_key; save_conf; step_node; }
act_regen()     { REGEN_SITE=1; collect_domain; save_conf; site_prepare; nginx_apply; }

menu() {
  local ch
  while true; do
    menu_draw
    read -rp "  $(t mn_choose) > " ch || { printf '\n'; return 0; }
    case $ch in
      1) run_action wizard ;;
      2) run_action act_tune ;;
      3) run_action act_docker ;;
      4) run_action act_selfsteal ;;
      5) run_action act_firewall ;;
      6) run_action act_node ;;
      7) run_action doctor ;;
      8) run_action act_regen ;;
      9) show_logs 100 ;;
      l|L) read -rp "  $(t q_lang) > " ch
           case $ch in 2) LANG_CODE=ru ;; *) LANG_CODE=en ;; esac
           save_conf; continue ;;
      0|q|Q) return 0 ;;
      *) warn "$(t mn_bad)"; sleep 1; continue ;;
    esac
    printf '\n'; read -rp "  $(t press_enter)" ch || return 0
  done
}

# ───────────────────────────── CLI ─────────────────────────────
usage() { banner; printf '\n'; t usage "$AUTHOR"; printf '\n'; }

need_val() { if (( $2 < 2 )) || [[ ${3:-} == --* ]]; then die "$(t opt_needs "$1")"; fi; }

parse_args() {
  local a
  while (( $# )); do
    a=$1
    case $a in
      --domain)          need_val "$a" $# "${2:-}"; DOMAIN=${2,,};        INSTALL_FLAGS=1; shift 2 ;;
      --email)           need_val "$a" $# "${2:-}"; EMAIL=$2;             INSTALL_FLAGS=1; shift 2 ;;
      --panel-ip)        need_val "$a" $# "${2:-}"; PANEL_IP=$2;          INSTALL_FLAGS=1; shift 2 ;;
      --node-port)       need_val "$a" $# "${2:-}"; NODE_PORT=$2;         INSTALL_FLAGS=1; shift 2 ;;
      --steal-port)      need_val "$a" $# "${2:-}"; STEAL_PORT=$2;        INSTALL_FLAGS=1; shift 2 ;;
      --secret-key)      need_val "$a" $# "${2:-}"; SECRET_KEY=$2;        INSTALL_FLAGS=1; warn "$(t node_key_cli)"; shift 2 ;;
      --secret-key-file) need_val "$a" $# "${2:-}"; SECRET_KEY_FILE=$2;   INSTALL_FLAGS=1; shift 2 ;;
      --node-tag)        need_val "$a" $# "${2:-}"; NODE_TAG=$2; NODE_TAG_SET=1; INSTALL_FLAGS=1; shift 2 ;;
      --compose-file)    need_val "$a" $# "${2:-}"; COMPOSE_FILE=$2;      INSTALL_FLAGS=1; shift 2 ;;
      --site-dir)        need_val "$a" $# "${2:-}"; SITE_DIR=$2;          INSTALL_FLAGS=1; shift 2 ;;
      --ufw-allow)       need_val "$a" $# "${2:-}"; UFW_ALLOW=$2;         INSTALL_FLAGS=1; shift 2 ;;
      --lang)            need_val "$a" $# "${2:-}"; LANG_CODE=$2;         shift 2 ;;
      --regen-site)      REGEN_SITE=1;    INSTALL_FLAGS=1; shift ;;
      --force-firewall)  FORCE_FW=1;      INSTALL_FLAGS=1; shift ;;
      --force-os)        FORCE_OS=1;      shift ;;
      --skip-dns-check)  SKIP_DNS=1;      INSTALL_FLAGS=1; shift ;;
      --skip-tune)       SKIP_TUNE=1;     INSTALL_FLAGS=1; shift ;;
      --skip-docker)     SKIP_DOCKER=1;   INSTALL_FLAGS=1; shift ;;
      --skip-firewall)   SKIP_FW=1;       INSTALL_FLAGS=1; shift ;;
      --skip-selfsteal)  SKIP_SELFSTEAL=1; INSTALL_FLAGS=1; shift ;;
      --skip-node)       SKIP_NODE=1;     INSTALL_FLAGS=1; shift ;;
      --dry-run)         DRY_RUN=1; shift ;;
      -y|--yes)          ASSUME_YES=1; shift ;;
      -h|--help)         WANT_HELP=1; shift ;;
      --version)         WANT_VERSION=1; shift ;;
      *) die "$(t unknown_opt "$a")" ;;
    esac
  done
}

validate_args() {
  [[ $LANG_CODE == ru || $LANG_CODE == en ]] || LANG_CODE=en
  if [[ -n $DOMAIN ]]; then valid_domain "$DOMAIN" || die "$(t bad_val --domain "$DOMAIN")"; fi
  if [[ -n $EMAIL ]]; then valid_email "$EMAIL" || die "$(t bad_val --email "$EMAIL")"; fi
  if [[ -n $PANEL_IP ]]; then valid_ip "$PANEL_IP" || die "$(t bad_val --panel-ip "$PANEL_IP")"; fi
  valid_port "$NODE_PORT"  || die "$(t bad_val --node-port "$NODE_PORT")"
  valid_port "$STEAL_PORT" || die "$(t bad_val --steal-port "$STEAL_PORT")"
  if [[ $STEAL_PORT == 80 || $STEAL_PORT == 443 || $STEAL_PORT == "$NODE_PORT" ]]; then die "$(t port_clash)"; fi
  if [[ ! $NODE_TAG =~ ^[A-Za-z0-9._-]+$ ]]; then die "$(t bad_val --node-tag "$NODE_TAG")"; fi
}

setup_log() {
  if (( DRY_RUN )); then return 0; fi
  mkdir -p "$(dirname "$LOG")"; touch "$LOG"; chmod 600 "$LOG"
  printf '\n===== %s  fastnode %s  %s =====\n' "$(date -Is)" "$VERSION" "${CMD:-menu}" >>"$LOG"
  exec > >(tee -a "$LOG") 2>&1
  LOGGING=1
}

# PID-file lock (an flock fd would be inherited by daemons we start, e.g. nginx, and never released)
LOCK=/run/fastnode.lock HAVE_LOCK=0 LOGGING=0
take_lock() {
  if (( DRY_RUN )); then return 0; fi
  local pid
  if [[ -f $LOCK ]]; then
    pid=$(<"$LOCK")
    if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null && tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "${SELF##*/}"; then
      die "$(t err_locked)"
    fi
  fi
  echo $$ >"$LOCK"
  HAVE_LOCK=1
}
on_exit() {
  if (( HAVE_LOCK )) && [[ -f $LOCK && $(<"$LOCK") == "$$" ]]; then rm -f "$LOCK"; fi
  if (( LOGGING )); then sleep 0.2; fi   # let tee flush before the shell prompt returns
}
trap on_exit EXIT

detect_lang() { case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in ru*|RU*) echo ru ;; *) echo en ;; esac; }

main() {
  setup_ui
  LANG_CODE=$(detect_lang)
  load_conf
  if [[ -n ${FASTNODE_LANG:-} ]]; then LANG_CODE=$FASTNODE_LANG; fi
  if (( $# )) && [[ ${1:0:1} != "-" ]]; then CMD=$1; shift; fi
  parse_args "$@"
  validate_args

  if (( WANT_VERSION )) || [[ $CMD == version ]]; then echo "$APP $VERSION by $AUTHOR"; exit 0; fi
  if (( WANT_HELP )) || [[ $CMD == help ]]; then usage; exit 0; fi

  if [[ -z $CMD ]]; then
    if (( INSTALL_FLAGS )); then CMD=install
    elif (( IS_TTY )) && [[ -t 0 ]]; then CMD=menu
    else usage; exit 0; fi
  fi
  case $CMD in
    install|tune|docker|firewall|selfsteal|node|doctor|status|logs|menu) ;;
    *) die "$(t unknown_cmd "$CMD")" ;;
  esac

  if (( EUID != 0 )); then die "$(t err_root "$0")"; fi
  if [[ $CMD == logs ]]; then show_logs 200; exit 0; fi
  case $CMD in install|tune|docker|firewall|selfsteal|node|menu) take_lock ;; esac
  setup_log

  case $CMD in
    menu)      menu ;;
    install)   do_install ;;
    tune)      step_preflight; step_tune ;;
    docker)    step_preflight; step_docker ;;
    firewall)  step_preflight; save_conf; step_firewall ;;
    selfsteal) step_preflight; save_conf; if (( ! SKIP_DNS )); then step_dns; fi; step_selfsteal ;;
    node)      save_conf; step_node ;;
    doctor)    doctor; if (( D_FAIL > 0 )); then exit 1; fi ;;
    status)    show_status ;;
  esac
}

main "$@"
