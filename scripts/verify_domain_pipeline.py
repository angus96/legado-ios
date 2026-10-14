#!/usr/bin/env python3
"""Exercise actual HTTP, parsing and CoreData code with a local fixture server."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import xml.etree.ElementTree as ET


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        bodies = {
            "/search": {"books": [{"idx": 0, "titles": ["测试书籍"], "author": "测试作者", "url": "/book"}]},
            "/search-missing": {"books": [{"titles": ["测试书籍"], "author": "测试作者", "url": "/book"}]},
            "/book": {"name": "测试书籍", "author": "测试作者", "toc": "/toc"},
            "/toc": {"chapters": [{"name": f"第{i + 1}章", "url": f"/chapter/{i + 1}"} for i in range(4)]},
            "/chapter/1": {"content": "第一章测试内容"},
            "/failure": {"error": "source unavailable"},
        }
        body = json.dumps(bodies.get(path, {"content": "测试正文"}), ensure_ascii=False).encode()
        self.send_response(503 if path == "/failure" else 200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def verify(directory, args):
    root = Path(__file__).resolve().parents[1]
    compiler = ["xcrun", "swiftc", "-O", "-module-cache-path", str(directory / "modules")]
    if args.sdk:
        compiler += ["-sdk", args.sdk]
    if args.vfs_overlay:
        compiler += ["-vfsoverlay", str(Path(args.vfs_overlay).resolve())]
    libraries = Path(args.libraries).resolve()
    if not (libraries / "libSwiftSoup.a").exists():
        raise RuntimeError("Run verify_rule_engine.py --build-dir first")
    schema = ET.parse(root / "Core/Persistence/Legado.xcdatamodeld/Legado.xcdatamodel/contents").getroot()
    model = [{"name": entity.attrib["name"],
              "attributes": [attribute.attrib for attribute in entity.findall("attribute")],
              "relationships": [relationship.attrib for relationship in entity.findall("relationship")]}
             for entity in schema.findall("entity")]
    (directory / "model.json").write_text(json.dumps(model))
    (directory / "fixtures.swift").write_text((root / "scripts/domain_pipeline_fixtures.swift").read_text())
    (directory / "main.swift").write_text((root / "scripts/domain_pipeline_checks.swift").read_text())
    paths = [
        "Core/RuleEngine/RuleEngine.swift", "Core/RuleEngine/RuleSplitter.swift", "Core/RuleEngine/SourceRule.swift",
        "Core/RuleEngine/RuleAnalyzer.swift", "Core/RuleEngine/TemplateEngine.swift", "Core/RuleEngine/JSBridge.swift",
        "Core/RuleEngine/JsEncodeUtils.swift", "Core/RuleEngine/TocRule.swift", "Core/RuleEngine/TocParser.swift",
        "Core/Model/WebBook.swift", "Core/Model/BookSourceSnapshot.swift", "Core/Model/BookRequestSnapshot.swift",
        "Core/Persistence/Book+CoreDataClass.swift", "Core/Persistence/BookSource+CoreDataClass.swift",
        "Core/Persistence/BookChapter+CoreDataClass.swift", "Core/Persistence/Cookie+CoreDataClass.swift",
        "Core/Persistence/Bookmark+CoreDataClass.swift",
        "Core/Persistence/ReadConfig.swift", "Core/Persistence/ManagedObjectAccess.swift",
        "Core/Persistence/BookSourceResolver.swift", "Core/Persistence/ChapterDirectoryUpdater.swift",
        "Core/Reader/ReadingProgressMapper.swift", "Core/Network/AnalyzeUrl.swift", "Core/Network/StrResponse.swift",
        "Core/Network/ConcurrentRateLimiter.swift", "Core/Network/CookieManager.swift",
        "Core/Parser/HTMLToTextConverter.swift",
        "Core/Parser/TxtFileParser.swift", "Core/Utils/JSONNumber.swift",
        "Core/Persistence/BackupStore.swift", "Core/Persistence/CoreDataStoreMigration.swift",
        "Core/Reader/ChapterContentLoader.swift", "Core/Utils/ZipBuilder.swift",
    ]
    binary = directory / "verify-domain-pipeline"
    subprocess.run(compiler + ["-I", str(libraries), "-L", str(libraries), "-lSwiftSoup", "-lKanna", "-lxml2", "-lz"]
                   + [str(root / path) for path in paths]
                   + [str(directory / "fixtures.swift"), str(directory / "main.swift"), "-o", str(binary)], check=True)
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        subprocess.run([str(binary), "-com.apple.CoreData.ConcurrencyDebug", "1",
                        str(directory / "model.json"), f"http://127.0.0.1:{server.server_port}", str(directory)], check=True)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk")
    parser.add_argument("--vfs-overlay")
    parser.add_argument("--libraries", required=True)
    parser.add_argument("--build-dir")
    args = parser.parse_args()
    if args.build_dir:
        directory = Path(args.build_dir).resolve()
        directory.mkdir(parents=True, exist_ok=True)
        verify(directory, args)
    else:
        with tempfile.TemporaryDirectory(prefix="legado-domain-") as temporary:
            verify(Path(temporary), args)
