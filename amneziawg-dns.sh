#!/bin/sh

MODE=$1 # on_dot, on_xbox, off, status
IFACE="awg0"
XBOX_DNS1="176.99.11.77"
XBOX_DNS2="80.78.247.254"
XBOX_PROXY="87.228.47.204"
WAN_GW=$(uci -q get network.wan.gateway || ip route show default | grep -v "$IFACE" | awk '/default/ {print $3}' | head -n 1)

case "$MODE" in
    "on_xbox")
        echo "Switching to Xbox DNS (SmartDNS + Force Proxy)..."
        
        # 1. Basic DNS servers
        uci del dhcp.@dnsmasq[0].server 2>/dev/null
        uci add_list dhcp.@dnsmasq[0].server="$XBOX_DNS1"
        uci add_list dhcp.@dnsmasq[0].server="$XBOX_DNS2"
        uci set dhcp.@dnsmasq[0].noresolv='1'
        uci set dhcp.@dnsmasq[0].filter_aaaa='1'
        
        # 2. Force Proxy IPs for Google AI (Safe fallback)
        uci del dhcp.@dnsmasq[0].address 2>/dev/null
        for d in gemini.google.com notebooklm.google ai.google.com generativelanguage.googleapis.com alkalicognition-pa.googleapis.com proactivebackend-pa.googleapis.com; do
            uci add_list dhcp.@dnsmasq[0].address="/$d/$XBOX_PROXY"
        done

        # 3. Routes via WAN (Keenetic model)
        if [ -n "$WAN_GW" ]; then
            ip route add $XBOX_DNS1 via $WAN_GW 2>/dev/null || ip route replace $XBOX_DNS1 via $WAN_GW
            ip route add $XBOX_DNS2 via $WAN_GW 2>/dev/null || ip route replace $XBOX_DNS2 via $WAN_GW
            ip route add $XBOX_PROXY via $WAN_GW 2>/dev/null || ip route replace $XBOX_PROXY via $WAN_GW
        fi
        
        # 4. GL.iNet Force DNS
        uci set gl-dns.@dns[0].force_dns='1'
        uci set amneziawg.config.dns_mode='xbox'
        ;;
    "on_dot")
        echo "Switching to Safe DNS (Cloudflare/Google)..."
        uci del dhcp.@dnsmasq[0].server 2>/dev/null
        uci del dhcp.@dnsmasq[0].address 2>/dev/null
        uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
        uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
        uci set dhcp.@dnsmasq[0].noresolv='1'
        uci set dhcp.@dnsmasq[0].filter_aaaa='1'
        uci set gl-dns.@dns[0].force_dns='1'
        uci set amneziawg.config.dns_mode='dot'
        ;;
    "off")
        echo "Switching to Default DNS..."
        uci del dhcp.@dnsmasq[0].server 2>/dev/null
        uci del dhcp.@dnsmasq[0].address 2>/dev/null
        uci set dhcp.@dnsmasq[0].noresolv='0'
        uci set dhcp.@dnsmasq[0].filter_aaaa='0'
        uci set gl-dns.@dns[0].force_dns='0'
        uci set amneziawg.config.dns_mode='default'
        
        # Cleanup routes
        ip route del $XBOX_DNS1 2>/dev/null
        ip route del $XBOX_DNS2 2>/dev/null
        ip route del $XBOX_PROXY 2>/dev/null
        ;;
    "status")
        uci -q get amneziawg.config.dns_mode || echo "default"
        exit 0
        ;;
esac

uci commit dhcp
uci commit gl-dns
uci commit amneziawg
/etc/init.d/dnsmasq restart
/etc/init.d/gl_dns restart
