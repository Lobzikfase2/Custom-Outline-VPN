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

# Все файлы, которые создаются дальше, будут root-only по умолчанию
umask 077

# ------------------------------------------------------------
# args: --domain
# ------------------------------------------------------------
proxy_domain=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      proxy_domain="${2:-}"
      shift 2
      ;;
    --domain=*)
      proxy_domain="${1#*=}"
      shift 1
      ;;
    -h|--help)
      echo "Usage: $0 [--domain \"<proxy-domain>\"]"
      exit 0
      ;;
    *)
      die "Неизвестный аргумент: $1"
      ;;
  esac
done

proxy_domain="$(echo -n "${proxy_domain}" | tr -d '[:space:]')"
# ------------------------------------------------------------

info "Установка gate_syncer"

# 1) Домен
if [[ -z "${proxy_domain}" ]]; then
  read -rp "Введите домен прокси-сервера: " proxy_domain
  proxy_domain="$(echo -n "${proxy_domain}" | tr -d '[:space:]')"
fi

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

# 4) sysctl + limits
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

sysctl -p >/dev/null 2>&1 || warn "sysctl вернул предупреждения."

grep -qE '^\* soft nofile' /etc/security/limits.conf || echo "* soft nofile 65536" >> /etc/security/limits.conf
grep -qE '^\* hard nofile' /etc/security/limits.conf || echo "* hard nofile 65536" >> /etc/security/limits.conf

# 5) Python-зависимости
info "Установка Python-зависимостей"
#python3 -m pip install --upgrade pip >/dev/null
#python3 -m pip install requests >/dev/null
python3 -m pip install --upgrade pip
python3 -m pip install requests
log "requests установлен"

# 6) stream.d базовые права
info "Права на каталог stream.d"
chown root:root "${TARGET_BASE}"
chmod 755 "${TARGET_BASE}"

# 7) PROXY_DOMAIN
info "Сохранение домена"
echo -n "${proxy_domain}" > "${DOMAIN_FILE}"
chown root:root "${DOMAIN_FILE}"
chmod 600 "${DOMAIN_FILE}"
log "Файл домена создан"

# 7.5) sync.log
info "Создание файла логов (root-only)"
touch "${LOG_FILE}"
chown root:root "${LOG_FILE}"
chmod 600 "${LOG_FILE}"
log "Файл логов создан"

# 8) gate_syncer
info "Загрузка gate_syncer из репозитория"
TMPDIR_PATH="$(mktemp -d)"
TARBALL_URL="https://codeload.github.com/${REPO_OWNER}/${REPO_NAME}/tar.gz/refs/heads/${REPO_BRANCH}"
TARBALL_PATH="${TMPDIR_PATH}/repo.tar.gz"

sudo curl -fL "${TARBALL_URL}" -o "${TARBALL_PATH}"
tar -xzf "${TARBALL_PATH}" -C "${TMPDIR_PATH}"

TOPDIR="$(find "${TMPDIR_PATH}" -maxdepth 1 -type d -name "${REPO_NAME}-*" | head -n 1)"
SRC_DIR="${TOPDIR}/gate_syncer"

rm -rf "${TARGET_DIR}"
cp -a "${SRC_DIR}" "${TARGET_DIR}"
log "gate_syncer установлен"

# 9) root-only
info "Права на пакет gate_syncer"
chown -R root:root "${TARGET_DIR}"
find "${TARGET_DIR}" -type d -exec chmod 700 {} \;
find "${TARGET_DIR}" -type f -exec chmod 600 {} \;

# 10) cron
info "Установка cron-задачи"
CRON_LINE="* * * * * umask 077; cd /etc/nginx/stream.d && /usr/bin/python3 -m gate_syncer.gate_syncer >/dev/null 2>&1"
CURRENT_CRON="$(crontab -l -u root 2>/dev/null || true)"
NEW_CRON="$(echo "${CURRENT_CRON}" | grep -v gate_syncer.gate_syncer | sed '/^[[:space:]]*$/d' || true)"
( echo "${NEW_CRON}"; echo "${CRON_LINE}" ) | crontab -u root -

systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null || true
systemctl restart nginx 2>/dev/null || service nginx restart 2>/dev/null || true

log "Установка завершена"
echo "Сводка:"
echo "  • Домен: ${DOMAIN_FILE}"
echo "  • Лог:   ${LOG_FILE}"
echo "  • Пакет: ${TARGET_DIR}"
echo "  • cron:  запуск каждую минуту"
