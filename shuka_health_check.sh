#!/bin/sh

# Проверяем, активен ли VPN (по наличию интерфейса)
if ! ip link show awg0 >/dev/null 2>&1 && ! ip link show tun-shuka >/dev/null 2>&1; then
    # VPN не запущен, проверять нечего
    exit 0
fi

# Пингуем Google DNS 3 раза с интервалом 1 секунда, таймаут 2 сек.
if ping -c 3 -W 2 -q mail.ru >/dev/null 2>&1; then
    # Пинг успешен
    exit 0
fi

# Если мы здесь, значит пинг не прошел. Делаем вторую попытку через 10 секунд
sleep 10

if ping -c 3 -W 2 -q mail.ru >/dev/null 2>&1; then
    exit 0
fi

# Если интернет реально мертв, отключаем VPN
echo "[$(date)] VPN Connection is DEAD. Stopping Shuka VPN to restore Internet." >> /var/log/shuka_health.log
/usr/bin/shuka_manager.py stop
ip route flush cache
