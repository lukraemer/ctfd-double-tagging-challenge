#!/usr/bin/env python3
"""Stateless UDP flag service for the double-tagging challenge.

Listens on udp/1337 and replies with /flag.txt to every datagram. The reply is
routed back to the attacker (VLAN 20 -> VLAN 10 is allowed by the router).
"""

import socket

FLAG_PATH = "/flag.txt"
PORT = 1337


def main() -> None:
    with open(FLAG_PATH, "r", encoding="utf-8") as f:
        flag = f.read().strip()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", PORT))
    print(f"victim: listening on udp/{PORT}", flush=True)

    while True:
        data, addr = sock.recvfrom(4096)
        print(f"victim: request from {addr[0]}:{addr[1]}: {data!r}", flush=True)
        sock.sendto((flag + "\n").encode(), addr)


if __name__ == "__main__":
    main()
