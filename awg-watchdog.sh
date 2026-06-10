#!/bin/sh
AWG_TOOL="/usr/bin/awg-new"
IFACE="awg0"

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    logger -t awg-watchdog "Interface $IFACE missing, restarting..."
    /etc/init.d/amneziawg restart
    exit 0
fi

LATEST=$( "$AWG_TOOL" show "$IFACE" latest-handshake | awk '{print $NF}' )
[ -z "$LATEST" ] && LATEST=0
NOW=$(date +%s)

if [ "$LATEST" -eq 0 ] || [ $((NOW - LATEST)) -gt 180 ]; then
    logger -t awg-watchdog "Handshake too old ($((NOW - LATEST))s) or never happened, restarting..."
    /etc/init.d/amneziawg restart
fi
