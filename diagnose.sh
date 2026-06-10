#!/bin/sh
# Диагностический скрипт для роутера
echo "--- Шаг 1: Проверка TUN устройства ---"
ls -l /dev/net/tun || echo "ОШИБКА: /dev/net/tun отсутствует!"

echo "--- Шаг 2: Очистка старых процессов ---"
/usr/bin/amneziawg-stop.sh >/dev/null 2>&1
killall amneziawg-go 2>/dev/null
sleep 1

echo "--- Шаг 3: Тестовый запуск драйвера ---"
# Запускаем amneziawg-go в фоне
/usr/bin/amneziawg-go awg0 &
sleep 3

if ip link show awg0 >/dev/null 2>&1; then
    echo "УСПЕХ: Интерфейс awg0 создан."
    
    CONF="/etc/amneziawg/awg0_final.conf"
    if [ ! -f "$CONF" ]; then
        echo "ОШИБКА: Конфиг $CONF не найден!"
        exit 1
    fi
    
    # Парсим IP
    IP=$(grep -i "Address" "$CONF" | awk -F'[ =]+' '{print $3}')
    echo "Назначаем IP: $IP"
    
    # Готовим чистый конфиг
    sed -e '/^[[:space:]]*Address/d' -e '/^[[:space:]]*DNS/d' "$CONF" > /tmp/awg_test.conf
    
    ip addr add "$IP" dev awg0
    /usr/bin/awg-new setconf awg0 /tmp/awg_test.conf
    
    if [ $? -eq 0 ]; then
        echo "УСПЕХ: Конфигурация загружена."
        ip link set mtu 1280 dev awg0
        ip link set awg0 up
        sleep 2
        /usr/bin/awg-new show awg0
    else
        echo "ОШИБКА при загрузке конфига через awg-new."
    fi
else
    echo "ОШИБКА: Интерфейс awg0 не появился."
fi
