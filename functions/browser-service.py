#!/usr/bin/env python3
"""
Local browser service for devpod-gh.fish.

Listens on a random port and opens URLs in the host machine's default browser.
The port is printed to stdout on startup so the caller can read it.
"""

import http.server
import platform
import subprocess
import sys
import urllib.parse


class BrowserHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Health check endpoint
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/open":
            params = urllib.parse.parse_qs(parsed.query)
            url = params.get("url", [None])[0]
            if url:
                self._open_url(url)
                self.send_response(200)
            else:
                self.send_response(400)
        else:
            self.send_response(404)
        self.end_headers()

    def _open_url(self, url):
        try:
            if platform.system() == "Darwin":
                subprocess.Popen(["open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            else:
                subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except FileNotFoundError:
            pass

    def log_message(self, format, *args):
        pass  # Suppress request logs


def main():
    server = http.server.HTTPServer(("127.0.0.1", 0), BrowserHandler)
    port = server.server_address[1]
    print(port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()


if __name__ == "__main__":
    main()
