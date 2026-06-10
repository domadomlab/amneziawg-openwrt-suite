#!/bin/bash

# Скрипт экстренного восстановления интернета на роутере (192.168.1.1)
# Удаляет все следы AmneziaWG и возвращает прямое соединение

ROUTER_IP="192.168.1.1"
ROUTER_USER="root"

echo "-------------------------------------------------------"
echo "   RESCUE SCRIPT: Восстановление интернета на роутере"
echo "-------------------------------------------------------"

# 1. Запрос пароля
read -s -p "Введите пароль для $ROUTER_USER@$ROUTER_IP: " SSH_PASS
echo ""

# 2. Проверка sshpass
if ! command -v sshpass &> /dev/null; then
    echo "[*] Установка sshpass..."
    sudo apt-get update && sudo apt-get install -y sshpass
fi

# 3. Выполнение команд восстановления через SSH
echo "[*] Подключение к роутеру и очистка настроек..."

sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$ROUTER_USER@$ROUTER_IP" << 'EOF'
    echo "[1/5] Остановка процессов AmneziaWG..."
    killall amneziawg-go 2>/dev/null
    /etc/init.d/amneziawg stop 2>/dev/null
    /usr/bin/amneziawg-stop.sh 2>/dev/null

    echo "[2/5] Принудительное удаление маршрутов..."
    # Удаляем специфичные VPN маршруты, если они остались
    while ip route del 0.0.0.0/1 2>/dev/null; do :; done
    while ip route del 128.0.0.0/1 2>/dev/null; do :; done
    
    # Удаляем маршруты к любым внешним IP через awg0
    ip route show | grep awg0 | awk '{print $1}' | while read -r route; do
        ip route del $route 2>/dev/null
    done

    echo "[3/5] Очистка Firewall (NAT и Forward)..."
    while iptables -t nat -D POSTROUTING -o awg0 -j MASQUERADE 2>/dev/null; do :; done
    while iptables -D FORWARD -i br-lan -o awg0 -j ACCEPT 2>/dev/null; do :; done
    while iptables -D FORWARD -i awg0 -o br-lan -j ACCEPT 2>/dev/null; do :; done

    echo "[4/5] Восстановление DNS провайдера..."
    if command -v uci >/dev/null; then
        uci set network.wan.peerdns='1'
        uci del network.wan.dns 2>/dev/null
        uci commit network
        /etc/init.d/dnsmasq restart 2>/dev/null
    fi

    echo "[5/5] Удаление проблемной конфигурации..."
    rm -f /etc/amneziawg/awg0_final.conf
    rm -f /etc/amneziawg/awg0_final.conf.bak
    ip link delete awg0 2>/dev/null
    
    echo "[*] Сброс кэша маршрутизации..."
    ip route flush cache
    
    echo "--- ОЧИСТКА ЗАВЕРШЕНА. Проверка интернета (ping 8.8.8.8) ---"
    ping -c 3 8.8.8.8 || echo "!!! Интернет всё еще не доступен. Возможно, проблема в физическом линке или WAN."
EOF

if [ $? -eq 0 ]; then
    echo "-------------------------------------------------------"
    echo "[SUCCESS] Роутер очищен, интернет должен работать напрямую."
    echo "-------------------------------------------------------"
else
    echo "[!] Ошибка при подключении к роутеру. Проверьте пароль."
fi
