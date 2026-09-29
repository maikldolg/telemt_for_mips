#!/bin/sh

set -e
set -o pipefail

CONF_DIR="/opt/etc/telemt"
CONF="$CONF_DIR/config.toml"
INIT="/opt/etc/init.d/S99telemt"
PID_DIR="/tmp/telemt-run"
PID_FILE="$PID_DIR/telemt.pid"

echo "=== Telemt installer for Entware ==="
echo "Установка зависимостей"
opkg update
opkg install openssl-util
opkg install jq
opkg install curl

# --- Stop Telemt if exists ---
if [ -x "$INIT" ]; then
    "$INIT" stop >/dev/null 2>&1 || true
fi
killall telemt >/dev/null 2>&1 || true

# --- sudo shim: telemt-panel вызывает "sudo systemctl restart telemt", а в Entware sudo нет ---
if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo не найден, создаю шим /opt/bin/sudo (нужен telemt-panel для обновлений)"
    mkdir -p /opt/bin
    cat > /opt/bin/sudo <<'SUDOEOF'
#!/bin/sh
while [ "${1#-}" != "$1" ]; do shift; done
exec "$@"
SUDOEOF
    chmod +x /opt/bin/sudo
fi

# --- Existing config? ---
KEEP_CONFIG=0
if [ -f "$CONF" ]; then
    printf "Найден существующий конфиг. Оставить его (секреты и ссылки не изменятся)? (y/n, default y): "
    read KEEP || true
    case "${KEEP:-y}" in
        y|Y) KEEP_CONFIG=1 ;;
    esac
fi

ask_params() {
    # --- Detect public IP and interface via ip route get ---
    echo "Detecting public IP via ip route get..."

    ROUTE_INFO=$(ip route get 1.1.1.1 2>/dev/null | head -n1)

    if [ -z "$ROUTE_INFO" ]; then
        echo "ERROR: Cannot determine route to 1.1.1.1!"
        exit 1
    fi

    DEF_IFACE=$(echo "$ROUTE_INFO" | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
    if [ -z "$DEF_IFACE" ]; then
        echo "ERROR: Cannot detect interface from ip route get!"
        exit 1
    fi
    echo "Default route interface: $DEF_IFACE"

    AUTO_IP=$(echo "$ROUTE_INFO" | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
    if [ -z "$AUTO_IP" ]; then
        echo "ERROR: Cannot detect source IP from ip route get!"
        exit 1
    fi
    echo "Detected public IP: $AUTO_IP"

    # --- Detect TLS domain ending with netcraze.io ---
    echo "Detecting TLS domain (ending with netcraze.io)..."
    AUTO_DOMAIN=$(ndmc -c 'ip http ssl acme list' | grep "domain:" | awk '{print $2}' | grep "netcraze.io" | head -n 1 || true)
    [ -z "$AUTO_DOMAIN" ] && AUTO_DOMAIN="не найден"
    echo "Domain: $AUTO_DOMAIN"

    # --- Ask parameters ---
    printf "Enter port (default 1443): "
    read PORT || true
    PORT=${PORT:-1443}

    printf "Enter public IP (default $AUTO_IP): "
    read PUBLIC_IP || true
    PUBLIC_IP=${PUBLIC_IP:-$AUTO_IP}

    printf "Enter TLS domain (default $AUTO_DOMAIN): "
    read TLS_DOMAIN || true
    TLS_DOMAIN=${TLS_DOMAIN:-$AUTO_DOMAIN}

    printf "Enter username (default user1): "
    read USERNAME || true
    USERNAME=${USERNAME:-user1}

    printf "Enable read-only API mode? По умолчанию в telemt-panel вы сможете только просматривать статистику и редактировать конфиг (y/n, default y): "
    read READONLY || true
    READONLY=${READONLY:-y}
    case "$READONLY" in
        y|Y) READONLY_FLAG=true ;;
        n|N) READONLY_FLAG=false ;;
        *) echo "Invalid input, using default: read-only = true"; READONLY_FLAG=true ;;
    esac
    echo "read-only mode: $READONLY_FLAG"

    # --- Auto-generate secret ---
    echo "Generating HEX16 secret..."
    USER_SECRET=$(openssl rand -hex 16)
    echo "Generated secret: $USER_SECRET"

    # --- Auto-generate auth_header ---
    echo "Generating API auth_header..."
    AUTH_HEADER=$(openssl rand -hex 32)
    echo "Generated auth_header: $AUTH_HEADER"

    # --- Select upstream interface ---
    echo "Выберете интерфейс через который прокси будет выходить в мир"

    IFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -v '^sit' | grep -v '^ip6tnl')

    echo "Доступные интерфейсы:"
    i=1
    for iface in $IFACES; do
        echo "  $i) $iface"
        eval "iface_$i=$iface"
        i=$((i+1))
    done

    COUNT=$((i-1))

    printf "Select upstream interface number (default $COUNT): "
    read IFNUM || true
    IFNUM=${IFNUM:-$COUNT}

    UP_IFACE=$(eval echo "\$iface_$IFNUM")
    echo "Selected interface: $UP_IFACE"

    # --- Check if port is free ---
    while true; do
        echo "Checking if port $PORT is free..."
        if netstat -tuln | grep -E "[:.]$PORT\b" >/dev/null 2>&1; then
            echo "Port $PORT is already in use!"
            printf "Enter another port: "
            read PORT || true
        else
            echo "Port OK."
            break
        fi
    done

    # --- Validate domain ---
    echo "Checking domain resolution..."
    if ! nslookup "$TLS_DOMAIN" 2>/dev/null | grep -q 'Address'; then
        echo "WARNING: Domain $TLS_DOMAIN does not resolve!"
        echo "Press Enter to continue anyway or Ctrl+C to abort."
        read _ || true
    else
        echo "Domain OK."
    fi
}

if [ "$KEEP_CONFIG" -eq 0 ]; then
    ask_params
fi

echo ""
echo "Installing dependencies..."
opkg install wget-ssl || opkg install wget

# --- Download latest Telemt release ---
echo "=== Installing Telemt (latest release) ==="

TMPDIR="/opt/tmp/telemt_dl"
rm -rf "$TMPDIR"
mkdir -p "$TMPDIR"

ARCH=$(uname -m)
case "$ARCH" in
    aarch64) TELEMT_FILE="telemt-aarch64-linux-musl.tar.gz" ;;
    mips|mipsel|mips32|mips32r2) TELEMT_FILE="telemt-mipsel-linux-musl.tar.gz" ;;
    *) echo "ERROR: Unsupported architecture: $ARCH"; exit 1 ;;
esac

echo "Detecting latest Telemt version from GitHub..."
LATEST_VER=$(wget -qO- https://api.github.com/repos/telemt/telemt/releases/latest | grep '"tag_name"' | cut -d '"' -f 4 || true)

if [ -z "$LATEST_VER" ]; then
    echo "ERROR: Cannot detect latest version from GitHub!"
    exit 1
fi

echo "Latest version: $LATEST_VER"

TARBALL_URL="https://github.com/telemt/telemt/releases/download/${LATEST_VER}/${TELEMT_FILE}"
TARBALL_PATH="$TMPDIR/telemt.tar.gz"

echo "Downloading Telemt from:"
echo "  $TARBALL_URL"

wget -O "$TARBALL_PATH" "$TARBALL_URL"

echo "Extracting Telemt..."
tar -xzf "$TARBALL_PATH" -C "$TMPDIR"

TELEMT_BIN=$(find "$TMPDIR" -maxdepth 2 -type f -name telemt | head -n 1)
if [ -z "$TELEMT_BIN" ]; then
    echo "ERROR: telemt binary not found in archive!"
    exit 1
fi

echo "Installing Telemt binary to /opt/usr/bin..."
mkdir -p /opt/usr/bin
cp "$TELEMT_BIN" /opt/usr/bin/telemt
chmod +x /opt/usr/bin/telemt

echo "Telemt binary installed: $(/opt/usr/bin/telemt --version 2>&1 | head -n1)"

# --- Install init script ---
echo "Installing init script..."

mkdir -p /opt/etc/init.d

# Каталог pid-файла: telemt проверяет владельца и права всего пути к нему.
# /var/run и /opt/var/run на Keenetic проверку не проходят (демон молча умирает после форка),
# /tmp/telemt-run проходит. /tmp очищается при ребуте, поэтому каталог создаётся при каждом вызове скрипта.
cat > "$INIT" <<'EOF'
#!/bin/sh

ENABLED=yes
PROCS=telemt
LOG_FILE="/tmp/log/telemt.log"
PID_DIR="/tmp/telemt-run"
PID_FILE="$PID_DIR/telemt.pid"
ARGS="--log-file $LOG_FILE --pid-file $PID_FILE -d /opt/etc/$PROCS/config.toml"
PREARGS=""
DESC="Telemt MTProxy"
PATH=/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin

mkdir -p /tmp/log "$PID_DIR"
chmod 755 "$PID_DIR"
pidof telemt >/dev/null 2>&1 || rm -f "$PID_FILE"

. /opt/etc/init.d/rc.func
EOF

chmod +x "$INIT"

# --- Prepare config directory ---
mkdir -p "$CONF_DIR/tlsfront"

if [ "$KEEP_CONFIG" -eq 1 ]; then
    echo "Оставляю существующий конфиг $CONF"
    AUTH_HEADER=$(grep -m1 '^auth_header' "$CONF" | cut -d '"' -f 2)
    PORT=$(grep -m1 -E '^port *=' "$CONF" | sed 's/.*= *//')
    API_ADDR=$(grep -m1 -E '^listen *=' "$CONF" | cut -d '"' -f 2)
else
    if [ -f "$CONF" ]; then
        BAK="$CONF.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "$CONF" "$BAK"
        echo "Старый конфиг сохранён в $BAK (там старый секрет, удалите после проверки)"
    fi

    echo "Writing config.toml..."

    cat > "$CONF" <<EOF
[general]
use_middle_proxy = false
log_level = "silent"
upstream_connect_failfast_hard_errors = false
beobachten_file = "/tmp/cache/beobachten.txt"


[server]
port = $PORT

[server.api]
enabled = true
listen = "127.0.0.1:9091"
whitelist = [ "127.0.0.1/32", "::1/128" ]
minimal_runtime_enabled = true
minimal_runtime_cache_ttl_ms = 1000
read_only = $READONLY_FLAG
auth_header = "$AUTH_HEADER"

[[server.listeners]]
ip = "$PUBLIC_IP"

[censorship]
tls_domain = "$TLS_DOMAIN"
mask = true
tls_emulation = true
tls_front_dir = "$CONF_DIR/tlsfront"
mask_host = "$TLS_DOMAIN"
mask_shape_hardening_aggressive_mode = true

[access.users]
$USERNAME = "$USER_SECRET"

[[upstreams]]
type = "direct"
bindtodevice = "$UP_IFACE"
EOF
    API_ADDR="127.0.0.1:9091"
fi

# --- Start and verify ---
diagnose() {
    echo ""
    echo "ERROR: Telemt не стартовал. Запускаю в foreground на 10 секунд с debug-логом:"
    "$INIT" stop >/dev/null 2>&1 || true
    killall telemt >/dev/null 2>&1 || true
    mkdir -p "$PID_DIR"
    chmod 755 "$PID_DIR"
    RUST_LOG=debug telemt --foreground --pid-file "$PID_FILE" "$CONF" >/tmp/telemt-diag.log 2>&1 &
    DIAG_PID=$!
    sleep 10
    kill "$DIAG_PID" >/dev/null 2>&1 || true
    head -n 40 /tmp/telemt-diag.log
    echo "(полный вывод: /tmp/telemt-diag.log)"
    exit 1
}

echo "Restarting Telemt..."
"$INIT" restart || diagnose

echo "Ожидание API (запуск занимает около 10 секунд)..."
API_OK=0
i=0
while [ "$i" -lt 30 ]; do
    if curl -s -f -H "Authorization: $AUTH_HEADER" "http://$API_ADDR/v1/users" >/dev/null 2>&1; then
        API_OK=1
        break
    fi
    i=$((i+1))
    sleep 1
done
[ "$API_OK" -eq 1 ] || diagnose

echo ""
echo "=== Telemt installed and running ==="
echo "Port: $PORT"
if [ "$KEEP_CONFIG" -eq 0 ]; then
    echo "IP: $PUBLIC_IP"
    echo "TLS domain: $TLS_DOMAIN"
    echo "User: $USERNAME"
    echo "Secret: $USER_SECRET"
    echo "Upstream interface: $UP_IFACE"
fi
echo "tlsfront directory: $CONF_DIR/tlsfront"
echo "Статус: telemt status --pid-file $PID_FILE"
echo ""
curl -H "Authorization: $AUTH_HEADER" -s "http://$API_ADDR/v1/users" | jq -r '.data[] | "[\(.username)]", (.links.classic[]? | "classic: \(.)"), (.links.secure[]? | "secure: \(.)"), (.links.tls[]? | "tls: \(.)"), ""'
echo ""
echo "⚠️ Не забудьте открыть порт $PORT в межсетевом экране!!!"
echo "Межсетевой экран -> Добавить правило -> Порт назначения равен $PORT. ✅ Включить правило. -> Сохранить"
echo "⚠️Если у вас не внешний IP, т.е. от провайдера вы получаете IP первый октет(цифра) которого 10|100|172|192, то подключиться к прокси вы сможете только внутри вашей локальной сети.⚠️"
echo "Очистка временных файлов"
rm -rf "$TMPDIR"
