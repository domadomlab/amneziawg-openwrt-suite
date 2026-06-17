#!/bin/sh

# AmneziaWG / Shuka Hybrid - Emergency Restore Script
# This script forcefully stops all VPN connections and restores direct internet.

echo "Starting Emergency Rescue (Manual Trigger)..."

# 1. Force stop Shuka Manager (Hybrid Engine)
if [ -x "/usr/bin/shuka_manager.py" ]; then
    /usr/bin/shuka_manager.py stop >/dev/null 2>&1
fi

# 2. Force stop legacy Amnezia processes
killall amneziawg-go 2>/dev/null
killall sing-box 2>/dev/null
/etc/init.d/amneziawg stop 2>/dev/null
/usr/bin/amneziawg-stop.sh 2>/dev/null

# 3. Clean up interfaces
ip link delete awg0 2>/dev/null
ip link delete tun-shuka 2>/dev/null

# 4. Clean up routing and firewall
while ip route del 0.0.0.0/1 2>/dev/null; do :; done
while ip route del 128.0.0.0/1 2>/dev/null; do :; done
ip route flush cache

# 5. Restore DNS configuration from backup (if exists)
if [ -f /etc/config/dhcp.bak_gemini ]; then
    cp /etc/config/dhcp.bak_gemini /etc/config/dhcp
fi

# 6. Re-enable IPv6 in UCI (Default behavior)
uci set network.globals.disable_ipv6='0' 2>/dev/null
uci set network.lan.ipv6='1' 2>/dev/null
uci set network.wan.ipv6='1' 2>/dev/null
uci set dhcp.lan.dhcpv6='server' 2>/dev/null
uci commit network 2>/dev/null
uci commit dhcp 2>/dev/null

# 7. Restart essential services
/etc/init.d/network restart 2>/dev/null
/etc/init.d/dnsmasq restart 2>/dev/null

echo "Emergency Rescue Complete. Direct internet connection restored."
