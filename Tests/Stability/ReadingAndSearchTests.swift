import XCTest
import CoreData
import UIKit
import Combine
@testable import Legado

private actor SearchResponseGate {
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

@MainActor
final class ReadingAndSearchTests: XCTestCase {
    private func container() throws -> NSPersistentContainer {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Legado", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
        let result = NSPersistentContainer(name: UUID().uuidString, managedObjectModel: model)
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        result.persistentStoreDescriptions = [store]
        result.loadPersistentStores { _, error in XCTAssertNil(error) }
        result.viewContext.automaticallyMergesChangesFromParent = true
        return result
    }

    private func chapter() -> TextChapter {
        TextChapter(chapter: nil, position: 0, title: "测试章节", chaptersSize: 2,
                    sameTitleRemoved: false, isVip: false, isPay: false, effectiveReplaceRules: nil)
    }

    private func makeBook(in context: NSManagedObjectContext) -> Book {
        let book = Book.create(in: context)
        book.name = "测试书籍"
        book.author = "测试作者"
        book.origin = "https://example.invalid"
        book.originName = "测试书源"
        book.bookUrl = "https://example.invalid/book"
        book.tocUrl = "https://example.invalid/toc"
        return book
    }

    func testDiscoveryDefersJavaScriptAndKeepsStaticCategoriesSearchable() async throws {
        let database = try container()
        let context = database.viewContext
        let scripted = BookSource.create(in: context)
        scripted.bookSourceUrl = "https://scripted.invalid"
        scripted.bookSourceName = "动态书源"
        scripted.enabledExplore = true
        scripted.exploreUrl = "@js: java.ajax('https://scripted.invalid/categories')"
        let plain = BookSource.create(in: context)
        plain.bookSourceUrl = "https://plain.invalid"
        plain.bookSourceName = "普通书源"
        plain.enabledExplore = true
        plain.exploreUrl = "奇幻::/fantasy&&历史::/history"
        try context.save()
        let scriptedID = scripted.sourceId

        let gate = SearchResponseGate()
        let started = expectation(description: "只解析展开的书源一次")
        started.assertForOverFulfill = true
        let model = DiscoveryViewModel(context: database.newBackgroundContext()) { source in
            XCTAssertEqual(source.sourceId, scriptedID)
            started.fulfill()
            await gate.wait()
            return [ExploreKind(title: "动态分类", url: "/dynamic")]
        }
        await model.loadExploreGroups()
        XCTAssertEqual(model.exploreGroups.count, 2)
        XCTAssertTrue(model.exploreGroups.allSatisfy { !$0.isLoading && !$0.isExpanded })
        XCTAssertEqual(try XCTUnwrap(model.exploreGroups.first { $0.sourceId == scripted.sourceId }).exploreKinds.count, 0)
        model.filterGroups(keyword: "历史")
        XCTAssertEqual(model.filteredGroups.map(\.sourceId), [plain.sourceId])
        model.filterGroups(keyword: "动态书源")

        let loaded = expectation(description: "动态分类加载完成")
        let subscription = model.$exploreGroups.first { $0.contains { $0.exploreKinds.first?.title == "动态分类" } }
            .sink { _ in loaded.fulfill() }
        model.toggleGroup(scripted.sourceId)
        await fulfillment(of: [started], timeout: 3)
        XCTAssertTrue(try XCTUnwrap(model.filteredGroups.first).isLoading)
        model.toggleGroup(scripted.sourceId)
        model.toggleGroup(scripted.sourceId)
        await gate.release()
        await fulfillment(of: [loaded], timeout: 3)
        XCTAssertEqual(model.filteredGroups.map(\.sourceId), [scripted.sourceId])
        XCTAssertFalse(try XCTUnwrap(model.filteredGroups.first).isLoading)
        model.toggleGroup(scripted.sourceId)
        model.toggleGroup(scripted.sourceId)
        XCTAssertEqual(model.filteredGroups.first?.exploreKinds.first?.url, "/dynamic")
        withExtendedLifetime(subscription) {}
    }

    func testDiscoveryCanRetryFailedCategories() async throws {
        let database = try container()
        let source = BookSource.create(in: database.viewContext)
        source.bookSourceUrl = "https://example.invalid"
        source.bookSourceName = "重试书源"
        source.enabledExplore = true
        source.exploreUrl = "@js: missingFunction()"
        try database.viewContext.save()
        var attempts = 0
        let model = DiscoveryViewModel(context: database.newBackgroundContext()) { _ in
            attempts += 1
            if attempts == 1 { throw ExploreRuleParser.ParseError.invalidJavaScript }
            return [ExploreKind(title: "重试成功", url: "/retry")]
        }
        await model.loadExploreGroups()
        let failed = expectation(description: "显示分类加载失败")
        let failureSubscription = model.$exploreGroups.first { $0.first?.errorMessage != nil }
            .sink { _ in failed.fulfill() }
        model.toggleGroup(source.sourceId)
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertFalse(try XCTUnwrap(model.exploreGroups.first).isLoading)
        let loaded = expectation(description: "重试后显示分类")
        let successSubscription = model.$exploreGroups.first { $0.first?.exploreKinds.first?.title == "重试成功" }
            .sink { _ in loaded.fulfill() }
        model.retryGroup(source.sourceId)
        await fulfillment(of: [loaded], timeout: 3)
        XCTAssertNil(model.exploreGroups.first?.errorMessage)
        XCTAssertEqual(attempts, 2)
        withExtendedLifetime((failureSubscription, successSubscription)) {}
    }

    func testDiscoveryRefreshIgnoresCategoriesFromAnOlderLoad() async throws {
        let database = try container()
        let source = BookSource.create(in: database.viewContext)
        source.bookSourceUrl = "https://example.invalid"
        source.bookSourceName = "刷新书源"
        source.enabledExplore = true
        source.exploreUrl = "@js: '旧分类::/old'"
        try database.viewContext.save()
        let gate = SearchResponseGate()
        let started = expectation(description: "旧分类正在加载")
        let finished = expectation(description: "旧请求已返回")
        let model = DiscoveryViewModel(context: database.newBackgroundContext()) { _ in
            started.fulfill()
            await gate.wait()
            finished.fulfill()
            return [ExploreKind(title: "旧分类", url: "/old")]
        }
        await model.loadExploreGroups()
        model.toggleGroup(source.sourceId)
        await fulfillment(of: [started], timeout: 3)
        source.exploreUrl = "新分类::/new"
        try database.viewContext.save()
        model.filterGroups(keyword: "刷新")
        await model.refresh()
        await gate.release()
        await fulfillment(of: [finished], timeout: 3)
        await Task.yield()
        XCTAssertEqual(model.filteredGroups.first?.exploreKinds.map(\.title), ["新分类"])
        XCTAssertFalse(try XCTUnwrap(model.filteredGroups.first).isLoading)
    }

    func testDiscoveryParsesScriptValuesAndReportsScriptErrors() async throws {
        let database = try container()
        let source = BookSource.create(in: database.viewContext)
        source.bookSourceUrl = "https://example.invalid"
        source.bookSourceName = "分类解析书源"
        source.variable = "{\"category\":\"推荐\"}"
        source.exploreUrl = "<js>[{title: category, url: '/first'}, {title: category, url: '/second'}]</js>"
        let kinds = try await ExploreRuleParser.parse(BookSourceSnapshot.capture(source))
        XCTAssertEqual(kinds.map(\.title), ["推荐", "推荐"])
        XCTAssertEqual(kinds.map(\.url), ["/first", "/second"])
        XCTAssertEqual(Set(kinds.map(\.id)).count, 2, "同名分类仍需分别显示")
        source.exploreUrl = "@js: ({'排行': '/ranking'})"
        let dictionaryKinds = try await ExploreRuleParser.parse(BookSourceSnapshot.capture(source))
        XCTAssertEqual(dictionaryKinds.first?.title, "排行")
        XCTAssertEqual(dictionaryKinds.first?.url, "/ranking")
        source.exploreUrl = "@js: throw new Error('broken rule')"
        do {
            _ = try await ExploreRuleParser.parse(BookSourceSnapshot.capture(source))
            XCTFail("脚本异常不能显示为成功加载的空分类")
        } catch ExploreRuleParser.ParseError.invalidJavaScript {
            // 页面据此显示失败并允许重试。
        }
    }

    func testChapterDirectoryUsesCompleteListAndKeepsIntroductions() async throws {
        let database = try container()
        let source = BookSource.create(in: database.viewContext)
        source.bookSourceUrl = "https://example.invalid"
        source.setTocRule(TocRule(bookList: "id.list@tag.dd", chapterName: "tag.a@text", chapterUrl: "tag.a@href"))
        let book = makeBook(in: database.viewContext)
        book.tocUrl = book.bookUrl
        func entry(_ title: String, _ url: String) -> String { "<dd><a href='\(url)'>\(title)</a></dd>" }
        let latest = entry("第三章 归来", "/3") + entry("第二章 上路", "/2")
        let directory = entry("引言", "/intro") + entry("序章", "/prologue") +
            entry("第一章 初见", "/1") + entry("第二章 上路", "/2") + entry("第三章 归来", "/3")
        for html in [latest + directory, directory + latest] {
            book.tocHtml = "<dl id='list'>\(html)</dl>"
            let chapters = try await WebBook.getChapterList(source: source, book: book)
            XCTAssertEqual(chapters.map(\.title), ["引言", "序章", "第一章 初见", "第二章 上路", "第三章 归来"])
            XCTAssertEqual(chapters.map(\.index), Array(0..<5))
            XCTAssertEqual(Set(chapters.map(\.url)).count, 5)
        }
    }

    func testChapterDirectoryKeepsPageOverlapsAndSameNamedChapters() throws {
        let raw = try TocParser().parseChapters(body: """
            {"chapters":[{"name":"引言","url":"/intro"},{"name":"第一章","url":"/1"},
            {"name":"第二章","url":"/2"},{"name":"第二章","url":"/2"},
            {"name":"序章","url":"/volume-2-prologue"},{"name":"第一章","url":"/volume-2-1"}]}
            """, baseUrl: "https://example.invalid", rule: TocRule(bookList: "$.chapters", chapterName: "$.name", chapterUrl: "$.url"))
        let chapters = TocParser.normalizeDirectory(raw)
        XCTAssertEqual(chapters.map(\.title), ["引言", "第一章", "第二章", "序章", "第一章"])
        XCTAssertEqual(chapters.map(\.index), Array(0..<5))
        XCTAssertEqual(chapters.last?.url, "/volume-2-1")
    }

    func testSavedDirectoryRepairPreservesReadingCacheAndBookmarks() async throws {
        let database = try container()
        let context = database.viewContext
        let book = makeBook(in: context)
        let entries = [("第三章", "/3"), ("第二章", "/2"), ("引言", "/intro"),
                       ("第一章", "/1"), ("第二章", "/2"), ("第三章", "/3")]
        for (index, entry) in entries.enumerated() {
            let chapter = BookChapter.create(in: context, bookId: book.bookId, url: entry.1, index: Int32(index), title: entry.0)
            chapter.book = book
            if index == 1 { chapter.isCached = true; chapter.cachePath = "existing-cache.txt"; chapter.contentHash = "existing-hash" }
        }
        book.totalChapterNum = 6; book.durChapterIndex = 1; book.durChapterPos = 7; book.durChapterTitle = "第二章"
        let bookmark = Bookmark.create(in: context)
        bookmark.bookId = book.bookId; bookmark.book = book; bookmark.chapterIndex = 0
        bookmark.chapterTitle = "第三章"; bookmark.content = "书签正文"
        try context.save()
        try await ChapterDirectoryUpdater.repairStoredDirectory(for: book)
        let chapters = try context.fetch(BookChapter.fetchRequest(byBookId: book.bookId))
        XCTAssertEqual(chapters.map(\.title), ["引言", "第一章", "第二章", "第三章"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(book.totalChapterNum, 4)
        XCTAssertEqual(book.durChapterIndex, 2); XCTAssertEqual(book.durChapterPos, 7)
        XCTAssertEqual(book.durChapterTitle, "第二章")
        XCTAssertTrue(chapters[2].isCached)
        XCTAssertEqual(chapters[2].cachePath, "existing-cache.txt")
        XCTAssertEqual(chapters[2].contentHash, "existing-hash")
        XCTAssertEqual(bookmark.chapterIndex, 3); XCTAssertEqual(bookmark.content, "书签正文")
        let identifiers = chapters.map(\.chapterId)
        try await ChapterDirectoryUpdater.repairStoredDirectory(for: book)
        XCTAssertEqual(try context.fetch(BookChapter.fetchRequest(byBookId: book.bookId)).map(\.chapterId), identifiers)
    }

    func testAuthorSearchFiltersByAuthorAndPreservesMergedSources() async throws {
        let database = try container()
        let context = database.viewContext
        let sources = (0..<2).map { index -> BookSource in
            let source = BookSource.create(in: context)
            source.bookSourceUrl = "https://example.invalid/\(index)"
            source.bookSourceName = "作者搜索测试源\(index)"
            source.searchUrl = "/search"
            return source
        }
        try context.save()
        let defaultsName = "author-search-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let requested = expectation(description: "每个书源只搜索一次")
        requested.expectedFulfillmentCount = sources.count
        requested.assertForOverFulfill = true
        let model = SearchViewModel(context: context, selectionDefaults: defaults) { source, keyword in
            XCTAssertEqual(keyword, "辰东")
            requested.fulfill()
            return [
                SearchBookResult(name: "遮天", author: " 辰东 ", bookUrl: source.bookSourceUrl + "/1"),
                SearchBookResult(name: "完美世界", author: "辰东", bookUrl: source.bookSourceUrl + "/2"),
                SearchBookResult(name: "辰东作品评论", author: "另一位作者", bookUrl: source.bookSourceUrl + "/3"),
                SearchBookResult(name: "辰东相关资料", author: "", bookUrl: source.bookSourceUrl + "/4")
            ]
        }
        XCTAssertEqual(model.searchMode, .all)
        model.searchMode = .author
        await model.search(keyword: "  辰东\n", sources: sources)
        await fulfillment(of: [requested], timeout: 3)
        XCTAssertEqual(model.searchResults.map(\.name), ["遮天", "完美世界"])
        XCTAssertEqual(model.searchResults.map(\.sourceCount), [2, 2])
        XCTAssertEqual(model.completedSourceCount, 2)
        let identifiers = model.searchResults.map(\.id)

        model.searchText = "尚未提交的新关键词"
        model.searchMode = .all
        XCTAssertEqual(model.searchResults.count, 4)
        model.searchMode = .author
        XCTAssertEqual(model.searchResults.map(\.id), identifiers, "切换方式使用已提交的关键词，并保留列表行和书源数量")
        XCTAssertEqual(model.searchResults.map(\.sourceCount), [2, 2])
        let reopened = SearchViewModel(context: context, selectionDefaults: defaults)
        XCTAssertEqual(reopened.searchMode, .author)

        model.clearSearch()
        model.searchMode = .all
        XCTAssertTrue(model.searchResults.isEmpty, "清空后切换方式不能重新显示旧结果")
        XCTAssertFalse(model.hasSearched)
    }

    func testAuthorSearchFiltersLateResultsAndCanRestoreGeneralResults() async throws {
        let database = try container()
        let context = database.viewContext
        let source = BookSource.create(in: context)
        source.bookSourceUrl = "https://example.invalid"
        source.bookSourceName = "作者搜索测试源"
        source.searchUrl = "/search"
        try context.save()
        let gate = SearchResponseGate()
        let started = expectation(description: "书源已开始搜索")
        let model = SearchViewModel(context: context, sourceTimeout: 5, selectionDefaults: nil) { _, _ in
            started.fulfill()
            await gate.wait()
            return [
                SearchBookResult(name: "Pride and Prejudice", author: " Jane Austen ", bookUrl: "https://example.invalid/1"),
                SearchBookResult(name: "Jane's Reading Guide", author: "Other Writer", bookUrl: "https://example.invalid/2"),
                SearchBookResult(name: "Jane's Notes", author: "", bookUrl: "https://example.invalid/3")
            ]
        }
        let task = Task { await model.search(keyword: "jane", sources: [source]) }
        await fulfillment(of: [started], timeout: 3)
        model.searchMode = .author
        await gate.release()
        await task.value
        XCTAssertEqual(model.searchResults.map(\.name), ["Pride and Prejudice"])
        XCTAssertEqual(model.completedSourceCount, 1)
        XCTAssertEqual(model.failedSourceCount, 0)
        XCTAssertFalse(model.isSearching)
        model.searchMode = .all
        XCTAssertEqual(model.searchResults.count, 3)
        await model.search(keyword: "unmatched", sources: [])
        model.searchMode = .author
        XCTAssertTrue(model.searchResults.isEmpty, "新搜索不能带回上次的结果")
    }

    func testSearchDropsRemovedSourcesAndKeepsAnUnnamedUsableSource() async throws {
        let database = try container()
        let context = database.viewContext
        let sources = (0..<4).map { index -> BookSource in
            let source = BookSource.create(in: context)
            source.bookSourceUrl = index == 3 ? " " : "https://example.invalid/\(index)"
            source.bookSourceName = index == 0 ? " " : "源\(index)"
            source.searchUrl = "/search"
            return source
        }
        try context.save()
        let gate = SearchResponseGate()
        let started = expectation(description: "已捕获三个有效书源")
        started.expectedFulfillmentCount = 3
        let model = SearchViewModel(context: context, sourceTimeout: 5, selectionDefaults: nil) { source, _ in
            started.fulfill()
            await gate.wait()
            return [SearchBookResult(name: "有效搜索结果", author: "作者", bookUrl: source.bookSourceUrl + "/book")]
        }
        let task = Task { await model.search(keyword: "搜索", sources: sources) }
        await fulfillment(of: [started], timeout: 3)
        context.delete(sources[1]); sources[2].enabled = false
        try context.save()
        await gate.release()
        await task.value
        XCTAssertEqual(model.totalSourceCount, 3)
        XCTAssertEqual(model.searchResults.count, 1)
        XCTAssertEqual(model.searchResults.first?.sourceId, sources[0].sourceId)
        XCTAssertEqual(model.searchResults.first?.sourceCount, 1)
        XCTAssertEqual(model.searchResults.first?.displaySourceName, sources[0].bookSourceUrl)
    }

    func testSearchKeepsAlternateSourceWhenTheFirstSourceDisappears() throws {
        let first = UUID(), second = UUID()
        var accumulator = SearchResultAccumulator()
        accumulator.append([
            BookSearchResult(name: "同一本书", author: "作者", sourceName: "原源", sourceId: first, bookUrl: "https://first.invalid/book"),
            BookSearchResult(name: "同一本书", author: "作者", sourceName: "备用源", sourceId: second, bookUrl: "https://second.invalid/book")
        ])
        let rowID = try XCTUnwrap(accumulator.results.first?.id)
        accumulator.retainSources([second])
        XCTAssertEqual(accumulator.results.first?.id, rowID)
        XCTAssertEqual(accumulator.results.first?.sourceCount, 1)
        XCTAssertEqual(accumulator.results.first?.sourceName, "备用源")
        XCTAssertEqual(accumulator.results.first?.bookUrl, "https://second.invalid/book")
        accumulator.retainSources([])
        XCTAssertTrue(accumulator.results.isEmpty)
    }

    func testLayoutPreservesShortLongAndUnicodeParagraphsAndDrawsEveryLine() async throws {
        let database = try container()
        let book = makeBook(in: database.viewContext)
        let provider = ChapterProvider.shared
        provider.updateViewSize(width: 390, height: 720)
        provider.updateStyle(titleFont: .systemFont(ofSize: 22), contentFont: .systemFont(ofSize: 20))
        let paragraphs = ["　　短句。", "ASCII abcXYZ123，组合字符 e\u{301}，家庭👨‍👩‍👧‍👦。"] +
            (0..<60).map { "第\($0)段：" + String(repeating: "山川与星河都在这里，每个段落的末尾必须保留。", count: 5) + "段落结束。" }
        let textChapter = chapter()
        let layout = TextChapterLayout(textChapter: textChapter, textPages: [], book: book,
                                       bookContent: BookContent(textList: paragraphs))
        await layout.startLayout()
        XCTAssertNil(layout.exception)
        XCTAssertGreaterThan(textChapter.pageSize, 4)
        func compact(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
        XCTAssertEqual(compact(textChapter.getContent()), compact("测试章节" + paragraphs.joined()))
        let firstBodyLine = try XCTUnwrap(textChapter.pages.first?.lines.first(where: { !$0.isTitle }))
        XCTAssertEqual(firstBodyLine.text.prefix(while: { $0.isWhitespace }).count,
                       ReadBookConfig.paragraphIndent.length, "书源已有缩进时不能再次叠加")
        for page in textChapter.pages {
            for line in page.lines {
                XCTAssertGreaterThanOrEqual(CGFloat(line.lineTop), provider.paddingTop)
                XCTAssertLessThanOrEqual(CGFloat(line.lineBottom), provider.visibleBottom + 0.01)
                XCTAssertGreaterThanOrEqual(CGFloat(line.lineStart), provider.paddingLeft - 0.01)
                XCTAssertLessThanOrEqual(CGFloat(line.lineEnd), provider.visibleRight + 0.01)
            }
        }
        let measure = TextMeasure(font: .systemFont(ofSize: 20))
        let measured = measure.measureTextSplit(text: "Wi👨‍👩‍👧‍👦e\u{301}")
        XCTAssertEqual(measured.strings.count, 4)
        XCTAssertGreaterThan(measured.widths[0], measured.widths[1])
        XCTAssertEqual(measured.strings.joined(), "Wi👨‍👩‍👧‍👦e\u{301}")

        let dataSource = FixturePageSource(chapter: textChapter)
        let reader = ReadView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        reader.pageFactory = TextPageFactory(dataSource: dataSource)
        reader.layoutIfNeeded()
        ReadBook.shared.msg = nil
        for dark in [false, true] {
            provider.textColor = dark ? .white : .black
            reader.backgroundColor = dark ? .black : .white
            (reader.curPage as? UIView)?.backgroundColor = reader.backgroundColor
            reader.upContent()
            reader.layer.displayIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: reader.bounds.size, format: format).image { context in
                reader.layer.render(in: context.cgContext)
            }
            let pixels = try rgba(image)
            let page = try XCTUnwrap(textChapter.pages.first)
            for line in page.lines where !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                XCTAssertGreaterThan(line.lineBase, line.lineTop)
                let minY = max(0, Int(line.lineTop))
                let maxY = min(720, Int(ceil(line.lineBottom)))
                var ink = 0
                for y in minY..<maxY {
                    for x in 10..<380 {
                        let value = pixels[(y * 390 + x) * 4]
                        if dark ? value > 100 : value < 150 { ink += 1 }
                    }
                }
                XCTAssertGreaterThan(ink, 8, "正文行应有可见像素：\(line.text)")
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = dark ? "阅读正文-暗色" : "阅读正文-亮色"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        reader.dispose()
    }

    func testPunctuationAndLetterSpacingStayInsideBothMargins() async throws {
        let database = try container()
        let book = makeBook(in: database.viewContext)
        let provider = ChapterProvider.shared
        let oldSize = CGSize(width: provider.viewWidth, height: provider.viewHeight)
        let oldFont = provider.contentFont
        let oldTitleFont = provider.titleFont
        let oldSpacing = provider.letterSpacing
        let oldPadding = [provider.paddingLeft, provider.paddingTop, provider.paddingRight, provider.paddingBottom]
        defer {
            provider.updateViewSize(width: oldSize.width, height: oldSize.height)
            provider.updateStyle(titleFont: oldTitleFont, contentFont: oldFont)
            provider.letterSpacing = oldSpacing
            provider.updatePadding(left: oldPadding[0], top: oldPadding[1], right: oldPadding[2], bottom: oldPadding[3])
        }
        let paragraphs = [String(repeating: "山川，。星河《（日月）》！？", count: 30),
                          String(repeating: "Latin Wi e\u{301} 👨‍👩‍👧‍👦中文；：", count: 20)]
        for width in [320.0, 393, 430] {
            for size in [18.0, 19, 24, 30] {
                for spacing in [0.0, 2, 5] {
                    provider.updateViewSize(width: width, height: 720)
                    provider.updatePadding(left: 16, top: 20, right: 16, bottom: 20)
                    provider.updateStyle(titleFont: .systemFont(ofSize: size + 2), contentFont: .systemFont(ofSize: size))
                    provider.letterSpacing = spacing
                    let text = chapter()
                    let layout = TextChapterLayout(textChapter: text, textPages: [], book: book,
                                                   bookContent: BookContent(textList: paragraphs))
                    await layout.startLayout()
                    XCTAssertNil(layout.exception)
                    for line in text.pages.flatMap(\.lines) {
                        XCTAssertGreaterThanOrEqual(CGFloat(line.lineStart), 16 - 0.01)
                        XCTAssertLessThanOrEqual(CGFloat(line.lineEnd), width - 16 + 0.01,
                                                "标点、字间距和组合字符不能占用边距：\(line.text)")
                    }
                    XCTAssertEqual(String(text.getContent().filter { !$0.isWhitespace }),
                                   String(("测试章节" + paragraphs.joined()).filter { !$0.isWhitespace }))
                }
            }
        }
    }

    func testScreenshotParagraphKeepsActualGlyphsInsideBothMargins() async throws {
        let database = try container()
        let book = makeBook(in: database.viewContext)
        let provider = ChapterProvider.shared
        let oldSize = CGSize(width: provider.viewWidth, height: provider.viewHeight)
        let oldFont = provider.contentFont
        let oldTitleFont = provider.titleFont
        let oldColor = provider.textColor
        let oldSpacing = provider.letterSpacing
        let oldIndent = ReadBookConfig.paragraphIndent
        let oldZhLayout = ReadBookConfig.useZhLayout
        let oldPadding = [provider.paddingLeft, provider.paddingTop, provider.paddingRight, provider.paddingBottom]
        defer {
            provider.updateViewSize(width: oldSize.width, height: oldSize.height)
            provider.updateStyle(titleFont: oldTitleFont, contentFont: oldFont, textColor: oldColor)
            provider.letterSpacing = oldSpacing
            ReadBookConfig.paragraphIndent = oldIndent
            ReadBookConfig.useZhLayout = oldZhLayout
            provider.updatePadding(left: oldPadding[0], top: oldPadding[1], right: oldPadding[2], bottom: oldPadding[3])
        }
        provider.updateViewSize(width: 393, height: 852)
        provider.updatePadding(left: 16, top: 20, right: 16, bottom: 20)
        provider.updateStyle(titleFont: .systemFont(ofSize: 21), contentFont: .systemFont(ofSize: 19), textColor: .black)
        provider.letterSpacing = 0
        ReadBookConfig.paragraphIndent = .four
        let paragraphs = [
            "一道数尺长寒光从朴刀中卷射而出，青光闪动下，当即便有三条青蛇被从中一刀两截的被劈飞，接着“砰砰”两声，其余两条青蛇也被大汉身上的白色光罩弹了开来，并在大汉刀光一个翻卷下，同样被砍成两段。",
            "这些青色长蛇一个照面便被虬髯大汉击溃，并就此现出原形，竟是几簇绿色杂草所化。",
            "虬髯大汉哼了一声，正要继续冲入草丛，突然面色一动，将朴刀一收的站在了原地。"
        ]
        for chineseLayout in [true, false] {
            ReadBookConfig.useZhLayout = chineseLayout
            let text = chapter()
            let layout = TextChapterLayout(textChapter: text, textPages: [], book: book,
                                          bookContent: BookContent(textList: paragraphs))
            await layout.startLayout()
            XCTAssertNil(layout.exception)
            XCTAssertEqual(String(text.getContent().filter { !$0.isWhitespace }),
                           String(("测试章节" + paragraphs.joined()).filter { !$0.isWhitespace }))
            let pageView = PageView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = true
            for page in text.pages {
                pageView.setPage(page)
                let image = UIGraphicsImageRenderer(size: pageView.bounds.size, format: format).image { context in
                    UIColor.white.setFill()
                    context.fill(pageView.bounds)
                    // 直接绘制原始页面，不裁剪边距，避免用遮住文字的方式通过检查。
                    pageView.draw(pageView.bounds)
                }
                let pixels = try rgba(image)
                let width = try XCTUnwrap(image.cgImage).width
                let height = try XCTUnwrap(image.cgImage).height
                var outsideInk = 0
                var insideInk = 0
                for y in 0..<height {
                    for x in 0..<width where pixels[(y * width + x) * 4] < 180 {
                        if x < 47 || x >= width - 47 { outsideInk += 1 }
                        else { insideInk += 1 }
                    }
                }
                XCTAssertEqual(outsideInk, 0, "实际绘制的字形不能侵入左右 16 点边距")
                XCTAssertGreaterThan(insideInk, 500, "正文必须实际绘出，不能只保证空白边距")
                let attachment = XCTAttachment(image: image)
                attachment.name = "截图段落-393点-19号字-中文排版\(chineseLayout)-第\(page.index + 1)页"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testAllFourMarginsAreSavedAndUsedForLayout() {
        let defaults = UserDefaults.standard
        let keys = ["reader.pageMargin", "readerPaddingLeft", "readerPaddingRight", "readerPaddingTop", "readerPaddingBottom"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        keys.forEach { defaults.removeObject(forKey: $0) }
        let initial = ReaderViewModel()
        XCTAssertEqual(initial.pagePadding.leading, initial.pagePadding.trailing)
        initial.pagePadding = .init(top: 24, leading: 28, bottom: 30, trailing: 28)
        let reopened = ReaderViewModel()
        XCTAssertEqual(reopened.pagePadding, initial.pagePadding)
        reopened.configureTextLayout(size: CGSize(width: 390, height: 720))
        XCTAssertEqual(ChapterProvider.shared.visibleWidth, 334)
        XCTAssertEqual(ChapterProvider.shared.visibleHeight, 666)
        XCTAssertEqual(ChapterProvider.shared.paddingLeft, 28)
        XCTAssertEqual(ChapterProvider.shared.paddingRight, 28)
    }

    func testScrollingReusesPageImagesAndPreservesFractionalMovement() throws {
        let text = chapter()
        for index in 0..<5 {
            let page = TextPage(text: "第\(index)页正文")
            page.index = index
            page.isCompleted = true
            text.appendPage(page)
        }
        text.isCompleted = true
        ReadBook.shared.msg = nil
        let source = FixturePageSource(chapter: text)
        source.pageIndex = 1
        let view = CountingReadView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        let pages = (0..<3).map { _ in CountingPageView(frame: view.bounds) }
        view.prevPage = pages[0]; view.curPage = pages[1]; view.nextPage = pages[2]
        view.pageFactory = TextPageFactory(dataSource: source)
        view.upContent()
        let scroll = ScrollPageDelegate(readView: view)
        view.pageDelegate = scroll
        scroll.setViewSize(width: 390, height: 720)
        scroll.setBitmap()
        XCTAssertEqual(pages.reduce(0) { $0 + $1.renderCount }, 3)
        for _ in 0..<20 { view.upContent(); scroll.setBitmap() }
        XCTAssertEqual(pages.reduce(0) { $0 + $1.renderCount }, 3, "重复触摸或界面更新应复用整页图片")
        source.pageIndex = 2
        view.upContent(); scroll.setBitmap()
        XCTAssertEqual(pages.reduce(0) { $0 + $1.renderCount }, 4, "跨一页只需绘制一个新相邻页")
        view.setStartPoint(0, 0, anim: false)
        let redrawsBeforeScrolling = view.redrawRequests
        let snapshotsBeforeScrolling = pages.reduce(0) { $0 + $1.renderCount }
        for frame in 1...30 { view.setTouchPoint(0, -CGFloat(frame) * 0.25, anim: false) }
        XCTAssertEqual(scroll.offset, -7.5, accuracy: 0.001, "惯性滚动的小数位移不能在每帧取整后累积误差")
        XCTAssertEqual(view.redrawRequests, redrawsBeforeScrolling, "滚动每一帧不能请求 UIView 整屏重绘")
        XCTAssertEqual(pages.reduce(0) { $0 + $1.renderCount }, snapshotsBeforeScrolling,
                       "页面内容未变化时，移动不能生成新截图")
        pages.forEach { $0.backgroundColor = .black }
        scroll.setBitmap()
        XCTAssertEqual(pages.reduce(0) { $0 + $1.renderCount }, 7, "换主题后应重新绘制")
        view.dispose()
    }

    func testScrollDragStartsWithoutReplayingTheTouchSlop() {
        let (view, scroll) = makeTouchScrollView()
        defer { view.dispose() }
        scroll.scroll(by: -120)
        let touch = FixtureReaderTouch()
        touch.send(.began, to: view, y: 360, at: 1)
        touch.send(.moved, to: view, y: 356, at: 1.02)
        touch.send(.moved, to: view, y: 351, at: 1.04)
        XCTAssertEqual(scroll.offset, -120, accuracy: 0.001, "点击容差内不能移动正文")
        touch.send(.moved, to: view, y: 349, at: 1.06)
        XCTAssertEqual(scroll.offset, -120, accuracy: 0.001, "识别拖动时不能突然补上之前的 11 点")
        touch.send(.moved, to: view, y: 348.5, at: 1.07)
        XCTAssertEqual(scroll.offset, -120.5, accuracy: 0.001)
        touch.send(.moved, to: view, y: 347.25, at: 1.08)
        XCTAssertEqual(scroll.offset, -121.75, accuracy: 0.001)
        touch.send(.moved, to: view, y: 348.5, at: 1.09)
        XCTAssertEqual(scroll.offset, -120.5, accuracy: 0.001, "反向移动也应逐点跟手")
        touch.send(.cancelled, to: view, y: 348.5, at: 1.10)
        XCTAssertFalse(scroll.isStarted)

        touch.send(.began, to: view, y: 400, at: 2)
        touch.send(.moved, to: view, y: 425, at: 2.02)
        XCTAssertEqual(scroll.offset, -120.5, accuracy: 0.001, "向下拖动的首个采样也不能跳动")
        touch.send(.moved, to: view, y: 425.75, at: 2.03)
        XCTAssertEqual(scroll.offset, -119.75, accuracy: 0.001)
        touch.send(.cancelled, to: view, y: 425.75, at: 2.04)
    }

    func testScrollReleaseUsesTouchTimeAndDropsVelocityAfterHoldingStill() {
        let (view, scroll) = makeTouchScrollView()
        defer { view.dispose() }
        let touch = FixtureReaderTouch()
        touch.send(.began, to: view, y: 360, at: 1)
        touch.send(.moved, to: view, y: 349, at: 1.02)
        touch.send(.moved, to: view, y: 329, at: 1.04)
        touch.send(.ended, to: view, y: 329, at: 1.05)
        XCTAssertTrue(scroll.isStarted, "连续拖动后松手仍应有惯性")
        XCTAssertTrue(view.isScroll)

        touch.send(.began, to: view, y: 360, at: 2)
        touch.send(.moved, to: view, y: 349, at: 2.02)
        touch.send(.moved, to: view, y: 329, at: 2.04)
        let heldOffset = scroll.offset
        touch.send(.ended, to: view, y: 329, at: 2.30)
        XCTAssertFalse(scroll.isStarted, "停住后松手不能重新滑动")
        XCTAssertFalse(view.isScroll)
        XCTAssertEqual(scroll.offset, heldOffset, accuracy: 0.001)
    }

    func testTouchStopsScrollInPlaceWithoutTurningPageAndPreservesOrdinaryTap() {
        let (view, scroll) = makeTouchScrollView()
        defer { view.dispose() }
        let callback = CountingReaderCallback()
        view.callBack = callback
        let savedCenterAction = AppConfig.clickActionMC
        let savedRightAction = AppConfig.clickActionMR
        AppConfig.clickActionMC = 0
        AppConfig.clickActionMR = 1
        defer {
            AppConfig.clickActionMC = savedCenterAction
            AppConfig.clickActionMR = savedRightAction
        }
        scroll.scroll(by: -120)
        view.setStartPoint(0, 0, anim: false)
        scroll.fling(startX: 0, startY: 0, velocityX: 0, velocityY: -400,
                     minX: 0, maxX: 0, minY: -720, maxY: 720)
        scroll.computeScroll(at: CACurrentMediaTime() + 0.02)
        let stoppedOffset = scroll.offset
        let touch = FixtureReaderTouch()
        touch.send(.began, to: view, x: 340, y: 360, at: 1)
        XCTAssertFalse(scroll.isStarted)
        XCTAssertEqual(scroll.offset, stoppedOffset, accuracy: 0.001, "按下时保留当前正文位置")
        scroll.computeScroll(at: CACurrentMediaTime() + 1)
        XCTAssertEqual(scroll.offset, stoppedOffset, accuracy: 0.001, "已取消动画的刷新不能继续推动正文")
        touch.send(.ended, to: view, x: 340, y: 360, at: 1.05)
        XCTAssertFalse(scroll.isStarted, "点停惯性不能同时触发右侧翻页")
        XCTAssertEqual(callback.menuCount, 0)
        touch.send(.began, to: view, y: 360, at: 2)
        touch.send(.moved, to: view, y: 355, at: 2.01)
        touch.send(.ended, to: view, y: 355, at: 2.05)
        XCTAssertEqual(callback.menuCount, 1, "普通点击仍应打开菜单")
        XCTAssertEqual(scroll.offset, stoppedOffset, accuracy: 0.001)
    }

    private func makeTouchScrollView() -> (ReadView, ScrollPageDelegate) {
        let text = chapter()
        for index in 0..<3 {
            let page = TextPage(text: "第\(index)页正文")
            page.index = index
            page.isCompleted = true
            text.appendPage(page)
        }
        text.isCompleted = true
        ReadBook.shared.msg = nil
        let source = FixturePageSource(chapter: text)
        source.pageIndex = 1
        let view = ReadView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        view.pageFactory = TextPageFactory(dataSource: source)
        view.layoutIfNeeded()
        view.upContent()
        let scroll = ScrollPageDelegate(readView: view)
        view.pageDelegate = scroll
        scroll.setViewSize(width: view.width, height: view.height)
        return (view, scroll)
    }

    private func rgba(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: cgImage.width, height: cgImage.height,
                                            bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return pixels
    }

    func testEPUBChapterNavigationUpdatesTheDisplayedHTML() async throws {
        let database = try container()
        let context = database.viewContext
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = makeBook(in: context)
        book.name = "EPUB 测试"; book.origin = "local"; book.bookUrl = directory.appendingPathComponent("sample.epub").path
        book.type = 1; book.folderName = directory.path; book.totalChapterNum = 2
        let chapters = try (0..<2).map { index -> BookChapter in
            let file = "chapter\(index).html"
            try "<html><body>EPUB 第\(index)章正文</body></html>".write(to: directory.appendingPathComponent(file), atomically: true, encoding: .utf8)
            let chapter = BookChapter.create(in: context, bookId: book.bookId, url: file, index: Int32(index), title: "第\(index)章")
            chapter.book = book; chapter.cachePath = file
            return chapter
        }
        try context.save()
        let model = ReaderViewModel()
        model.currentBook = book; model.chapters = chapters; model.totalChapters = 2
        try await model.loadChapter(at: 0)
        XCTAssertEqual(model.chapterHTMLURL?.lastPathComponent, "chapter0.html")
        await model.nextChapter()
        XCTAssertEqual(model.chapterHTMLURL?.lastPathComponent, "chapter1.html")
        XCTAssertTrue(model.chapterContent?.contains("第1章正文") == true)
        await model.prevChapter()
        XCTAssertEqual(model.chapterHTMLURL?.lastPathComponent, "chapter0.html")
    }

    func testPageGraphIsReleased() {
        weak var releasedChapter: TextChapter?
        weak var releasedPage: TextPage?
        weak var releasedLine: TextLine?
        weak var releasedColumn: TextColumn?
        autoreleasepool {
            let chapter = chapter()
            let page = TextPage(text: "正文")
            let line = TextLine()
            let column = TextColumn(start: 0, end: 20, charData: "文")
            chapter.appendPage(page)
            page.textChapter = chapter
            page.addLine(line)
            line.addColumn(column)
            releasedChapter = chapter; releasedPage = page
            releasedLine = line; releasedColumn = column
        }
        XCTAssertNil(releasedChapter)
        XCTAssertNil(releasedPage)
        XCTAssertNil(releasedLine)
        XCTAssertNil(releasedColumn)
    }

    func testDeletionCanBeRepeatedAndFileImportUpdatesExistingSource() async throws {
        let database = try container()
        let context = database.viewContext
        let book = makeBook(in: context)
        book.name = "删除测试"
        try context.save()
        let shelf = BookshelfViewModel(context: context)
        await shelf.loadBooks()
        XCTAssertEqual(shelf.books.count, 1)
        shelf.removeBook(book)
        shelf.removeBook(book)
        XCTAssertTrue(shelf.books.isEmpty)
        XCTAssertEqual(try context.count(for: Book.fetchRequest()), 0)
        let source = BookSource.create(in: context)
        source.bookSourceUrl = "https://example.invalid"
        source.bookSourceName = "旧名称"
        source.enabled = false
        try context.save()
        let id = source.sourceId
        let model = SourceViewModel(context: context)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(#"[{"bookSourceUrl":"https://example.invalid","bookSourceName":"推荐书源","bookSourceGroup":"推荐","enabled":true,"ruleSearch":{"bookList":"$.books"}}]"#.utf8).write(to: file)
        let summary = await model.importFromFiles([file])
        XCTAssertEqual(summary.successCount, 1)
        XCTAssertEqual(summary.updatedCount, 1)
        XCTAssertEqual(try context.count(for: BookSource.fetchRequest()), 1)
        XCTAssertEqual(source.sourceId, id)
        XCTAssertTrue(source.enabled)
        XCTAssertEqual(source.bookSourceGroup, "推荐")
        XCTAssertNotNil(source.getSearchRule())
        await model.loadSources()
        model.deleteSource(source)
        model.deleteSource(source)
        XCTAssertEqual(try context.count(for: BookSource.fetchRequest()), 0)
    }

    func testSearchStreamsFastSourcesAndIgnoresCancelledGeneration() async throws {
        let database = try container()
        let sources = (0..<30).map { index -> BookSource in
            let source = BookSource.create(in: database.viewContext)
            source.bookSourceName = "源\(index)"
            source.bookSourceUrl = "https://example.invalid/\(index)"
            source.searchUrl = "/search"
            source.weight = Int32(30 - index)
            return source
        }
        try database.viewContext.save()
        let model = SearchViewModel(context: database.viewContext, sourceTimeout: 0.15, selectionDefaults: nil) { source, key in
            if ["源0", "源1", "源2", "源3", "源4"].contains(source.bookSourceName) {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } else { try await Task.sleep(nanoseconds: 5_000_000) }
            return [SearchBookResult(name: key, author: "作者", bookUrl: source.bookSourceUrl + "/book")]
        }
        let pending = Task { await model.search(keyword: "第一本", sources: sources) }
        for _ in 0..<50 where model.searchResults.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(model.searchResults.first?.name, "第一本")
        let rowID = try XCTUnwrap(model.searchResults.first?.id)
        await pending.value
        XCTAssertEqual(model.searchResults.first?.id, rowID)
        XCTAssertEqual(model.completedSourceCount, 30)
        XCTAssertEqual(model.failedSourceCount, 5)
        XCTAssertEqual(model.searchResults.first?.sourceCount, 25)
        XCTAssertNil(model.errorMessage, "部分书源超时不能弹窗遮挡有效结果")
        let old = Task { await model.search(keyword: "旧搜索", sources: sources) }
        await Task.yield()
        model.cancelSearch()
        await model.search(keyword: "新搜索", sources: [sources[10]])
        await old.value
        XCTAssertEqual(model.searchResults.map(\.name), ["新搜索"])
        XCTAssertFalse(model.isSearching)
    }

    func testDetailPreviewDoesNotSaveUntilExplicitlyAddedAndDoesNotDuplicate() throws {
        let database = try container()
        let context = database.viewContext
        let source = BookSource.create(in: context)
        source.bookSourceUrl = "https://example.invalid"
        source.bookSourceName = "详情书源"
        try context.save()
        let result = BookSearchResult(name: "待加入的书", author: "作者", kind: "奇幻", wordCount: "120万字",
                                      sourceName: source.bookSourceName, sourceId: source.sourceId,
                                      bookUrl: source.bookSourceUrl + "/preview")
        let first = BookDetailViewModel(result: result, context: context)
        let second = BookDetailViewModel(result: result, context: context)
        XCTAssertFalse(first.isInBookshelf)
        first.book.intro = "预览页加载的简介"
        first.book.tocUrl = source.bookSourceUrl + "/toc"
        try context.save()
        XCTAssertEqual(try context.count(for: Book.fetchRequest()), 0, "主上下文保存不能把浏览中的书放入书架")
        XCTAssertTrue(first.addToBookshelf())
        XCTAssertTrue(first.isInBookshelf)
        XCTAssertEqual(first.book.intro, "预览页加载的简介")
        XCTAssertEqual(first.book.kind, "奇幻")
        XCTAssertEqual(first.book.wordCount, "120万字")
        XCTAssertEqual(first.book.source?.objectID, source.objectID)
        first.book.durChapterIndex = 12; first.book.durChapterPos = 5
        try context.save()
        XCTAssertTrue(second.addToBookshelf())
        XCTAssertTrue(first.addToBookshelf())
        XCTAssertTrue(second.book === first.book)
        XCTAssertEqual(try context.count(for: Book.fetchRequest()), 1)
        XCTAssertEqual(second.book.durChapterIndex, 12)
        XCTAssertEqual(second.book.durChapterPos, 5)
    }

    func testOpeningExistingSearchResultPreservesProgressAndBookSettings() throws {
        let database = try container()
        let book = makeBook(in: database.viewContext)
        book.durChapterIndex = 8; book.durChapterPos = 3
        book.totalChapterNum = 60; book.group = 7; book.order = -1
        book.tocUrl = "https://example.invalid/saved-toc"
        book.customIntro = "自定义简介"
        try database.viewContext.save()
        let result = BookSearchResult(name: book.name, author: book.author,
                                      sourceName: "搜索书源", sourceId: UUID(), bookUrl: book.bookUrl)
        let model = BookDetailViewModel(result: result, context: database.viewContext)
        XCTAssertTrue(model.isInBookshelf)
        XCTAssertTrue(model.book === book)
        XCTAssertFalse(database.viewContext.hasChanges, "仅浏览已有书籍不应写入默认字段")
        XCTAssertTrue(model.startReading())
        XCTAssertEqual(book.durChapterIndex, 8)
        XCTAssertEqual(book.durChapterPos, 3)
        XCTAssertEqual(book.totalChapterNum, 60)
        XCTAssertEqual(book.group, 7)
        XCTAssertEqual(book.order, -1)
        XCTAssertEqual(book.tocUrl, "https://example.invalid/saved-toc")
        XCTAssertEqual(book.customIntro, "自定义简介")
    }

    func testAddingBookReportsSaveFailureAndCanRetry() throws {
        let database = try container()
        let context = FailingBookSaveContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = database.persistentStoreCoordinator
        let result = BookSearchResult(name: "待保存", author: "作者", sourceName: "书源",
                                      sourceId: UUID(), bookUrl: "https://example.invalid/new")
        let model = BookDetailViewModel(result: result, context: context)
        context.failSave = true
        XCTAssertFalse(model.startReading())
        XCTAssertFalse(model.isInBookshelf)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(try context.count(for: Book.fetchRequest()), 0)
        context.failSave = false
        XCTAssertTrue(model.startReading(chapterIndex: 2, chapterTitle: "第三章"))
        XCTAssertTrue(model.isInBookshelf)
        XCTAssertEqual(model.book.durChapterIndex, 2)
        XCTAssertEqual(model.book.durChapterTitle, "第三章")
        XCTAssertEqual(try context.count(for: Book.fetchRequest()), 1)
    }

    func testSearchRemembersSelectedSourcesAndAnEmptySelection() throws {
        let database = try container()
        let suite = "SearchSelectionTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sources = (0..<3).map { index -> BookSource in
            let source = BookSource.create(in: database.viewContext)
            source.bookSourceName = "源\(index)"
            source.bookSourceUrl = "https://example.invalid/\(index)"
            source.searchUrl = "/search"
            return source
        }
        try database.viewContext.save()
        let first = SearchViewModel(context: database.viewContext, selectionDefaults: defaults)
        XCTAssertEqual(first.selectedSources.count, 3)
        first.selectedSources = [sources[1]]
        let reopened = SearchViewModel(context: database.viewContext, selectionDefaults: defaults)
        XCTAssertEqual(reopened.selectedSources.map(\.sourceId), [sources[1].sourceId])
        reopened.selectedSources = []
        XCTAssertTrue(SearchViewModel(context: database.viewContext, selectionDefaults: defaults).selectedSources.isEmpty)
    }

    func testCrossChapterBackwardsReflowAndScrollingKeepTextAndPosition() async throws {
        let database = try container()
        let context = database.viewContext
        let book = makeBook(in: context)
        book.name = "跨章阅读"; book.origin = "https://example.invalid"; book.bookUrl = book.origin + "/book"
        book.totalChapterNum = 2
        let files = (0..<2).map { _ in FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
        defer { files.forEach { try? FileManager.default.removeItem(at: $0) }; ReadBook.shared.releaseAndCancel(); ReadBook.shared.clearTextChapter(); ReadBook.shared.book = nil }
        for index in 0..<2 {
            try String(repeating: "第\(index)章：这是正文，末尾不能缺少。\n", count: 80).write(to: files[index], atomically: true, encoding: .utf8)
            let chapter = BookChapter.create(in: context, bookId: book.bookId, url: "/\(index)", index: Int32(index), title: "第\(index)章")
            chapter.book = book; chapter.isCached = true; chapter.cachePath = files[index].path
        }
        try context.save()
        let reader = ReadBook.shared
        reader.callBack = nil
        ChapterProvider.shared.updateViewSize(width: 390, height: 720)
        reader.resetData(book)
        reader.loadContent()
        for _ in 0..<100 where reader.curTextChapter == nil || reader.nextTextChapter == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let first = try XCTUnwrap(reader.curTextChapter)
        XCTAssertGreaterThan(first.pageSize, 2)
        let factory = TextPageFactory(dataSource: reader)
        reader.setPageIndex(first.lastIndex)
        XCTAssertTrue(factory.moveToNext(upContent: true))
        XCTAssertEqual(reader.durChapterIndex, 1)
        XCTAssertTrue(factory.moveToPrev(upContent: true))
        XCTAssertEqual(reader.durChapterIndex, 0)
        XCTAssertEqual(reader.durChapterPos, first.lastIndex)
        XCTAssertTrue(reader.curTextChapter === first, "预排版的章节应直接复用")
        reader.setPageIndex(0)
        let view = ReadView(frame: CGRect(x: 0, y: 0, width: 390, height: 720))
        view.pageFactory = factory
        view.layoutIfNeeded(); view.upContent()
        let scroll = ScrollPageDelegate(readView: view)
        view.pageDelegate = scroll
        scroll.setViewSize(width: 390, height: 720)
        scroll.scroll(by: -780)
        XCTAssertEqual(reader.durChapterPos, 1)
        XCTAssertEqual(scroll.offset, -60, accuracy: 1)
        scroll.scroll(by: 780)
        XCTAssertEqual(reader.durChapterPos, 0)
        XCTAssertEqual(scroll.offset, 0, accuracy: 1)
        view.dispose()
        reader.setPageIndex(1)
        let position = first.getReadLength(1)
        ChapterProvider.shared.updateStyle(contentFont: .systemFont(ofSize: 28))
        reader.loadContent(resetPageOffset: false, forceRebuild: true)
        for _ in 0..<100 where reader.curTextChapter == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let resized = try XCTUnwrap(reader.curTextChapter)
        XCTAssertEqual(reader.durChapterPos, resized.getPageIndexByCharIndex(position))
    }
}

private final class FailingBookSaveContext: NSManagedObjectContext {
    var failSave = false
    override func save() throws {
        if failSave { throw NSError(domain: "BookSaveFixture", code: 1) }
        try super.save()
    }
}

@MainActor
private final class FixturePageSource: PageDataSource {
    var currentChapter: TextChapter?
    var prevChapter: TextChapter?
    var nextChapter: TextChapter?
    var pageIndex = 0
    init(chapter: TextChapter) { currentChapter = chapter }
    func hasPrevChapter() -> Bool { false }
    func hasNextChapter() -> Bool { false }
}

@MainActor
private final class CountingPageView: PageView {
    private(set) var renderCount = 0
    override func screenshot() -> UIImage? {
        renderCount += 1
        return super.screenshot()
    }
}

@MainActor
private final class CountingReadView: ReadView {
    private(set) var redrawRequests = 0
    override func setNeedsDisplay() {
        redrawRequests += 1
        super.setNeedsDisplay()
    }
}

/// 通过 ReadView 的真实触摸入口重放采样，覆盖点击容差和代理之间的衔接。
@MainActor
private final class FixtureReaderTouch: UITouch {
    private var point = CGPoint.zero
    private var samplePhase: UITouch.Phase = .began
    private var sampleTime: TimeInterval = 0
    override var phase: UITouch.Phase { samplePhase }
    override var timestamp: TimeInterval { sampleTime }
    override func location(in view: UIView?) -> CGPoint { point }

    func send(_ phase: UITouch.Phase, to view: ReadView, x: CGFloat = 190,
              y: CGFloat, at timestamp: TimeInterval) {
        point = CGPoint(x: x, y: y)
        samplePhase = phase
        sampleTime = timestamp
        switch phase {
        case .began: view.touchesBegan([self], with: nil)
        case .moved: view.touchesMoved([self], with: nil)
        case .ended: view.touchesEnded([self], with: nil)
        case .cancelled: view.touchesCancelled([self], with: nil)
        default: break
        }
    }
}

@MainActor
private final class CountingReaderCallback: ReadViewCallBack {
    private(set) var menuCount = 0
    func showActionMenu() { menuCount += 1 }
    func hideActionMenu() {}
    func addBookmark() {}
    func showTextActionMenu() {}
    func screenOffTimerStart() {}
    func upSystemUiVisibility() {}
    func autoPageStop() {}
    func upContent() {}
    func upMenuView() {}
    func upPageAnim() {}
}
