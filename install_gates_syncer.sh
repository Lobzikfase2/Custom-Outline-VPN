#!/usr/bin/env bash
set -euo pipefail
export PIP_ROOT_USER_ACTION=ignore

REPO_OWNER="Lobzikfase2"
REPO_NAME="Custom-Outline-VPN"
REPO_BRANCH="main"

TARGET_BASE="/etc/nginx/stream.d"
TARGET_DIR="${TARGET_BASE}/gate_syncer"
DOMAIN_FILE="${TARGET_BASE}/PROXY_DOMAIN"
LOG_FILE="${TARGET_BASE}/sync.log"

log()  { echo -e "[OK]   $*"; }
info() { echo -e "[INFO] $*"; }
warn() { echo -e "[WARN] $*" >&2; }
die()  { echo -e "[ERR]  $*" >&2; exit 1; }

cleanup() {
  if [[ -n "${TMPDIR_PATH:-}" && -d "${TMPDIR_PATH:-}" ]]; then
    rm -rf "${TMPDIR_PATH}" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'die "Ошибка на строке ${LINENO}. Команда: ${BASH_COMMAND}"' ERR

[[ "${EUID}" -eq 0 ]] || die "Запусти скрипт с правами root (через sudo)."

# Все файлы, которые создаются дальше, будут root-only по умолчанию (600/700)
umask 077

info "Установка gate_syncer"

# 1) Домен
read -rp "Введите домен прокси-сервера: " proxy_domain
proxy_domain="$(echo -n "${proxy_domain}" | tr -d '[:space:]')"
[[ -n "${proxy_domain}" ]] || die "Домен не может быть пустым."
log "Домен принят: ${proxy_domain}"

# 2) Пакеты
info "Установка необходимых пакетов"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

REQUIRED_PKGS=(python3 python3-pip cron curl nginx ca-certificates tar)
MISSING=()
for p in "${REQUIRED_PKGS[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if ((${#MISSING[@]})); then
  apt-get install -y "${MISSING[@]}"
  log "Установлено: ${MISSING[*]}"
else
  log "Пакеты уже установлены"
fi

# 3) nginx.conf
info "Запись конфигурации nginx"
mkdir -p "${TARGET_BASE}"

cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 30000;
    multi_accept on;
    use epoll;
}

stream {
    proxy_connect_timeout 5s;
    include /etc/nginx/stream.d/*.conf;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    gzip on;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

nginx -t >/dev/null
log "Конфигурация nginx корректна"

# 4) sysctl + limits (начисто)
info "Применение системных параметров"
cat > /etc/sysctl.conf <<'EOF'
net.ipv4.tcp_mtu_probing = 1
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.ipv4.tcp_rmem = 8192 87380 2500000
net.ipv4.tcp_wmem = 4096 65536 2500000
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.core.somaxconn = 16384
net.ipv4.tcp_max_syn_backlog = 1024
EOF

sysctl -p >/dev/null 2>&1 || warn "sysctl вернул предупреждения (часть параметров могла не примениться)."

grep -qE '^\* soft nofile' /etc/security/limits.conf || echo "* soft nofile 65536" >> /etc/security/limits.conf
grep -qE '^\* hard nofile' /etc/security/limits.conf || echo "* hard nofile 65536" >> /etc/security/limits.conf

# 5) requests
info "Установка Python-зависимостей"
python3 -m pip install --upgrade pip >/dev/null
python3 -m pip install requests >/dev/null
log "requests установлен"

# 6) stream.d базовые права (не трогаем другие файлы)
info "Права на каталог stream.d"
chown root:root "${TARGET_BASE}"
chmod 755 "${TARGET_BASE}"

# 7) PROXY_DOMAIN (root-only)
info "Сохранение домена"
echo -n "${proxy_domain}" > "${DOMAIN_FILE}"
chown root:root "${DOMAIN_FILE}"
chmod 600 "${DOMAIN_FILE}"
log "Файл домена создан"

# 7.5) sync.log (root-only)
# Создаём заранее, чтобы он НЕ появился с 644 из-за umask cron/python.
info "Создание файла логов (root-only)"
touch "${LOG_FILE}"
chown root:root "${LOG_FILE}"
chmod 600 "${LOG_FILE}"
log "Файл логов создан: ${LOG_FILE} (600, root-only)"

# 8) Скачивание и установка gate_syncer (строго из корня репо)
info "Загрузка gate_syncer из репозитория"
TMPDIR_PATH="$(mktemp -d)"
TARBALL_URL="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${REPO_BRANCH}"
TARBALL_PATH="${TMPDIR_PATH}/repo.tar.gz"

curl -fsSL "${TARBALL_URL}" -o "${TARBALL_PATH}"
tar -xzf "${TARBALL_PATH}" -C "${TMPDIR_PATH}"

TOPDIR="$(find "${TMPDIR_PATH}" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n 1)"
[[ -n "${TOPDIR}" && -d "${TOPDIR}" ]] || die "Не удалось определить корневую папку репозитория в архиве."

SRC_DIR="${TOPDIR}/gate_syncer"
[[ -d "${SRC_DIR}" ]] || die "Папка gate_syncer не найдена в корне репозитория."

rm -rf "${TARGET_DIR}"
cp -a "${SRC_DIR}" "${TARGET_DIR}"
log "gate_syncer установлен"

# 9) root-only на gate_syncer
info "Права на пакет gate_syncer (только root)"
chown -R root:root "${TARGET_DIR}"
find "${TARGET_DIR}" -type d -exec chmod 700 {} \;
find "${TARGET_DIR}" -type f -exec chmod 600 {} \;

[[ -f "${TARGET_DIR}/__init__.py" ]] || die "__init__.py не найден."
[[ -f "${TARGET_DIR}/gate_syncer.py" ]] || die "gate_syncer.py не найден."
log "Структура пакета проверена"

# 10) cron + тест импорта + первый запуск
info "Проверка импорта модуля"
cd "${TARGET_BASE}"
python3 -c "import gate_syncer.gate_syncer" >/dev/null 2>&1 || warn "Импорт завершился с ошибкой (в cron может повториться)."

info "Тестовый запуск (до 30 секунд)"
cd "${TARGET_BASE}"
timeout 30 python3 -m gate_syncer.gate_syncer >/dev/null 2>&1 || warn "Тестовый запуск завершился с ошибкой (возможно, ожидаемо)."

info "Установка cron-задачи (root, раз в минуту)"
# umask 077 — чтобы даже если sync.log удалят, он заново создался как 600.
CRON_LINE="* * * * * umask 077; cd /etc/nginx/stream.d && /usr/bin/python3 -m gate_syncer.gate_syncer >/dev/null 2>&1"
CURRENT_CRON="$(crontab -l -u root 2>/dev/null || true)"
NEW_CRON="$(echo "${CURRENT_CRON}" | grep -v "gate_syncer.gate_syncer" | sed '/^[[:space:]]*$/d' || true)"
( echo "${NEW_CRON}"; echo "${CRON_LINE}" ) | crontab -u root -
log "cron-задача установлена"

info "Перезапуск служб"
systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null || true
systemctl restart nginx 2>/dev/null || service nginx restart 2>/dev/null || true

log "Установка завершена"
echo "Сводка:"
echo "  • Домен: ${DOMAIN_FILE} (600, root-only)"
echo "  • Лог:   ${LOG_FILE} (600, root-only)"
echo "  • Пакет: ${TARGET_DIR} (700/600, root-only)"
echo "  • cron: запуск каждую минуту (python3 -m gate_syncer.gate_syncer)"
