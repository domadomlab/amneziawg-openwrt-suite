#!/bin/sh
# Форсированный запуск с ручной установкой всех параметров AmneziaWG
IFACE="awg0"
CONF="/etc/amneziawg/awg0_final.conf"

/usr/bin/amneziawg-stop.sh >/dev/null 2>&1
killall amneziawg-go 2>/dev/null
sleep 1

/usr/bin/amneziawg-go "$IFACE" &
sleep 2

# Ручная установка КАЖДОГО параметра через awg-new set
echo "[*] Установка интерфейса..."
/usr/bin/awg-new set "$IFACE" \
    private-key <(grep "PrivateKey" "$CONF" | awk '{print $3}') \
    listen-port 51820 \
    jc 5 jmin 10 jmax 50 \
    s1 74 s2 106 s3 18 s4 2 \
    h1 1138274689 h2 2144085124 h3 2147391471 h4 2147483115

echo "[*] Установка пира..."
PUB=$(grep "PublicKey" "$CONF" | awk '{print $3}')
PSK=$(grep "PresharedKey" "$CONF" | awk '{print $3}')
END=$(grep "Endpoint" "$CONF" | awk '{print $3}')

# Создаем временные файлы для ключей, чтобы избежать инъекций
echo "$PSK" > /tmp/psk.key

/usr/bin/awg-new set "$IFACE" peer "$PUB" \
    preshared-key /tmp/psk.key \
    endpoint "$END" \
    allowed-ips 0.0.0.0/0 \
    persistent-keepalive 25

ip addr add 10.8.1.23/32 dev "$IFACE"
ip link set mtu 1280 dev "$IFACE"
ip link set "$IFACE" up

echo "[*] Проверка связи с сервером..."
ping -c 3 167.17.183.41

echo "[*] Ожидание рукопожатия (10 сек)..."
sleep 10
/usr/bin/awg-new show all
rm /tmp/psk.key
