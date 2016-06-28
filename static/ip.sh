#!/bin/sh

IFCONFIG="/sbin/ifconfig"
INTERFACES="/etc/network/interfaces"

IFACE=$(lshw -c network | grep "logical name" | awk '{print $3}')
ADDRESS=$($IFCONFIG | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
NETMASK=$($IFCONFIG | grep -w inet |grep -v 127.0.0.1| awk '{print $4}' | cut -d ":" -f 2)
GATEWAY=$(route -n|grep "UG"|grep -v "UGH"|cut -f 10 -d " ")

cat <<-IPCONFIG > "$INTERFACES"
source /etc/network/interfaces.d/*

# The loopback network interface
        auto lo $IFACE
        iface lo inet loopback

# The primary network interface
        iface $IFACE inet static
                pre-up /sbin/ethtool -K $IFACE tso off
                pre-up /sbin/ethtool -K $IFACE gso off

# Best practice is to change the static address
# to something outside your DHCP range.
                address $ADDRESS
                netmask $NETMASK
                gateway $GATEWAY

# Exit and save:	[CTRL+X] + [Y] + [ENTER]
# Exit without saving:	[CTRL+X]

IPCONFIG

exit 0
