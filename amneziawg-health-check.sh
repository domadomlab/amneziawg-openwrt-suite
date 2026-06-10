#!/bin/sh
LOG="/tmp/awg_health.log"
IFACE="awg0"
CHECK_TARGET="8.8.8.8"

log_msg() {
    echo "[$(date)] $1" >> "$LOG"
    logger -t awg-health "$1"
}

rollback() {
    log_msg "CRITICAL: VPN Health Check FAILED. Executing Rollback..."
    /usr/bin/amneziawg-stop.sh
    log_msg "Rollback COMPLETE. Internet access should be restored."
    exit 1
}

log_msg "Starting verification for $IFACE..."

# 1. Проверка наличия интерфейса
if ! ip link show "$IFACE" >/dev/null 2>&1; then
    log_msg "ERROR: Interface $IFACE does not exist."
    rollback
fi

# 2. Проверка входящего трафика (Handshake check)
log_msg "Waiting 15 seconds for handshake and traffic..."
sleep 15

RX_BYTES=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes)
if [ "$RX_BYTES" -eq 0 ]; then
    log_msg "ERROR: Zero Rx bytes on $IFACE. No handshake?"
    # Попытка 'разбудить' соединение
    ping -c 3 -W 2 -I "$IFACE" "$CHECK_TARGET" >/dev/null 2>&1
    RX_BYTES=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes)
    if [ "$RX_BYTES" -eq 0 ]; then
        log_msg "CRITICAL: Still no Rx traffic after probe."
        rollback
    fi
fi

# 3. Проверка доступности Google
if ! ping -c 3 -W 5 -I "$IFACE" "$CHECK_TARGET" >/dev/null 2>&1; then
    log_msg "ERROR: $CHECK_TARGET is NOT reachable through VPN."
    rollback
fi

log_msg "SUCCESS: VPN is working. Rx: $RX_BYTES bytes."
exit 0
