#!/bin/sh

# Shuka & Sing-box Installer for OpenWrt (aarch64)
# This script installs the VLESS/Reality hybrid part of the suite.

echo "[*] Starting Shuka & Sing-box installation..."

# 1. Directories
mkdir -p /etc/sing-box
mkdir -p /usr/lib/lua/luci/controller/

# 2. Binary and Scripts (assumes files are in current directory)
[ -f "./sing-box" ] && cp "./sing-box" /usr/bin/
[ -f "./shuka_manager.py" ] && cp "./shuka_manager.py" /usr/bin/
[ -f "./sing-box.init" ] && cp "./sing-box.init" /etc/init.d/sing-box

# 3. LuCI Interface
[ -f "./shuka_hybrid.lua" ] && cp "./shuka_hybrid.lua" /usr/lib/lua/luci/controller/shuka_hybrid.lua

# 4. Configuration Template
# We use config.json.template as the primary source
if [ -f "./config.json.template" ]; then
    cp "./config.json.template" /etc/sing-box/config.json.template
fi

# If config doesn't exist, create from template
if [ ! -f /etc/sing-box/config.json ] && [ -f /etc/sing-box/config.json.template ]; then
    cp /etc/sing-box/config.json.template /etc/sing-box/config.json
fi

# 5. Permissions
chmod +x /usr/bin/sing-box 2>/dev/null
chmod +x /usr/bin/shuka_manager.py 2>/dev/null
chmod +x /etc/init.d/sing-box 2>/dev/null

# 6. Enable and Start
/etc/init.d/sing-box enable
/etc/init.d/rpcd restart
# Note: We don't force start here to avoid routing conflicts with existing VPNs.
# The user should start it from the LuCI UI.

# 7. Cleanup LuCI cache
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache

echo "[OK] Shuka installation finished."
echo "[INFO] New UI: Services -> Shuka VPN"
e
# Note: We don't force start here to avoid routing conflicts with existing VPNs.
# The user should start it from the LuCI UI.

# 7. Cleanup LuCI cache
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache

echo "[OK] Shuka installation finished."
echo "[INFO] New UI: Services -> Shuka VPN"
