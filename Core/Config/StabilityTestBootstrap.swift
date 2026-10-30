#if DEBUG
import Foundation

@MainActor
enum StabilityTestBootstrap {
    static func incomingTextFixture() throws -> URL? {
        guard ProcessInfo.processInfo.environment["LEGADO_UI_TESTS"] == "1",
              ProcessInfo.processInfo.environment["LEGADO_SHARED_TXT"] == "1" else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SharedTextFixture", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("分享的星河.TXT")
        try "引言：这是从其他应用分享的文本。\n第1章 星河\n第一章分享正文，保存后可以离线阅读。\n第2章 远行\n第二章分享正文，章节完整保留。".write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    static func prepareIfRequested() {
        guard ProcessInfo.processInfo.environment["LEGADO_UI_TESTS"] == "1" else { return }
        let base = ProcessInfo.processInfo.environment["LEGADO_FIXTURE_URL"] ?? "http://127.0.0.1:8766"
        UserDefaults.standard.set(true, forKey: "hasCompletedWelcome")
        UserDefaults.standard.set(0, forKey: "app.defaultHomePage")
        // 每次 UI 测试启动都会创建新数据库，旧书源编号不属于本次测试数据。
        UserDefaults.standard.removeObject(forKey: "search.selectedSourceIDs")
        UserDefaults.standard.removeObject(forKey: "search.mode")
        UserDefaults.standard.removeObject(forKey: "discovery.selectedSourceID")
        UserDefaults.standard.removeObject(forKey: "discovery.selectedCategories")
        let rules: [String: Any] = [
            "ruleSearch": ["bookList": "$.books", "name": "$.titles[{$.idx}]", "author": "$.author", "bookUrl": "$.url"],
            "ruleBookInfo": ["name": "$.name", "author": "$.author", "tocUrl": "$.toc",
                             "intro": "$.intro", "kind": "$.kind", "wordCount": "$.wordCount"],
            "ruleToc": ["chapterList": "$.chapters", "chapterName": "$.name", "chapterUrl": "$.url"],
            "ruleContent": ["content": "$.content"]
        ]
        let sources = ["current", "alternate", "missing"].map { kind -> [String: Any] in
            var source = rules
            source["bookSourceUrl"] = base + "/" + kind
            source["bookSourceName"] = kind == "current" ? "测试原书源" : (kind == "alternate" ? "测试新书源" : "测试缺字段书源")
            source["searchUrl"] = base + (kind == "missing" ? "/search-missing" : "/search")
            if ProcessInfo.processInfo.environment["LEGADO_SEARCH_PREVIEW"] == "1" {
                source["searchUrl"] = base + "/search-preview"
            }
            if ProcessInfo.processInfo.environment["LEGADO_DIRECTORY_REGRESSION"] == "1" {
                source["enabled"] = kind == "current"
                source["searchUrl"] = base + "/search-directory"
            }
            if ProcessInfo.processInfo.environment["LEGADO_AUTHOR_SEARCH"] == "1" {
                source["searchUrl"] = base + "/search-author?key={{key}}"
            }
            if ProcessInfo.processInfo.environment["LEGADO_TITLE_SEARCH"] == "1" {
                source["searchUrl"] = base + "/search-title"
            }
            if ProcessInfo.processInfo.environment["LEGADO_SEARCH_CONTINUES"] == "1" {
                source["searchUrl"] = base + (kind == "current" ? "/search-early" : "/search-late")
            }
            if kind != "missing" {
                source["enabledExplore"] = true
                source["exploreUrl"] = "测试分类::" + base + "/explore-posters?source=\(kind)&kind=hot&page={{page}}"
                if kind == "current", let key = ProcessInfo.processInfo.environment["LEGADO_DISCOVERY_SLOW"] {
                    source["exploreUrl"] = "@js: java.ajax('\(base)/explore-kinds?key=\(key)')"
                }
            }
            if ProcessInfo.processInfo.environment["LEGADO_DISCOVERY_WALL"] == "1" {
                source["enabledExplore"] = true
                source["bookSourceName"] = kind == "current" ? "星河书屋" : (kind == "alternate" ? "远山书屋" : "暂不可用书源")
                source["bookSourceGroup"] = kind == "missing" ? "待校验" : "小说"
                source["exploreUrl"] = kind == "current"
                    ? "热门推荐::\(base)/explore-posters?source=current&kind=hot&page={{page}}&&完本榜::\(base)/explore-posters?source=current&kind=finished&page={{page}}"
                    : (kind == "alternate" ? "都市精选::\(base)/explore-posters?source=alternate&kind=urban&page={{page}}" : "推荐::\(base)/failure")
            }
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
