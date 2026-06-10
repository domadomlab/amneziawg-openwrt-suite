#!/bin/sh
# Сетевой отладчик для роутера
CONF="/etc/amneziawg/awg0_final.conf"

echo "--- 1. Пинг сервера ---"
ping -c 2 167.17.183.41

echo "--- 2. Смена MTU на 1200 ---"
ip link set dev awg0 mtu 1200

echo "--- 3. Пересоздание пира ---"
PUB=$(grep "PublicKey" "$CONF" | awk '{print $3}' | tr -d '\r')
PSK=$(grep "PresharedKey" "$CONF" | awk '{print $3}' | tr -d '\r')
END=$(grep "Endpoint" "$CONF" | awk '{print $3}' | tr -d '\r')

echo "$PSK" > /tmp/psk.tmp
/usr/bin/awg-new set awg0 peer "$PUB" remove 2>/dev/null
sleep 1
/usr/bin/awg-new set awg0 peer "$PUB" preshared-key /tmp/psk.tmp endpoint "$END" allowed-ips 0.0.0.0/0
rm /tmp/psk.tmp

echo "--- 4. Пинг через туннель ---"
ping -I awg0 -c 4 1.1.1.1

echo "--- 5. Итоговый статус ---"
/usr/bin/awg-new show awg0
