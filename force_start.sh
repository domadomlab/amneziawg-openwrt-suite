#!/bin/sh
# Скрипт для принудительной установки и диагностики AmneziaWG
CONF="/etc/amneziawg/awg0_final.conf"
IFACE="awg0"

echo "[*] 1. Очистка старых интерфейсов и процессов..."
/usr/bin/amneziawg-stop.sh >/dev/null 2>&1
killall amneziawg-go 2>/dev/null
sleep 1

echo "[*] 2. Запуск amneziawg-go..."
/usr/bin/amneziawg-go "$IFACE" &
sleep 2

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    echo "!!! ОШИБКА: Интерфейс $IFACE не создан драйвером amneziawg-go"
    exit 1
fi

echo "[*] 3. Парсинг IP из конфига..."
IP=$(grep -i "Address" "$CONF" | awk -F'[ =]+' '{print $3}')
if [ -z "$IP" ]; then IP="10.8.1.23/32"; fi
echo "Используем IP: $IP"

echo "[*] 4. Подготовка конфига для awg-new..."
sed -e '/^[[:space:]]*Address/d' -e '/^[[:space:]]*DNS/d' "$CONF" > /tmp/awg_clean.conf

echo "[*] 5. Настройка интерфейса..."
ip addr add "$IP" dev "$IFACE"
/usr/bin/awg-new setconf "$IFACE" /tmp/awg_clean.conf

echo "[*] 6. Активация интерфейса..."
ip link set mtu 1280 dev "$IFACE"
ip link set "$IFACE" up

echo "[*] 7. Настройка маршрутов..."
# Определяем текущий шлюз
GW=$(ip route show default | awk '/default/ {print $3}' | head -n1)
DEV=$(ip route show default | awk '/default/ {print $5}' | head -n1)
# Маршрут к Endpoint (обязателен для работы туннеля)
ENDPOINT=$(grep -i "Endpoint" "$CONF" | awk -F'[ =:]+' '{print $3}')

if [ -n "$ENDPOINT" ] && [ -n "$GW" ]; then
    ip route add "$ENDPOINT" via "$GW" dev "$DEV" 2>/dev/null
fi

# Глобальный трафик
ip route add 0.0.0.0/1 dev "$IFACE"
ip route add 128.0.0.0/1 dev "$IFACE"

echo "[*] ФИНАЛЬНАЯ ПРОВЕРКА:"
/usr/bin/awg-new show "$IFACE"
ip addr show "$IFACE"
ip route | grep "$IFACE"
