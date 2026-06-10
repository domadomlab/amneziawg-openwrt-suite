#!/bin/sh

# AmneziaWG Suite - Emergency Restore Script
# This script reverts DNS and IPv6 changes made for Gemini/SmartDNS optimization

echo "Starting Emergency Restore..."

# 1. Restore DNS configuration from backup
if [ -f /etc/config/dhcp.bak_gemini ]; then
    echo "Found DNS backup, restoring..."
    cp /etc/config/dhcp.bak_gemini /etc/config/dhcp
else
    echo "No DNS backup found, skipping..."
fi

# 2. Re-enable IPv6 in UCI
echo "Re-enabling IPv6 settings..."
uci set network.globals.disable_ipv6='0'
uci set network.lan.ipv6='1'
uci set network.wan.ipv6='1'
uci set dhcp.lan.dhcpv6='server'
uci commit network
uci commit dhcp

# 3. Restore and restart services
echo "Restarting network and DNS services..."
/etc/init.d/odhcpd enable 2>/dev/null
/etc/init.d/odhcpd start 2>/dev/null
/etc/init.d/stubby start 2>/dev/null
/etc/init.d/network restart 2>/dev/null
/etc/init.d/dnsmasq restart 2>/dev/null

echo "Emergency Restore Complete."
