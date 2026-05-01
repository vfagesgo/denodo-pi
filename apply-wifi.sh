#!/bin/bash

CONF=/boot/firmware/denodo/denodo_config.env

# ---- 1. Load environment variables if present
if [ -f $CONF ]; then
    set -o allexport
    source $CONF
    set +o allexport
else
    echo "💩 - No config file found"
    exit 0
fi

SSID=${SSID:-"denodo"} 
PSK=${PSK:-"denodo"} 
COUNTRY=${COUNTRY:-"FR"} 

cat > /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
country=$COUNTRY
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
    ssid="$SSID"
    psk="$PSK"
}
EOF

systemctl restart dhcpcd
systemctl restart wpa_supplicant