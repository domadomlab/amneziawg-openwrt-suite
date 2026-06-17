#!/bin/sh
IFACE="awg0"
AWG_BIN="/usr/bin/amneziawg-go"
AWG_TOOL="/usr/bin/awg-new"
CONF="/etc/amneziawg/awg0.conf"
LOG="/tmp/awg_health.log"

echo "[$(date)] --- STARTING VPN ---" > "$LOG"

# 1. Stop if running (fast)
ip link delete "$IFACE" 2>/dev/null
killall amneziawg-go 2>/dev/null

# 2. Create clean config for setconf
grep -vE "Address|DNS|^I[2-5]" "$CONF" | tr -d '\r' > /tmp/awg_clean.conf

# 3. Create interface (Kernel first, then Go)
if ! ip link show "$IFACE" >/dev/null 2>&1; then
    ip link add dev "$IFACE" type amneziawg 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "Kernel module missing, using userspace..." >> "$LOG"
        "$AWG_BIN" "$IFACE" &
        # Wait just a bit for Go driver
        for i in 1 2 3 4 5; do
            ip link show "$IFACE" >/dev/null 2>&1 && break
            sleep 0.5
        done
    fi
fi

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "FAILED to create interface" >> "$LOG"
    exit 1
fi

# 4. Apply config (Fast)
"$AWG_TOOL" setconf "$IFACE" /tmp/awg_clean.conf
IP_ADDR=$(grep -i "Address" "$CONF" | awk -F'[ =]+' '{print $2}' | tr -d '\r ')
ip addr add "${IP_ADDR:-10.8.1.23/32}" dev "$IFACE"
ip link set mtu 1280 dev "$IFACE"
ip link set "$IFACE" up

# 5. Routes and Firewall (Fast)
# Get gateway only if needed
GW=$(ip route show default | awk '/default/ {print $3}' | head -n1)
DEV=$(ip route show default | awk '/default/ {print $5}' | head -n1)
ENDPOINT=$(grep -i "Endpoint" "$CONF" | awk -F'[ =]+' '{print $2}' | tr -d '\r ')
ENDPOINT_IP=$(echo "$ENDPOINT" | cut -d: -f1)

if [ -n "$GW" ] && [ -n "$ENDPOINT_IP" ]; then
    ip route add "$ENDPOINT_IP" via "$GW" dev "$DEV" 2>/dev/null
fi
ip route add 0.0.0.0/1 dev "$IFACE"
ip route add 128.0.0.0/1 dev "$IFACE"

iptables -t nat -I POSTROUTING -o "$IFACE" -j MASQUERADE
iptables -I FORWARD -i br-lan -o "$IFACE" -j ACCEPT
iptables -I FORWARD -i "$IFACE" -o br-lan -j ACCEPT

# Disable IPv6 (Fast)
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null

# 6. DNS and Health Check (Background - don't wait!)
(
    /usr/bin/amneziawg-dns.sh on >/dev/null 2>&1
    /usr/bin/amneziawg-health-check.sh &
) &

echo "OK"
