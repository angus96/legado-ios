#!/usr/bin/env python3
"""Compile and exercise the app's JavaScript bridge without an iOS simulator."""

import argparse
from pathlib import Path
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument("--sdk")
parser.add_argument("--vfs-overlay")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
engine = (root / "Core/RuleEngine/RuleEngine.swift").read_text()
context = engine[engine.index("enum RuleResult {"):engine.index("private final class SourceRuleContextAdapter")]

fixtures = """
import Foundation
import JavaScriptCore

final class BookSource {
    var bookSourceUrl = "https://example.com"
    var bookSourceName = "Regression source"
    var loginUrl: String? = nil
    var header: String? = nil
    var variable: String? = nil
    var enabledCookieJar = false
    var concurrentRate: String? = nil
}
final class RuleEngine {}
final class CookieManager {
    static let shared = CookieManager()
    func getCookie(for tag: String) -> String? { nil }
}
"""

checks = """
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    print("PASS: \\(message)")
}

let execution = ExecutionContext()
execution.source = BookSource()
execution.variables["keyword"] = "测试"
execution.lastResult = .string("page body")
let js = execution.jsContext

func eval(_ script: String) -> JSValue {
    js.exception = nil
    guard let result = js.evaluateScript(script), js.exception == nil else {
        fatalError("JavaScript failed: \\(js.exception?.toString() ?? script)")
    }
    return result
}

check(eval("typeof java.ajax === 'function' && typeof cookie.get === 'function'").toBool(), "native bridge initializes")
check(eval("source.bookSourceUrl === 'https://example.com' && source.enabledCookieJar === false").toBool(), "source properties are values")
check(eval("java.put('saved', 'value'); java.get('saved')").toString() == "value", "bridge survives initialization")
check(execution.variables["saved"] == "value", "JavaScript updates execution variables")
check(eval("setVar('state', 'ready'); getVar('state')").toString() == "ready", "getVar and setVar are callable")
check(eval("result").toString() == "page body", "result contains the response value")
check(eval("cache.put('cache-key', 'cached'); cache.get('cache-key')").toString() == "cached", "cache callbacks are callable")
check(eval("cache.getFromMemory('cache-key')").toString() == "cached", "memory cache callback is callable")
check(eval("var crypto = java.createSymmetricCrypto('AES/ECB/PKCS5Padding', '0123456789abcdef', null); crypto.decryptStr(crypto.encryptBase64('round trip'))").toString() == "round trip", "crypto callbacks are callable")

js.setObject("中文关键词", forKeyedSubscript: "key" as NSString)
js.setObject(2, forKeyedSubscript: "page" as NSString)
check(eval("source.bookSourceUrl + '/search?q=' + encodeURIComponent(key) + '&page=' + page").toString() == "https://example.com/search?q=%E4%B8%AD%E6%96%87%E5%85%B3%E9%94%AE%E8%AF%8D&page=2", "search variables produce a URL")

js.setObject("分类", forKeyedSubscript: "category" as NSString)
let discovery = eval("[{title: category, url: source.bookSourceUrl + '/explore'}]").toArray() as? [[String: Any]]
check(discovery?.first?["title"] as? String == "分类", "discovery returns categories")
check(discovery?.first?["url"] as? String == "https://example.com/explore", "discovery reads source URL")

_ = js.evaluateScript("throw new Error('invalid source rule')")
check(js.exception != nil, "invalid JavaScript reports an exception")
check(eval("java.get('saved')").toString() == "value", "a failed rule does not destroy the bridge")

weak var releasedExecution: ExecutionContext?
weak var releasedJavaScript: JSContext?
autoreleasepool {
    let temporary = ExecutionContext()
    releasedExecution = temporary
    releasedJavaScript = temporary.jsContext
    _ = temporary.jsContext.evaluateScript("java.put('temporary', 'value')")
}
check(releasedExecution == nil && releasedJavaScript == nil, "execution context releases its bridge")
"""

with tempfile.TemporaryDirectory(prefix="legado-js-") as temporary:
    directory = Path(temporary)
    main = directory / "main.swift"
    main.write_text(fixtures + context + checks)
    binary = directory / "verify-js"
    command = ["xcrun", "swiftc"]
    if args.sdk:
        command += ["-sdk", args.sdk]
    if args.vfs_overlay:
        command += ["-vfsoverlay", str(Path(args.vfs_overlay).resolve())]
    command += [
        "-module-cache-path", str(directory / "modules"),
        str(root / "Core/RuleEngine/JSBridge.swift"),
        str(root / "Core/RuleEngine/JsEncodeUtils.swift"),
        str(main), "-o", str(binary),
    ]
    subprocess.run(command, check=True)
    subprocess.run([str(binary)], check=True)
