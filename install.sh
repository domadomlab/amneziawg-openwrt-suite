#!/bin/sh
echo "--- Starting AmneziaWG Suite v3.3.0 Installation ---"

# 1. Очистка конфликтов
killall amneziawg-go 2>/dev/null
rmmod amneziawg 2>/dev/null
opkg remove amneziawg-tools --force-depends 2>/dev/null
opkg remove kmod-amneziawg --force-depends 2>/dev/null

# 2. Установка зависимостей
opkg update
for pkg in "iptables" "ip-full" "kmod-tun" "luci" "curl"; do
    opkg list-installed | grep -q "$pkg" || opkg install "$pkg"
done

# 3. Копирование файлов
mkdir -p /etc/amneziawg/profiles
cp amneziawg-go /usr/bin/
cp awg-new /usr/bin/
cp amneziawg-start.sh /usr/bin/
cp amneziawg-stop.sh /usr/bin/
cp amneziawg-switch.sh /usr/bin/
cp amneziawg-dns.sh /usr/bin/
cp amneziawg-rescue.sh /usr/bin/
cp awg-watchdog.sh /usr/bin/
cp amneziawg_init /etc/init.d/amneziawg

# Настройка LuCI
mkdir -p /usr/lib/lua/luci/controller/
cp amneziawg.lua /usr/lib/lua/luci/controller/amneziawg.lua

# Установка конфига UCI
[ -f /etc/config/amneziawg ] || cp amneziawg_config.uci /etc/config/amneziawg

# 4. Настройка "Бессмертного" фаервола (модель Keenetic)
cat << 'EOF' > /etc/firewall.user
# ПРИНУДИТЕЛЬНЫЙ ПЕРЕХВАТ DNS
iptables -t nat -I PREROUTING -i br-lan -p udp --dport 53 -j REDIRECT --to-ports 53
iptables -t nat -I PREROUTING -i br-lan -p tcp --dport 53 -j REDIRECT --to-ports 53

# БЛОКИРОВКА ОБХОДОВ (DoT и QUIC)
iptables -I FORWARD -p tcp --dport 853 -j REJECT
iptables -I FORWARD -p udp --dport 853 -j REJECT
iptables -I FORWARD -p udp --dport 443 -j REJECT

# МАСКИРОВКА TTL
iptables -t mangle -I POSTROUTING -j TTL --ttl-set 64

# FIX MTU/MSS
iptables -t mangle -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# БЛОКИРОВКА IPv6 (Защита от утечек)
ip6tables -I FORWARD -j REJECT
ip6tables -I INPUT -j REJECT
EOF

# 5. Права и автозагрузка
chmod +x /usr/bin/amneziawg* /usr/bin/awg* /etc/init.d/amneziawg
/etc/init.d/amneziawg enable
/etc/init.d/firewall restart

# Очистка кэша LuCI
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache

echo "--- INSTALLATION COMPLETE! Please open LuCI Services -> AmneziaWG ---"
