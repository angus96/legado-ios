#!/usr/bin/env python3
from http.server import ThreadingHTTPServer
import base64
import json
import threading
import time
from urllib.parse import parse_qs, urlsplit
from verify_domain_pipeline import Handler


class StabilityHandler(Handler):
    explore_requests = {}
    explore_lock = threading.Lock()
    image_requests = {}
    image_lock = threading.Lock()
    image = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=")

    def do_GET(self):
        parsed = urlsplit(self.path)
        key = parse_qs(parsed.query).get("key", [""])[0]
        if parsed.path == "/search-title":
            books = [{"idx": 0, "titles": [title], "author": "测试作者", "url": f"/title/{index}"}
                     for index, title in enumerate(["我在大明当先生", "全集：我在大明当先生", "大明：我在朝堂"])]
            body = json.dumps({"books": books}, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
        elif parsed.path in ("/search-early", "/search-late"):
            late = parsed.path == "/search-late"
            if late:
                time.sleep(5)
            body = json.dumps({"books": [{"idx": 0, "titles": ["后来返回的书" if late else "详情失败的书"],
                                         "author": "测试作者", "url": "/book" if late else "/broken-book"}]}, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
        elif parsed.path == "/broken-book":
            body = b"book unavailable"
            self.send_response(404)
            self.send_header("Content-Type", "text/plain")
        elif parsed.path == "/explore-kinds":
            with self.explore_lock:
                self.explore_requests[key] = self.explore_requests.get(key, 0) + 1
            time.sleep(3)
            body = json.dumps([{"title": "动态测试分类", "url": "/explore"}], ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
        elif parsed.path == "/explore-request-count":
            with self.explore_lock:
                body = json.dumps({"requests": self.explore_requests.get(key, 0)}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
        elif parsed.path == "/search-author":
            books = [
                {"idx": 0, "titles": ["遮天"], "author": "辰东", "url": "/author/book-1"},
                {"idx": 0, "titles": ["完美世界"], "author": "辰东", "url": "/author/book-2"},
                {"idx": 0, "titles": ["辰东作品评论"], "author": "另一位作者", "url": "/author/review"},
                {"idx": 0, "titles": ["辰东相关资料"], "author": "", "url": "/author/unknown"},
            ] if key == "辰东" else []
            body = json.dumps({"books": books}, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
        elif parsed.path in ("/search-directory", "/book-directory", "/toc-latest"):
            payload = {"name": "目录测试书", "author": "测试作者", "toc": "/toc-latest", "intro": "目录测试简介"}
            if parsed.path == "/search-directory":
                payload = {"books": [{"idx": 0, "titles": ["目录测试书"], "author": "测试作者", "url": "/book-directory"}]}
            elif parsed.path == "/toc-latest":
                chapters = [{"name": f"第{i}章", "url": f"/chapter/{i}"} for i in range(1, 5)]
                payload = {"chapters": list(reversed(chapters[-2:])) + [{"name": "引言", "url": "/chapter/intro"}] + chapters}
            body = json.dumps(payload, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
        elif parsed.path in ("/search-preview", "/book-preview"):
            title = "长夜行舟：一个旅人与群星的故事"
            payload = {"name": title, "author": "远山与海", "toc": "/toc", "kind": "奇幻,冒险",
                       "wordCount": "128万字", "intro": "群星隐去的夜晚，一个年轻旅人沿河启程。<br>他带着一封没有地址的信，穿过沉睡的城镇，寻找远方灯塔的守夜人。" * 3}
            if parsed.path == "/search-preview":
                payload = {"books": [{"idx": 0, "titles": [title], "author": "远山与海", "url": "/book-preview"}]}
            body = json.dumps(payload, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
        elif parsed.path.startswith("/chapter/"):
            number = parsed.path.rsplit("/", 1)[-1]
            paragraphs = [f"第{number}章正文，第{i}段。" + "这段文字用于检查阅读器是否真正显示正文，翻页后仍然能看清。" * 4 for i in range(50)]
            body = json.dumps({"content": "\n".join(paragraphs)}, ensure_ascii=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
        elif parsed.path == "/image.png":
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
