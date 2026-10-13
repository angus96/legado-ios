#!/usr/bin/env python3
from http.server import ThreadingHTTPServer
import base64
import json
import threading
import time
from urllib.parse import parse_qs, urlsplit
from verify_domain_pipeline import Handler


class StabilityHandler(Handler):
    image_requests = {}
    image_lock = threading.Lock()
    image = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=")

    def do_GET(self):
        parsed = urlsplit(self.path)
        key = parse_qs(parsed.query).get("key", [""])[0]
        if parsed.path == "/image.png":
            with self.image_lock:
                self.image_requests[key] = self.image_requests.get(key, 0) + 1
            time.sleep(0.1)
            allowed = self.headers.get("X-Legado-Test") == "image-cache"
            body = self.image if allowed else b"missing source headers"
            self.send_response(200 if allowed else 403)
            self.send_header("Content-Type", "image/png" if allowed else "text/plain")
        elif parsed.path == "/image-count":
            with self.image_lock:
                body = json.dumps({"requests": self.image_requests.get(key, 0)}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
        else:
            return super().do_GET()
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8766), StabilityHandler).serve_forever()
