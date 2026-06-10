#!/bin/bash
PROFILE=$1

if [ -z "$PROFILE" ]; then
    echo "Usage: $0 <profile_name.conf>"
    exit 1
fi

PROFILE_PATH="/etc/amneziawg/profiles/$PROFILE"

if [ ! -f "$PROFILE_PATH" ]; then
    echo "Error: Profile $PROFILE_PATH not found"
    exit 1
fi

echo "Switching to profile: $PROFILE"

# Save as last profile and active
if command -v uci >/dev/null; then
    uci set amneziawg.config.last_profile="$PROFILE"
    uci commit amneziawg
fi

# Stop current
/usr/bin/amneziawg-stop.sh

# Install new
cp "$PROFILE_PATH" /etc/amneziawg/awg0.conf

# Start
/usr/bin/amneziawg-start.sh
