#!/bin/sh
IFACE="awg0"
AWG_BIN="/usr/bin/amneziawg-go"
AWG_TOOL="/usr/bin/awg-new"
CONF="/etc/amneziawg/awg0.conf"
LOG="/tmp/awg_health.log"

echo "[$(date)] --- NEW VPN START ATTEMPT ---" > "$LOG"

# 1. Полная очистка перед стартом
/usr/bin/amneziawg-stop.sh >/dev/null 2>&1
sleep 2

# 2. Создание чистого конфига для setconf (убираем Address и лишнее)
grep -vE "Address|DNS|^I[2-5]" "$CONF" | tr -d '\r' > /tmp/awg_clean.conf

# 3. Запуск бинарного файла
"$AWG_BIN" "$IFACE" &
for i in $(seq 1 10); do
    ip link show "$IFACE" >/dev/null 2>&1 && break
    sleep 1
done

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "[$(date)] FAILED to create interface" >> "$LOG"
    exit 1
fi

# 4. Применение конфигурации
"$AWG_TOOL" setconf "$IFACE" /tmp/awg_clean.conf
IP_ADDR=$(grep -i "Address" "$CONF" | awk -F'[ =]+' '{print $2}' | tr -d '\r ')
ip addr add "${IP_ADDR:-10.8.1.23/32}" dev "$IFACE"
ip link set mtu 1280 dev "$IFACE"
ip link set "$IFACE" up

# 5. Маршрутизация
GW=$(ip route show default | awk '/default/ {print $3}' | head -n1)
DEV=$(ip route show default | awk '/default/ {print $5}' | head -n1)
ENDPOINT=$(grep -i "Endpoint" "$CONF" | awk -F'[ =]+' '{print $2}' | tr -d '\r ')
ENDPOINT_IP=$(echo "$ENDPOINT" | cut -d: -f1)

if [ -n "$GW" ] && [ -n "$ENDPOINT_IP" ]; then
    ip route add "$ENDPOINT_IP" via "$GW" dev "$DEV" 2>/dev/null
fi
ip route add 0.0.0.0/1 dev "$IFACE"
ip route add 128.0.0.0/1 dev "$IFACE"

# 6. Firewall NAT & Anti-Leak (Kill Switch)
iptables -t nat -I POSTROUTING -o "$IFACE" -j MASQUERADE
iptables -I FORWARD -i br-lan -o "$IFACE" -j ACCEPT
iptables -I FORWARD -i "$IFACE" -o br-lan -j ACCEPT

# Блокировка IPv6 для предотвращения утечек местоположения (важно для Google/Gemini)
ip6tables -I FORWARD -j REJECT
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1

# 7. Принудительный DNS внутри туннеля
/usr/bin/amneziawg-dns.sh on

# 8. Запуск проверки здоровья (Health Check)
# Запускаем в фоне, чтобы не блокировать вывод, но лог будет доступен
/usr/bin/amneziawg-health-check.sh &
echo "[$(date)] Setup finished. Verification in progress..." >> "$LOG"
