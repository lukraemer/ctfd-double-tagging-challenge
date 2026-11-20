#! /bin/sh
set -eu

# Wait for the veth ends attached by containerlab.
i=0
while [ "$i" -lt 60 ]; do
    if [ -e /sys/class/net/eth1 ] && [ -e /sys/class/net/eth2 ]; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

if ! [ -e /sys/class/net/eth2 ]; then
    echo "router: lab interfaces did not appear" >&2
    exit 1
fi

ip link set eth1 up
ip link set eth2 up
ip addr replace 192.168.0.1/24 dev eth1
ip addr replace 192.168.20.1/24 dev eth2

sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0
sysctl -w net.ipv4.conf.eth1.rp_filter=0 2>/dev/null || true
sysctl -w net.ipv4.conf.eth2.rp_filter=0 2>/dev/null || true

# Block VLAN 10 -> VLAN 20. Only replies from VLAN 20 to VLAN 10 are allowed,
# so the victim can answer the attacker but the attacker cannot reach the
# victim over L3.
iptables -F FORWARD
iptables -P FORWARD DROP
iptables -A FORWARD -i eth2 -o eth1 -j ACCEPT

echo "router ready"
iptables -S FORWARD

exec tail -f /dev/null
