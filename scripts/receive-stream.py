"""Listens to a rig's live view for a while and prints what arrived, per stream.

    uv run --no-project --with pyzmq python scripts\\receive-stream.py [seconds] [host]

Subscribes to every topic on the data (5556) and video (5558) ports of host (default
127.0.0.1), for seconds (default 30), then prints for each stream: messages and rate, index
gaps (messages this listener lost), the first and last header, and the last payload (for
video, whether it is a JPEG and its size). Only listens: the rig cannot tell it is there.
"""
import json
import sys
import time

import zmq

seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 30
host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"

context = zmq.Context()
poller = zmq.Poller()
for port in (5556, 5558):
    socket = context.socket(zmq.SUB)
    socket.connect(f"tcp://{host}:{port}")
    socket.setsockopt(zmq.SUBSCRIBE, b"")
    poller.register(socket, zmq.POLLIN)

streams = {}
end = time.time() + seconds
while time.time() < end:
    for socket, _ in poller.poll(200):
        topic, header, payload = socket.recv_multipart()
        topic, header = topic.decode(), json.loads(header)
        now = time.time()
        s = streams.setdefault(topic, {"n": 0, "gaps": 0, "bytes": 0, "first": header, "t0": now})
        if s["n"] and header["index"] != s["last"]["index"] + 1:
            s["gaps"] += 1
        s["n"] += 1
        s["bytes"] += len(payload)
        s["last"], s["t1"], s["payload"] = header, now, payload


def jpeg_size(data):
    """Width and height from the first SOF0/SOF2 marker, or None."""
    for i in range(2, len(data) - 9):
        if data[i] == 0xFF and data[i + 1] in (0xC0, 0xC2):
            return int.from_bytes(data[i + 7:i + 9], "big"), int.from_bytes(data[i + 5:i + 7], "big")
    return None


if not streams:
    print(f"Nothing from {host} in {seconds:g} s.")
for topic, s in sorted(streams.items()):
    span = s["t1"] - s["t0"]
    rate = (s["n"] - 1) / span if span > 0 else 0.0
    p = s["payload"]
    if s["last"]["enc"] == "jpeg":
        is_jpeg = p[:2] == b"\xff\xd8"
        last = f"JPEG {is_jpeg}, size {jpeg_size(p)}, mean {s['bytes'] / s['n'] / 1024:.1f} KB"
    else:
        last = f"last value {p.decode()}"
    print(f"{topic}  {s['n']} messages, {rate:.1f}/s, {s['gaps']} index gaps, {last}")
    print(f"    first {s['first']}")
    print(f"    last  {s['last']}")
