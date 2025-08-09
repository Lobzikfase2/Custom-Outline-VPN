#!/usr/bin/env bash
set -euo pipefail

# ================================================
#  НАСТРАИВАЕМЫЕ ПАРАМЕТРЫ
# ================================================

# Публичный IP-адрес в формате CIDR
IP_CIDR="4.19.4.20/32"
IP_ADDR=${IP_CIDR%/*}

# Имя домена для hosts
DOMAIN="example.com"

# Имя systemd сервиса
SERVICE_NAME="piplo"

# ================================================
#  ПРОВЕРКА ПРЕДВАРИТЕЛЬНЫХ УСЛОВИЙ
# ================================================

if [[ $EUID -ne 0 ]]; then
    echo "ОШИБКА: Скрипт должен запускаться с правами root!" >&2
    exit 1
fi

if ! command -v systemctl &>/dev/null; then
    echo "ОШИБКА: Systemd не обнаружен!" >&2
    exit 1
fi

# Проверка наличия Docker
if ! command -v docker &>/dev/null; then
    echo "ОШИБКА: Docker не установлен!" >&2
    echo "Перед запуском скрипта необходимо установить Docker." >&2
    exit 1
fi

# ================================================
#  УСТАНОВКА НЕОБХОДИМЫХ ПАКЕТОВ
# ================================================

REQUIRED_PKGS=("ipcalc" "nginx" "iproute2")
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    echo "Установка недостающих пакетов: ${MISSING_PKGS[*]}"
    apt-get update
    apt-get install -y "${MISSING_PKGS[@]}"
fi

# ================================================
#  ПРОВЕРКА ПУБЛИЧНОСТИ IP
# ================================================

# Функция проверки публичности IP
is_public_ip() {
    local ip="$1"
    # Проверяем диапазоны приватных IP
    if ipcalc "$ip" | grep -q "Private Internet"; then
        return 1
    fi
    return 0
}

if ! is_public_ip "$IP_ADDR"; then
    echo "ОШИБКА: $IP_ADDR не является публичным IP-адресом!" >&2
    exit 1
fi

# ================================================
#  СОЗДАНИЕ SYSTEMD-СЕРВИСА
# ================================================

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
echo "Создание systemd-сервиса: $SERVICE_FILE"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Add public IP [$IP_CIDR] to loopback
DefaultDependencies=no
Before=nginx.service
After=local-fs.target
Requires=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c "/sbin/ip addr add $IP_CIDR dev lo || true; for i in {1..10}; do ip addr show dev lo | grep -qF \"$IP_CIDR\" && exit 0; sleep 0.2; done; echo \"ERROR: IP $IP_CIDR not added!\" >&2; exit 1"
ExecStop=/sbin/ip addr del $IP_CIDR dev lo
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Перезагружаем демон systemd
systemctl daemon-reload

# Включаем и запускаем сервис
if ! systemctl enable --now "$SERVICE_NAME"; then
    echo "ОШИБКА: Не удалось запустить сервис $SERVICE_NAME!" >&2
    echo "Подробности: systemctl status $SERVICE_NAME" >&2
    exit 1
fi

if ! ip addr show dev lo | grep -qF "$IP_CIDR"; then
    echo "ОШИБКА: IP $IP_CIDR не добавлен в интерфейс lo!" >&2
    exit 1
fi

# ================================================
#  НАСТРОЙКА ЗАВИСИМОСТЕЙ ДЛЯ NGINX
# ================================================

NGINX_OVERRIDE_DIR="/etc/systemd/system/nginx.service.d"
NGINX_WAIT_CONF="${NGINX_OVERRIDE_DIR}/wait-for-${SERVICE_NAME}.conf"
echo "Создание конфигурации ожидания для nginx: $NGINX_WAIT_CONF"

mkdir -p "$NGINX_OVERRIDE_DIR"
cat > "$NGINX_WAIT_CONF" <<EOF
[Unit]
Requires=$SERVICE_NAME.service
After=$SERVICE_NAME.service
EOF

systemctl daemon-reload

# ================================================
#  КОНФИГУРАЦИЯ NGINX
# ================================================

NGINX_CONF="/etc/nginx/sites-available/${DOMAIN}.conf"
echo "Создание конфигурации nginx: $NGINX_CONF"

cat > "$NGINX_CONF" <<EOF
server {
    listen $IP_ADDR:80;
    server_name $DOMAIN;

    location / {
        add_header Content-Type text/plain;
        access_log off;
        # return 204;
        # Либо вместо прямого ответа статусом, можно делать редирект на сервис гугла для проверки
        proxy_pass http://clients3.google.com/generate_204;
        proxy_set_header Host clients3.google.com;
    }
}
EOF

# Активация конфига
rm -f /etc/nginx/sites-available/default
rm -f /etc/nginx/sites-enabled/default
ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/"

# Проверка конфигурации
if ! nginx -t; then
    echo "ОШИБКА: Неверная конфигурация nginx!" >&2
    exit 1
fi

systemctl reload nginx

# Проверка работы nginx
if ! ss -tuln | grep -qF "$IP_ADDR:80"; then
    echo "ОШИБКА: Nginx не слушает $IP_ADDR:80!" >&2
    exit 1
fi

# ================================================
#  НАСТРОЙКА /etc/hosts
# ================================================

HOSTS_ENTRY="$IP_ADDR $DOMAIN"
echo "Добавление записи в /etc/hosts: $HOSTS_ENTRY"

# Удаление существующих записей
sed -i "/$DOMAIN/d" /etc/hosts
echo "$HOSTS_ENTRY" >> /etc/hosts

# Проверка записи
if ! grep -qF "$HOSTS_ENTRY" /etc/hosts; then
    echo "ОШИБКА: Не удалось добавить запись в /etc/hosts!" >&2
    exit 1
fi

# ================================================
#  ОПТИМИЗАЦИЯ СЕТЕВЫХ ПАРАМЕТРОВ
# ================================================

echo "Оптимизация сетевых параметров системы"
echo "============================================"
# Резервное копирование и настройка sysctl.conf
mv /etc/sysctl.conf /etc/sysctl.conf.old
cat > /etc/sysctl.conf <<EOF
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

# Применение изменений
sysctl -p

# Настройка лимитов файловых дескрипторов
grep -q "\* soft nofile" /etc/security/limits.conf || echo "* soft nofile 65536" >> /etc/security/limits.conf
grep -q "\* hard nofile" /etc/security/limits.conf || echo "* hard nofile 65536" >> /etc/security/limits.conf
echo "============================================"

# ================================================
#  ПЕРЕЗАГРУЗКА DOCKER
# ================================================

echo "Перезагрузка службы Docker"
systemctl restart docker

# ================================================
#  ФИНАЛЬНАЯ ПРОВЕРКА
# ================================================

echo "Проверка доступности сервисов..."

check_http() {
    local url=$1
    echo -n "Проверка $url: "
    if curl -sI "$url" | grep -q "HTTP/1.1 204"; then
        echo "УСПЕХ"
    else
        echo "ОШИБКА"
        exit 1
    fi
}

curl -I "http://$IP_ADDR"
curl -I "http://$DOMAIN"

# ================================================
#  ИТОГОВЫЙ СТАТУС
# ================================================

echo ""
echo "✅ Настройка успешно завершена!"
echo "============================================"
echo "Публичный IP:    $IP_CIDR"
echo "Домен:           $DOMAIN"
echo "Сервис адресов:  $(systemctl is-active $SERVICE_NAME)"
echo "Nginx статус:    $(systemctl is-active nginx)"
echo ""
echo "Проверка назначенного адреса:"
ip addr show dev lo | grep -F "$IP_CIDR" || true
echo "============================================"
