#!/bin/sh

set -e

PANEL_CONFIG="/opt/etc/telemt-panel/config.toml"
TELEMT_CONFIG="/opt/etc/telemt/config.toml"
TELEMT_PANEL_URL="https://test.entware.net/mipssf-k3.4/4test/be/telemt-panel_0.6.0-1_mips-3.4.ipk"

echo "=== Telemt Panel installer for Entware (mips) ==="

# --- Остановка сервиса если есть ---
if [ -x /opt/etc/init.d/S99telemt-panel ]; then
    /opt/etc/init.d/S99telemt-panel stop >/dev/null 2>&1 || true
fi

# --- Проверка порта ---
DEFAULT_PORT=8080

check_port() {
    PORT=$1
    if netstat -tuln | grep -q ":$PORT "; then
        return 1
    fi
    return 0
}

echo "[1] Проверка занятости порта $DEFAULT_PORT"

if ! check_port "$DEFAULT_PORT"; then
    echo "⚠️  Порт $DEFAULT_PORT уже занят!"
    printf "Введите новый порт для telemt-panel: "
    read LISTEN_PORT || true
    while ! check_port "$LISTEN_PORT"; do
        printf "Порт $LISTEN_PORT тоже занят. Введите другой: "
        read LISTEN_PORT || true
    done
else
    LISTEN_PORT="$DEFAULT_PORT"
fi

echo "Используем порт: $LISTEN_PORT"

# --- Установка через opkg ---
echo "[2] Установка telemt-panel через opkg..."
opkg update
opkg install "$TELEMT_PANEL_URL"

# --- Пароль ---
echo "[3] Введите пароль для входа в панель:"
read PASS || true

PASSWORD_HASH=$(echo "$PASS" | /opt/sbin/telemt-panel hash-password 2>&1 | tail -1)

if [ -z "$PASSWORD_HASH" ]; then
    echo "❌ Ошибка: не удалось сгенерировать хеш пароля!"
    exit 1
fi

echo "password_hash = $PASSWORD_HASH"

# --- JWT secret ---
echo "[4] Генерация jwt_secret..."
JWT_SECRET=$(openssl rand -hex 32)
echo "jwt_secret = $JWT_SECRET"

# --- Читаем auth_header из telemt конфига ---
echo "[5] Чтение auth_header из $TELEMT_CONFIG"

if [ ! -f "$TELEMT_CONFIG" ]; then
    echo "❌ Файл $TELEMT_CONFIG не найден!"
    exit 1
fi

AUTH_HEADER=$(grep -E '^auth_header' "$TELEMT_CONFIG" | sed -E 's/.*= *"([^"]+)".*/\1/')

if [ -z "$AUTH_HEADER" ]; then
    echo "❌ Не удалось извлечь auth_header!"
    exit 1
fi

echo "auth_header = $AUTH_HEADER"

# --- Конфиг ---
echo "[6] Создание конфига telemt-panel..."

mkdir -p /opt/etc/telemt-panel

cat > "$PANEL_CONFIG" <<TOML
listen = "0.0.0.0:$LISTEN_PORT"

[telemt]
url = "http://127.0.0.1:9091"
auth_header = "$AUTH_HEADER"
binary_path = "/opt/usr/bin/telemt"

[panel]
binary_path = "/opt/sbin/telemt-panel"

[tls]

[geoip]

[auth]
username = "admin"
password_hash = "$PASSWORD_HASH"
jwt_secret = "$JWT_SECRET"
session_ttl = "24h"

[users]
TOML

# --- Init скрипт ---
echo "[7] Создание init скрипта..."

cat > /opt/etc/init.d/S99telemt-panel <<'INITSCRIPT'
#!/bin/sh

ENABLED=yes
PROCS=telemt-panel
ARGS="-config /opt/etc/telemt-panel/config.toml"
PREARGS=""
DESC="Telemt Panel"
PATH=/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /opt/etc/init.d/rc.func
INITSCRIPT

chmod +x /opt/etc/init.d/S99telemt-panel

# --- Запуск ---
echo "[8] Запуск telemt-panel..."

if /opt/etc/init.d/S99telemt-panel start; then
    sleep 2
    /opt/etc/init.d/S99telemt-panel status || true
else
    echo "❌ Ошибка запуска telemt-panel!"
    exit 1
fi

# --- Локальный IP ---
IP=$(ip -4 addr show br0 2>/dev/null | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -n1 || \
     ip -4 addr show | grep -oE "(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)[0-9]+(\.[0-9]+){2}" | head -n1)

echo ""
echo "==========================================="
echo "✔ telemt-panel установлен и запущен"
echo "✔ Конфиг: $PANEL_CONFIG"
echo "✔ Порт: $LISTEN_PORT"
echo "✔ Логин: admin"
echo "✔ Init скрипт: /opt/etc/init.d/S99telemt-panel"
echo ""
echo "🌐 http://${IP:-192.168.1.1}:$LISTEN_PORT"
echo "==========================================="
