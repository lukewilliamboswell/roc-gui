#!/usr/bin/env python3
import http.server
import time

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("content-length", "0"))
        body = self.rfile.read(length)
        if self.path == "/slow":
            time.sleep(0.15)
        if self.path == "/large":
            body = b"x" * 300000
        elif self.path == "/bulk":
            body = b"x" * 200000
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, format, *args):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", 38191), Handler).serve_forever()
