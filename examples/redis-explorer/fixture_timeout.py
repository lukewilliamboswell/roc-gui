#!/usr/bin/env python3
import socketserver
import time

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.rfile.readline()
        time.sleep(3)

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server(("127.0.0.1", 36377), Handler) as server:
    server.serve_forever()
