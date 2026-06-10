#!/bin/sh
# Ultimate AmneziaWG Fixer for OpenWrt aarch64
CONF="/etc/amneziawg/awg0_final.conf"
IFACE="awg0"

echo "--- Начинаю глубокое исправление AmneziaWG ---"

# 1. Остановка и очистка
/usr/bin/amneziawg-stop.sh >/dev/null 2>&1
killall amneziawg-go 2>/dev/null
sleep 2

# 2. Запуск драйвера
/usr/bin/amneziawg-go "$IFACE" &
sleep 3

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "ОШИБКА: Драйвер не создал интерфейс!"
    exit 1
fi

# 3. Извлечение и чистка параметров из конфига
parse_val() {
    grep -i "$1" "$CONF" | awk -F'[ =]+' '{print $3}' | cut -d'-' -f1 | tr -d '\r'
}

JC=$(parse_val "Jc")
JMIN=$(parse_val "Jmin")
JMAX=$(parse_val "Jmax")
S1=$(parse_val "S1")
S2=$(parse_val "S2")
S3=$(parse_val "S3")
S4=$(parse_val "S4")
H1=$(parse_val "H1")
H2=$(parse_val "H2")
H3=$(parse_val "H3")
H4=$(parse_val "H4")
IP=$(parse_val "Address")
PUB=$(parse_val "PublicKey")
PSK=$(parse_val "PresharedKey")
END=$(parse_val "Endpoint")

echo "[*] Параметры: JC=$JC, S1=$S1, H1=$H1, IP=$IP"

# 4. Установка ключей и маскировки
PRIV=$(grep "PrivateKey" "$CONF" | awk '{print $3}' | tr -d '\r')
echo "$PRIV" > /tmp/priv.key
echo "$PSK" > /tmp/psk.key

echo "[*] Применяю настройки интерфейса..."
/usr/bin/awg-new set "$IFACE" \
    private-key /tmp/priv.key \
    jc "$JC" jmin "$JMIN" jmax "$JMAX" \
    s1 "$S1" s2 "$S2" s3 "$S3" s4 "$S4" \
    h1 "$H1" h2 "$H2" h3 "$H3" h4 "$H4"

echo "[*] Применяю настройки пира..."
/usr/bin/awg-new set "$IFACE" peer "$PUB" \
    preshared-key /tmp/psk.key \
    endpoint "$END" \
    allowed-ips 0.0.0.0/0 \
    persistent-keepalive 25

# 5. Сетевая настройка
ip addr add "$IP" dev "$IFACE"
ip link set mtu 1280 dev "$IFACE"
ip link set "$IFACE" up

# 6. Маршруты
GW=$(ip route show default | awk '/default/ {print $3}' | head -n1)
DEV=$(ip route show default | awk '/default/ {print $5}' | head -n1)
E_IP=$(echo "$END" | cut -d: -f1)

if [ -n "$E_IP" ] && [ -n "$GW" ]; then
    ip route add "$E_IP" via "$GW" dev "$DEV" 2>/dev/null
fi
ip route add 0.0.0.0/1 dev "$IFACE"
ip route add 128.0.0.0/1 dev "$IFACE"

echo "[*] Ожидание рукопожатия..."
sleep 8
/usr/bin/awg-new show "$IFACE"

rm /tmp/priv.key /tmp/psk.key
