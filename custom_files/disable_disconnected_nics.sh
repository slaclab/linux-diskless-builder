#!/bin/bash

# Get a list of all network interfaces (excluding loopback)
interfaces=$(ls /sys/class/net | grep -v lo)

for iface in $interfaces; do
        # Check if the interface is disconnected (carrier detected)
        if [[ -f "/sys/class/net/$iface/carrier" ]] && [[ "$(cat /sys/class/net/$iface/carrier)" == "0" ]]; then
            ip link set dev $iface down
        fi
done
