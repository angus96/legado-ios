#!/usr/bin/env python3
from http.server import ThreadingHTTPServer
from verify_domain_pipeline import Handler

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8766), Handler).serve_forever()
