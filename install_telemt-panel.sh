#!/bin/sh

set -e

PANEL_CONFIG="/opt/etc/telemt-panel/config.toml"
TELEMT_CONFIG="/opt/etc/telemt/config.toml"
GITHUB_REPO="amirotin/telemt_panel"

# Определяем архитектуру
ARCH=$(uname -m)

case "$ARCH" in
    aarch64)
        ARCH_TAG="aarch64"
        ;;
    x86_64)
        ARCH_TAG="x86_64"
        ;;
    mips|mipsel)
        ARCH_TAG="mipsel"
        echo "⚠️  Предупреждение: архитектура $ARCH может не быть доступна в релизах"
        ;;
    *)
        echo "Неизвестная архитектура: $ARCH"
        exit 1
        ;;
esac

echo "Определена архитектура: $ARCH"
echo "Репозиторий: https://github.com/$GITHUB_REPO/releases"
echo ""

# Остановка сервиса, если есть
if [ -x /opt/etc/init.d/S99telemt-panel ]; then
    /opt/etc/init.d/S99telemt-panel stop >/dev/null 2>&1 || true
fi

DEFAULT_PORT=8080

echo "[1] Проверка занятости порта $DEFAULT_PORT"

check_port() {
    PORT=$1
    if netstat -tuln | grep -q ":$PORT "; then
        echo "⚠️  Порт $PORT уже занят!"
        netstat -tulnp | grep ":$PORT " || true
        return 1
    fi
    return 0
}

if ! check_port "$DEFAULT_PORT"; then
    echo ""
    echo "Введите новый порт для telemt-panel:"
    read -r NEW_PORT

    while ! check_port "$NEW_PORT"; do
        echo "Порт $NEW_PORT тоже занят. Введите другой:"
        read -r NEW_PORT
    done

    LISTEN_PORT="$NEW_PORT"
else
    LISTEN_PORT="$DEFAULT_PORT"
fi

echo "Используем порт: $LISTEN_PORT"
echo ""

echo "[2] Получение последнего релиза из GitHub"

TMPDIR="/opt/tmp/telemt-panel-install"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"
cd "$TMPDIR"

# Получаем информацию о последнем релизе через GitHub API
LATEST_RELEASE=$(wget -q -O - "https://api.github.com/repos/$GITHUB_REPO/releases/latest")

if [ -z "$LATEST_RELEASE" ]; then
    echo "❌ Ошибка: не удалось получить информацию о релизе!"
    exit 1
fi

# Извлекаем версию
VERSION=$(echo "$LATEST_RELEASE" | grep -o '"tag_name": "[^"]*"' | head -1 | cut -d'"' -f4)
echo "Найден релиз: $VERSION"

# Формируем URL для архива
ARCHIVE_URL="https://github.com/$GITHUB_REPO/releases/download/$VERSION/telemt-panel-${ARCH_TAG}-linux-gnu.tar.gz"

echo "Скачиваем архив: $ARCHIVE_URL"
echo ""

# Скачиваем архив
if ! wget -O telemt-panel.tar.gz "$ARCHIVE_URL"; then
    echo "❌ Ошибка: не удалось скачать архив!"
    exit 1
fi

# Распаковываем архив
echo "[3] Распаковка архива"
tar -xzf telemt-panel.tar.gz

if [ ! -f telemt-panel ]; then
    echo "❌ Ошибка: telemt-panel не найден в архиве!"
    exit 1
fi

chmod +x telemt-panel

echo "[4] Установка telemt-panel"

# Создаем директорию для бинарника
mkdir -p /opt/sbin
cp telemt-panel /opt/sbin/telemt-panel

echo "[5] Проверка наличия telemt-panel"
if ! /opt/sbin/telemt-panel --version >/dev/null 2>&1; then
    echo "⚠️  Предупреждение: не удалось проверить версию telemt-panel"
fi

echo "[6] Введите пароль для входа в панель:"
read PASS

PASSWORD_HASH=$(/opt/sbin/telemt-panel hash-password "$PASS" 2>/dev/null || echo "")

if [ -z "$PASSWORD_HASH" ]; then
    echo "❌ Ошибка: не удалось сгенерировать хеш пароля!"
    exit 1
fi

echo "password_hash = $PASSWORD_HASH"

echo "[7] Генерация jwt_secret"
JWT_SECRET=$(openssl rand -hex 32)
echo "jwt_secret = $JWT_SECRET"

echo "[8] Чтение auth_header из $TELEMT_CONFIG"

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

echo "[9] Создание нового конфига telemt-panel"

mkdir -p /opt/etc/telemt-panel

cat > "$PANEL_CONFIG" <<EOF
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
EOF

echo "[10] Создание init скрипта для Entware"

cat > /opt/etc/init.d/S99telemt-panel <<'INITSCRIPT'
#!/bin/sh

ENABLED=yes
PROCS=telemt-panel
ARGS="-config /opt/etc/$PROCS/config.toml"
PREARGS=""
DESC="Telemt Panel"
PATH=/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin

. /opt/etc/init.d/rc.func
INITSCRIPT

chmod +x /opt/etc/init.d/S99telemt-panel

echo "[11] Запуск telemt-panel"

if /opt/etc/init.d/S99telemt-panel start; then
    sleep 2
    /opt/etc/init.d/S99telemt-panel status || true
else
    echo "❌ Ошибка запуска telemt-panel!"
    exit 1
fi

echo ""
echo "==========================================="
echo "✔ telemt-panel установлен и запущен"
echo "✔ Версия: $VERSION"
echo "✔ Конфиг: $PANEL_CONFIG"
echo "✔ Порт: $LISTEN_PORT"
echo "✔ Логин: admin"
echo "✔ Init скрипт: /opt/etc/init.d/S99telemt-panel"
echo "==========================================="
