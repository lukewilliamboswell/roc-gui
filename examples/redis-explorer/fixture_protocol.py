#!/usr/bin/env python3
import socketserver

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.rfile.readline()
        self.wfile.write(b"!not-resp\r\n")
        self.wfile.flush()

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

with Server(("127.0.0.1", 36376), Handler) as server:
    server.serve_forever()
