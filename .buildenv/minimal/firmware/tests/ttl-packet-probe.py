"""Capture one synthetic UDP packet at a test veth peer; never use on a router."""
import socket
import sys

device, peer, target = sys.argv[1:]
ipv6 = ":" in target
with socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(3)) as capture:
    capture.bind((peer, 0))
    capture.settimeout(3)
    family = socket.AF_INET6 if ipv6 else socket.AF_INET
    with socket.socket(family, socket.SOCK_DGRAM) as sender:
        sender.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, device.encode() + b"\0")
        sender.setsockopt(socket.IPPROTO_IPV6 if ipv6 else socket.IPPROTO_IP,
                          socket.IPV6_UNICAST_HOPS if ipv6 else socket.IP_TTL, 42)
        sender.sendto(b"qmodem-ttl-regression", (target, 39999))
    while True:
        packet = capture.recv(2048)
        if ipv6 and packet[12:14] == b"\x86\xdd" and packet[20] == 17:
            if int.from_bytes(packet[56:58], "big") == 39999:
                print(packet[21])
                break
        if not ipv6 and packet[12:14] == b"\x08\x00" and packet[23] == 17:
            udp = 14 + (packet[14] & 15) * 4
            if int.from_bytes(packet[udp + 2:udp + 4], "big") == 39999:
                print(packet[22])
                break
