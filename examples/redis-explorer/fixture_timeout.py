#!/usr/bin/env python3
import os
import socketserver
import time
from pathlib import Path

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.rfile.readline()
        time.sleep(3)

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server(("127.0.0.1", 36377), Handler) as server:
    if ready_file := os.environ.get("ROC_GUI_FIXTURE_READY_FILE"):
        Path(ready_file).touch()
    server.serve_forever()
