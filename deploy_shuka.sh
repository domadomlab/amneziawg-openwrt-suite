#!/bin/bash

# Shuka & Sing-box Hybrid Deployer

ROUTER_IP="192.168.1.1"
ROUTER_USER="root"
ARCHIVE="shuka_deployment.tar.gz"

echo "[*] Preparing Shuka deployment package..."
tar -czf "$ARCHIVE" \
    sing-box shuka_manager.py \
    sing-box.init shuka_hybrid.lua \
    config.json.example install_shuka.sh

echo "[*] Uploading to $ROUTER_IP..."
if [ -z "$SSH_PASS" ]; then
    read -s -p "Enter password: " SSH_PASS
    echo ""
fi

sshpass -p "$SSH_PASS" scp -O -o StrictHostKeyChecking=no "$ARCHIVE" "$ROUTER_USER@$ROUTER_IP:/tmp/"

echo "[*] Executing installer..."
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$ROUTER_USER@$ROUTER_IP" << EOT
    cd /tmp
    tar -xzf $ARCHIVE
    chmod +x install_shuka.sh
    ./install_shuka.sh
    rm $ARCHIVE install_shuka.sh
EOT

rm "$ARCHIVE"
echo "[SUCCESS] Shuka Hybrid Suite deployed!"
