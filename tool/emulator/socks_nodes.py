#!/usr/bin/env python3
"""穿云 e2e: SOCKS5 test nodes for the Android emulator (reached there as 10.0.2.2).

Ports 11080..11087. Each node adds a fixed delay before every response (the first bytes coming
back after the client sent something), so node tests show green, yellow and red latencies.
No auth, TCP CONNECT only (IPv4 / domain / IPv6).

Test traffic does not depend on any outside host: a CONNECT to SINK_IP (TEST-NET-3, not a CN
address, so the app's rules send it through the node) is answered by the node itself with an
HTTP response streamed at RATE bytes/s. Everything a node carries is counted per port.

Control (CI host only, 127.0.0.1:11990):
  GET /counters -> {"ports": {port: bytes}, "sink": bytes, "sinkStreams": open streams}
  GET /stop     -> ends every open sink stream (the test stops its traffic per phase)
"""
import asyncio
import json
import socket
import struct
import sys

DELAYS_MS = [0, 60, 150, 320, 420, 560, 800, 1200]
BASE = 11080
SINK_IP = "203.0.113.7"
RATE = 1024 * 1024  # bytes per second per sink stream
CONTROL_PORT = 11990
counters = {BASE + i: 0 for i in range(len(DELAYS_MS))}
sink = {"bytes": 0, "streams": 0, "generation": 0}


async def pipe(reader, writer, port, state, delay, is_response):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            if is_response:
                if state["pending"] and delay:
                    await asyncio.sleep(delay / 1000)
                state["pending"] = False
            else:
                state["pending"] = True
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


async def serve_sink(reader, writer, port, delay):
    """Answers one HTTP request with a long body at RATE until the client or /stop ends it."""
    gen = sink["generation"]
    sink["streams"] += 1
    try:
        req = b""
        while b"\r\n\r\n" not in req and len(req) < 8192:
            chunk = await asyncio.wait_for(reader.read(4096), 15)
            if not chunk:
                break
            req += chunk
        counters[port] += len(req)
        if delay:
            await asyncio.sleep(delay / 1000)
        total = 1 << 30
        head = (
            "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
            f"Content-Length: {total}\r\nConnection: close\r\n\r\n"
        ).encode()
        writer.write(head)
        await writer.drain()
        block = b"\x5a" * 16384
        per_tick = RATE // 10
        sent = 0
        loop = asyncio.get_running_loop()
        while sent < total and sink["generation"] == gen:
            t0 = loop.time()
            n = 0
            while n < per_tick:
                writer.write(block)
                n += len(block)
            await writer.drain()
            sent += n
            counters[port] += n
            sink["bytes"] += n
            await asyncio.sleep(max(0.0, 0.1 - (loop.time() - t0)))
    except Exception:
        pass
    finally:
        sink["streams"] -= 1
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
        if host == SINK_IP:
            writer.write(b"\x05\x00\x00\x01" + b"\x00" * 6)
            await writer.drain()
            await serve_sink(reader, writer, port, delay)
            return
        try:
            r2, w2 = await asyncio.wait_for(asyncio.open_connection(host, dport), 10)
        except Exception:
            writer.write(b"\x05\x05\x00\x01" + b"\x00" * 6)
            await writer.drain()
            writer.close()
            return
        writer.write(b"\x05\x00\x00\x01" + b"\x00" * 6)
        await writer.drain()
        state = {"pending": False}
        await asyncio.gather(
            pipe(reader, w2, port, state, delay, False),
            pipe(r2, writer, port, state, delay, True),
        )
    except Exception:
        try:
            writer.close()
        except Exception:
            pass


async def control(reader, writer):
    try:
        line = (await reader.readline()).decode(errors="replace")
        while (await reader.readline()) not in (b"\r\n", b"\n", b""):
            pass
        path = line.split(" ")[1] if " " in line else "/"
        if path.startswith("/stop"):
            sink["generation"] += 1
        body = json.dumps({"ports": {str(p): c for p, c in counters.items()}, "sink": sink["bytes"],
                           "sinkStreams": sink["streams"]}).encode()
        writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "
                     + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body)
        await writer.drain()
    finally:
        writer.close()


async def report():
    while True:
        await asyncio.sleep(10)
        print("socks bytes:", {p: c for p, c in counters.items() if c}, "sink:", sink, flush=True)


async def main():
    for i, d in enumerate(DELAYS_MS):
        port = BASE + i
        await asyncio.start_server(lambda r, w, p=port, dd=d: handle(r, w, p, dd), "0.0.0.0", port)
    await asyncio.start_server(control, "127.0.0.1", CONTROL_PORT)
    print("socks nodes up on", list(counters), "control on", CONTROL_PORT, flush=True)
    await report()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
