#!/usr/bin/env python3
"""Deterministic local RESP fixture for Redis Explorer specifications."""

from __future__ import annotations

import fnmatch
import os
import socketserver
from pathlib import Path

HOST = "127.0.0.1"
PORT = 36379

SPECIAL = {
    "profile:ada": ("hash", ["name", "Ada Lovelace", "role", "Engineer"]),
    "profile:grace": ("string", "Grace Hopper"),
    "profile:recent": ("list", ["ada", "grace", "linus"]),
    "profile:roles": ("set", ["admin", "editor", "viewer"]),
    "profile:scores": ("zset", [("ada", "98.5"), ("grace", "99")]),
    "unsupported:events": ("stream", []),
}

KEYS = (
    sorted(SPECIAL)
    + [f"session:{index:03d}" for index in range(100)]
    + [f"product:{index:04d}" for index in range(1000)]
    + [f"catalog:item:{index:05d}" for index in range(10000)]
)


def bulk(value: str | None) -> bytes:
    if value is None:
        return b"$-1\r\n"
    encoded = value.encode()
    return f"${len(encoded)}\r\n".encode() + encoded + b"\r\n"


def array(values: list[str]) -> bytes:
    return f"*{len(values)}\r\n".encode() + b"".join(bulk(value) for value in values)


def key_type(key: str) -> str:
    if key in SPECIAL:
        return SPECIAL[key][0]
    if key in KEYS:
        return "string"
    return "none"


def string_value(key: str) -> str | None:
    if key == "profile:grace":
        return "Grace Hopper"
    if key.startswith("session:"):
        return f"active session {key.removeprefix('session:')}"
    if key.startswith("product:"):
        return f"inventory record {key.removeprefix('product:')}"
    if key.startswith("catalog:item:"):
        return f"catalog description {key.removeprefix('catalog:item:')}"
    return None


def read_request(stream) -> list[str] | None:
    line = stream.readline()
    if not line:
        return None
    if not line.startswith(b"*"):
        raise ValueError("expected RESP array")
    count = int(line[1:-2])
    parts = []
    for _ in range(count):
        length = int(stream.readline()[1:-2])
        value = stream.read(length)
        if stream.read(2) != b"\r\n":
            raise ValueError("invalid bulk ending")
        parts.append(value.decode())
    return parts


class Handler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        try:
            while command := read_request(self.rfile):
                name = command[0].upper()
                if name == "PING":
                    response = b"+PONG\r\n"
                elif name == "SCAN" and len(command) == 6:
                    cursor = int(command[1])
                    pattern = command[3]
                    count = max(1, int(command[5]))
                    matches = [key for key in KEYS if fnmatch.fnmatchcase(key, pattern)]
                    page = matches[cursor : cursor + count]
                    next_cursor = 0 if cursor + count >= len(matches) else cursor + count
                    response = b"*2\r\n" + bulk(str(next_cursor)) + array(page)
                elif name == "TYPE" and len(command) == 2:
                    response = f"+{key_type(command[1])}\r\n".encode()
                elif name == "PTTL" and len(command) == 2:
                    ttl = 60000 if command[1] == "profile:grace" else -1
                    response = f":{ttl}\r\n".encode()
                elif name == "GET" and len(command) == 2:
                    response = bulk(string_value(command[1]))
                elif name == "LRANGE" and len(command) == 4 and command[1] == "profile:recent":
                    response = array(SPECIAL[command[1]][1])
                elif name == "SMEMBERS" and len(command) == 2 and command[1] == "profile:roles":
                    response = array(SPECIAL[command[1]][1])
                elif name == "HGETALL" and len(command) == 2 and command[1] == "profile:ada":
                    response = array(SPECIAL[command[1]][1])
                elif name == "ZRANGE" and len(command) == 5 and command[1] == "profile:scores":
                    response = array([part for pair in SPECIAL[command[1]][1] for part in pair])
                else:
                    response = b"-ERR unsupported fixture command\r\n"
                self.wfile.write(response)
                self.wfile.flush()
        except (ValueError, UnicodeDecodeError, ConnectionError):
            return


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server((HOST, PORT), Handler) as server:
        if ready_file := os.environ.get("ROC_GUI_FIXTURE_READY_FILE"):
            Path(ready_file).touch()
        server.serve_forever()
