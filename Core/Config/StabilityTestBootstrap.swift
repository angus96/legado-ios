#if DEBUG
import Foundation

@MainActor
enum StabilityTestBootstrap {
    static func prepareIfRequested() {
        guard ProcessInfo.processInfo.environment["LEGADO_UI_TESTS"] == "1" else { return }
        let base = ProcessInfo.processInfo.environment["LEGADO_FIXTURE_URL"] ?? "http://127.0.0.1:8766"
        UserDefaults.standard.set(true, forKey: "hasCompletedWelcome")
        UserDefaults.standard.set(0, forKey: "defaultHomePage")
        let rules: [String: Any] = [
            "ruleSearch": ["bookList": "$.books", "name": "$.titles[{$.idx}]", "author": "$.author", "bookUrl": "$.url"],
            "ruleBookInfo": ["name": "$.name", "author": "$.author", "tocUrl": "$.toc"],
            "ruleToc": ["chapterList": "$.chapters", "chapterName": "$.name", "chapterUrl": "$.url"],
            "ruleContent": ["content": "$.content"]
        ]
        let sources = ["current", "alternate", "missing"].map { kind -> [String: Any] in
            var source = rules
            source["bookSourceUrl"] = base + "/" + kind
            source["bookSourceName"] = kind == "current" ? "测试原书源" : (kind == "alternate" ? "测试新书源" : "测试缺字段书源")
            source["searchUrl"] = base + (kind == "missing" ? "/search-missing" : "/search")
            return source
        }
        let payload: [String: Any] = ["sources": sources, "books": [[
            "bookId": "11111111-1111-4111-8111-111111111111", "name": "测试书籍", "author": "测试作者",
            "origin": base + "/current", "originName": "测试原书源", "bookUrl": base + "/book", "tocUrl": base + "/toc"
        ]]]
        do { _ = try BackupStore.restore(payload, container: CoreDataStack.shared.persistentContainer) }
        catch { DebugLogger.shared.log("模拟器测试初始化失败：\(error.localizedDescription)") }
    }
}
#endif
