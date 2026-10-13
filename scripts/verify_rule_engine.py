#!/usr/bin/env python3
"""Run the production rule engine with real HTML dependencies on macOS."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import tempfile


def verify(directory, args):
    root = Path(__file__).resolve().parents[1]
    modules = directory / "modules"
    modules.mkdir(parents=True, exist_ok=True)
    dependencies = Path(args.dependencies).resolve() if args.dependencies else directory / "dependencies"
    dependencies.mkdir(parents=True, exist_ok=True)
    base = ["xcrun", "swiftc", "-O", "-module-cache-path", str(modules)]
    if args.sdk:
        base += ["-sdk", args.sdk]
    if args.vfs_overlay:
        base += ["-vfsoverlay", str(Path(args.vfs_overlay).resolve())]

    def dependency(name, repository, version):
        checkout = dependencies / name
        if not checkout.exists():
            subprocess.run(["git", "clone", "--quiet", "--depth", "1", "--branch", version,
                            repository, str(checkout)], check=True)
        tag = subprocess.check_output(["git", "describe", "--tags", "--exact-match"], cwd=checkout, text=True).strip()
        if tag != version:
            raise RuntimeError(f"{name} must use {version}; found {tag}")
        output = directory / f"lib{name}.a"
        if not output.exists():
            sources = sorted((checkout / "Sources").rglob("*.swift"))
            subprocess.run(base + ["-parse-as-library", "-emit-library", "-static", "-emit-module",
                                  "-module-name", name, "-emit-module-path", str(directory / f"{name}.swiftmodule")]
                           + list(map(str, sources)) + ["-o", str(output)], check=True)
        print(f"Dependency: {name} {version}", flush=True)

    with ThreadPoolExecutor(max_workers=2) as executor:
        jobs = [
            executor.submit(dependency, "SwiftSoup", "https://github.com/scinfu/SwiftSoup.git", "2.9.6"),
            executor.submit(dependency, "Kanna", "https://github.com/tid-kijyun/Kanna.git", "5.3.0"),
        ]
        for job in jobs:
            job.result()

    fixtures = directory / "fixtures.swift"
    fixtures.write_text("""
import Foundation

// CoreData and cookies do not participate in these parser checks.
final class BookSourceSnapshot {
    var bookSourceUrl = "https://example.com"
    var bookSourceName = "Regression source"
    var loginUrl: String? = nil
    var header: String? = nil
    var variable: String? = nil
    var enabledCookieJar = false
    var concurrentRate: String? = nil
}
typealias BookSource = BookSourceSnapshot
final class CookieManager {
    static let shared = CookieManager()
    func getCookie(for tag: String) -> String? { nil }
}
""")
    main = directory / "main.swift"
    main.write_text((root / "scripts/rule_engine_checks.swift").read_text())
    files = [root / "Core/RuleEngine" / (name + ".swift") for name in [
        "RuleEngine", "SourceRule", "RuleSplitter", "RuleAnalyzer", "TemplateEngine", "JSBridge", "JsEncodeUtils",
    ]]
    files.append(root / "Core/Concurrency/ConcurrentSourceSearch.swift")
    binary = directory / "verify-rule-engine"
    subprocess.run(base + ["-I", str(directory), "-L", str(directory), "-lSwiftSoup", "-lKanna", "-lxml2"]
                   + list(map(str, files)) + [str(fixtures), str(main), "-o", str(binary)], check=True)
    command = [str(binary), args.case]
    if args.corpus:
        command.append(str(Path(args.corpus).resolve()))
    subprocess.run(command, check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk")
    parser.add_argument("--vfs-overlay")
    parser.add_argument("--dependencies", help="Existing dependency checkouts")
    parser.add_argument("--build-dir", help="Keep compiled dependencies for repeated local checks")
    parser.add_argument("--case", default="all", choices=["all", "html-inline", "unicode", "corpus"])
    parser.add_argument("--corpus", help="Local JSON array of source rules; JavaScript is not executed")
    args = parser.parse_args()
    if args.build_dir:
        directory = Path(args.build_dir).resolve()
        directory.mkdir(parents=True, exist_ok=True)
        verify(directory, args)
    else:
        with tempfile.TemporaryDirectory(prefix="legado-rules-") as temporary:
            verify(Path(temporary), args)
