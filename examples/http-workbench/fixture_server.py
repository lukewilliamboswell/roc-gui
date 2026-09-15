#!/usr/bin/env python3
"""Small deterministic HTTP/1.1 fixture for HTTP Workbench specifications."""

import os
import socketserver
import time
from pathlib import Path


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        request = self.rfile.readline().decode("ascii").split()
        if len(request) != 3:
            return
        _method, path, _version = request
        headers = {}
        while line := self.rfile.readline():
            if line == b"\r\n":
                break
            name, value = line.decode("ascii").split(":", 1)
            headers[name.lower()] = value.strip()
        body = self.rfile.read(int(headers.get("content-length", "0")))
        if path == "/slow":
            time.sleep(0.15)
        if path == "/large":
            body = b"x" * 300000
        elif path == "/bulk":
            body = b"x" * 200000
        response_headers = (
            "HTTP/1.1 200 OK\r\n"
            "content-type: application/json\r\n"
            f"content-length: {len(body)}\r\n"
            "connection: close\r\n\r\n"
        ).encode("ascii")
        self.wfile.write(response_headers + body)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


server = Server(("127.0.0.1", 38191), Handler)
ready_file = os.environ.get("ROC_GUI_FIXTURE_READY_FILE")
if ready_file is not None:
    Path(ready_file).touch()
server.serve_forever()
