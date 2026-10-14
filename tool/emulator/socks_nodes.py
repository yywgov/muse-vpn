#!/usr/bin/env python3
"""穿云 e2e: SOCKS5 test nodes for the Android emulator (reached there as 10.0.2.2).

Ports 11080..11087, each answering CONNECT after an added delay so the node list shows green,
yellow and red latencies. No auth, TCP CONNECT only (IPv4 / domain / IPv6). Byte counts per
port are printed every 10 s so the CI log shows which node carried traffic.
"""
import asyncio
import socket
import struct
import sys

DELAYS_MS = [0, 60, 150, 320, 420, 560, 800, 1200]
BASE = 11080
counters = {BASE + i: 0 for i in range(len(DELAYS_MS))}


async def pipe(reader, writer, port):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            counters[port] += len(data)
            writer.write(data)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle(reader, writer, port, delay):
    try:
        head = await reader.readexactly(2)
        if head[0] != 5:
            writer.close()
            return
        await reader.readexactly(head[1])
        writer.write(b"\x05\x00")
        await writer.drain()
        ver, cmd, _, atyp = await reader.readexactly(4)
        if atyp == 1:
            host = socket.inet_ntoa(await reader.readexactly(4))
        elif atyp == 3:
            n = (await reader.readexactly(1))[0]
            host = (await reader.readexactly(n)).decode()
        elif atyp == 4:
            host = socket.inet_ntop(socket.AF_INET6, await reader.readexactly(16))
        else:
            writer.close()
            return
        dport = struct.unpack("!H", await reader.readexactly(2))[0]
        if cmd != 1:
            writer.write(b"\x05\x07\x00\x01" + b"\x00" * 6)
            await writer.drain()
            writer.close()
            return
        if delay:
            await asyncio.sleep(delay / 1000)
        try:
            r2, w2 = await asyncio.wait_for(asyncio.open_connection(host, dport), 10)
        except Exception:
            writer.write(b"\x05\x05\x00\x01" + b"\x00" * 6)
            await writer.drain()
            writer.close()
            return
        writer.write(b"\x05\x00\x00\x01" + b"\x00" * 6)
        await writer.drain()
        await asyncio.gather(pipe(reader, w2, port), pipe(r2, writer, port))
    except Exception:
        try:
            writer.close()
        except Exception:
            pass


async def report():
    while True:
        await asyncio.sleep(10)
        print("socks bytes:", {p: c for p, c in counters.items() if c}, flush=True)


async def main():
    for i, d in enumerate(DELAYS_MS):
        port = BASE + i
        await asyncio.start_server(lambda r, w, p=port, dd=d: handle(r, w, p, dd), "0.0.0.0", port)
    print("socks nodes up on", list(counters), flush=True)
    await report()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
