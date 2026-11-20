#! /bin/sh
set -eu

ROLE="${SWITCH_ROLE:?SWITCH_ROLE must be set to 1 or 2}"

# containerlab attaches the veth ends after the container starts, so wait for
# eth1..eth3 to appear before building the bridge.
i=0
while [ "$i" -lt 60 ]; do
    if [ -e /sys/class/net/eth1 ] && [ -e /sys/class/net/eth2 ] && [ -e /sys/class/net/eth3 ]; then
        break
    fi
    i=$((i + 1))
    sleep 1
done

if ! [ -e /sys/class/net/eth3 ]; then
    echo "switch: lab interfaces did not appear" >&2
    exit 1
fi

ip link add br0 type bridge vlan_filtering 1
ip link set br0 up

for port in eth1 eth2 eth3; do
    ip link set "$port" master br0
    ip link set "$port" up
    # drop the default VLAN 1 membership; only our VLANs should pass
    bridge vlan del dev "$port" vid 1 2>/dev/null || true
done

case "$ROLE" in
    1)
        # eth1 = attacker access (VLAN 10)
        # eth2 = trunk to switch2 (native VLAN 10 untagged, VLAN 20 tagged)
        # eth3 = router access (VLAN 10)
        bridge vlan add dev eth1 vid 10 pvid untagged
        bridge vlan add dev eth2 vid 10 pvid untagged
        bridge vlan add dev eth2 vid 20 tagged
        bridge vlan add dev eth3 vid 10 pvid untagged
        ;;
    2)
        # eth1 = trunk to switch1 (native VLAN 10 untagged, VLAN 20 tagged)
        # eth2 = victim access (VLAN 20)
        # eth3 = router access (VLAN 20)
        bridge vlan add dev eth1 vid 10 pvid untagged
        bridge vlan add dev eth1 vid 20 tagged
        bridge vlan add dev eth2 vid 20 pvid untagged
        bridge vlan add dev eth3 vid 20 pvid untagged
        ;;
    *)
        echo "switch: unknown SWITCH_ROLE=$ROLE" >&2
        exit 1
        ;;
esac

echo "switch$ROLE ready"
bridge vlan show

exec tail -f /dev/null
