#!/bin/bash

# Get a list of all network interfaces (excluding loopback)
interfaces=$(ls /sys/class/net | grep -v lo)

should_down()
{
        # Check if the interface is disconnected (carrier not detected)
        if [[ -f "/sys/class/net/$1/carrier" && "$(cat /sys/class/net/$1/carrier)" == "0" ]]; then
            return 1
        fi

        # Check if the interface is bridged by USB (PCI -> USB -> ethernet)
        if [[ "$1" =~ enp0s[0-9]{1,}f[0-9]u[0-9]{1,} ]] ; then
            # Naming convention documentation: https://www.freedesktop.org/software/systemd/man/latest/systemd.net-naming-scheme.html
            # Table 3: slot naming schemes
            #  en            --> ethernet
            #  p0            --> PCI domain 0
            #  s[0-9]{1,}    --> PCI slot 0 or higher, seems to be decimal from code (safe_atou*())
            #  f[0-9]        --> PCI function 0 to 9
            #  u[0-9]{1,}    --> USB port 0 or higher
            #
            # Minh has "enp0s20f0u7u4", which matches and additionally is behind a second USB port (u7u4).
            return 1
        fi

        return 0
}

for iface in $interfaces; do
        if [[ $(should_down $iface) == "1" ]]; then
            echo "downing iface $iface"
            ip link set dev $iface down
        else
            echo "up iface $iface"
        fi
done
