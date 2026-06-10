#!/bin/bash

# AmneziaWG Suite v3.3.0 - Ultimate OpenWrt Installer
# For GL-MT3600BE and other aarch64 OpenWrt routers

ROUTER_IP="192.168.1.1"
ROUTER_USER="root"
VERSION="v3.3.0 LTS"
ARCHIVE="amneziawg_installer.tar.gz"

echo "======================================================="
echo "   AmneziaWG Suite $VERSION - Installer"
echo "======================================================="

# 1. Check dependencies
if ! command -v sshpass &> /dev/null; then
    echo "[*] Installing sshpass..."
    sudo apt-get update && sudo apt-get install -y sshpass
fi

# 2. Get Password
if [ -z "$SSH_PASS" ]; then
    read -s -p "Enter password for $ROUTER_USER@$ROUTER_IP: " SSH_PASS
    echo ""
fi

# 3. Create Deployment Package
echo "[*] Preparing installer package..."
tar -czf "$ARCHIVE" \
    amneziawg-go awg-new \
    amneziawg-start.sh amneziawg-stop.sh amneziawg-switch.sh \
    amneziawg-dns.sh amneziawg-rescue.sh awg-watchdog.sh \
    amneziawg_init amneziawg.lua amneziawg_config.uci \
    install.sh

# 4. Upload and Execute
echo "[*] Connecting to router at $ROUTER_IP..."
if ! ping -c 1 -W 2 "$ROUTER_IP" > /dev/null; then
    echo "[!] ERROR: Router not reachable."
    exit 1
fi

echo "[*] Uploading files..."
sshpass -p "$SSH_PASS" scp -O -o StrictHostKeyChecking=no "$ARCHIVE" "$ROUTER_USER@$ROUTER_IP:/tmp/"

echo "[*] Running installation on router..."
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$ROUTER_USER@$ROUTER_IP" << EOT
    cd /tmp
    tar -xzf $ARCHIVE
    chmod +x install.sh
    ./install.sh
    rm $ARCHIVE install.sh
EOT

if [ $? -eq 0 ]; then
    echo "======================================================="
    echo "[SUCCESS] AmneziaWG Suite $VERSION installed!"
    echo "[INFO] Panel: http://$ROUTER_IP/cgi-bin/luci/admin/services/amneziawg"
    echo "======================================================="
else
    echo "[!] ERROR: Installation failed."
fi

# Cleanup local archive
rm "$ARCHIVE"
