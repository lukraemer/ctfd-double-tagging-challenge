#! /bin/sh
set -eu

# Wait for the veth end attached by containerlab.
i=0
while [ "$i" -lt 60 ]; do
    [ -e /sys/class/net/eth1 ] && break
    i=$((i + 1))
    sleep 1
done

if ! [ -e /sys/class/net/eth1 ]; then
    echo "victim: eth1 did not appear" >&2
    exit 1
fi

ip link set eth1 up
ip addr replace 192.168.20.10/24 dev eth1
ip route replace default via 192.168.20.1 dev eth1

sysctl -w net.ipv4.conf.all.rp_filter=0
sysctl -w net.ipv4.conf.default.rp_filter=0
sysctl -w net.ipv4.conf.eth1.rp_filter=0 2>/dev/null || true

exec python3 /server.py
