import XCTest
import CoreData
@testable import Legado

final class LegadoStabilityTests: XCTestCase {
    func testSerializedNumbersAndMissingInnerRules() throws {
        let engine = RuleEngine()
        let body = "{\"items\":[{\"idx\":0,\"titles\":[\"测试书籍\"]},{\"titles\":[\"缺字段\"]}]}"
        let items = try engine.getElements(ruleStr: "$.items", body: body, baseUrl: "https://example.invalid")
        XCTAssertEqual(engine.getString(ruleStr: "$.titles[{$.idx}]", elementContext: items[0]), "测试书籍")
        XCTAssertEqual(engine.getString(ruleStr: "$.titles[{$.idx}]", elementContext: items[1]), "")
    }

    @MainActor
    func testTextLayoutPublishesCompletedPages() async throws {
        let modelURL = try XCTUnwrap(Bundle.main.url(forResource: "Legado", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        let container = NSPersistentContainer(name: "LayoutTest", managedObjectModel: model)
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [store]
        container.loadPersistentStores { _, error in XCTAssertNil(error) }
        let book = Book.create(in: container.viewContext)
        ChapterProvider.shared.updateViewSize(width: 390, height: 780)
        let chapter = TextChapter(chapter: nil, position: 0, title: "测试章节", chaptersSize: 1,
                                  sameTitleRemoved: false, isVip: false, isPay: false, effectiveReplaceRules: nil)
        let layout = TextChapterLayout(textChapter: chapter, textPages: [], book: book,
                                       bookContent: BookContent(textList: ["这是实际排版的测试正文。", "第二段正文。"] ))
        await layout.startLayout()
        XCTAssertNil(layout.exception)
        XCTAssertTrue(chapter.isCompleted)
        XCTAssertGreaterThan(chapter.pages.count, 0)
        XCTAssertNotNil(chapter.getPage(0))
    }

    @MainActor
    func testWebViewCompletesAndCancels() async throws {
        let response = try await BackstageWebView(html: "<html><body>测试正文</body></html>",
                                                  javaScript: "document.body.textContent", delayTime: 0, timeout: 5000).getStrResponse()
        XCTAssertEqual(response.body, "测试正文")
        let cancelled = Task { @MainActor in
            try await BackstageWebView(html: "<html><body>取消</body></html>", delayTime: Int64.max, timeout: Int64.max).getStrResponse()
        }
        await Task.yield()
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("取消后仍返回正文") }
        catch is CancellationError {}
        let next = try await BackstageWebView(html: "<html><body>继续</body></html>",
                                              javaScript: "document.body.textContent", timeout: 5000).getStrResponse()
        XCTAssertEqual(next.body, "继续")
    }

    func testHTTPAndDatabaseSourceReplacement() async throws {
        let modelURL = try XCTUnwrap(Bundle.main.url(forResource: "Legado", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        let container = NSPersistentContainer(name: "Regression", managedObjectModel: model)
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [store]
        container.loadPersistentStores { _, error in XCTAssertNil(error) }
        let context = container.newBackgroundContext()
        let base = ProcessInfo.processInfo.environment["LEGADO_FIXTURE_URL"] ?? "http://127.0.0.1:8766"
        let created = try await context.perform { () -> (Book, BookSource) in
            let source = BookSource.create(in: context)
            source.bookSourceUrl = base
            source.bookSourceName = "模拟器测试书源"
            source.searchUrl = base + "/search"
            source.setSearchRule(.init(bookList: "$.books", name: "$.titles[{$.idx}]", author: "$.author", bookUrl: "$.url"))
            source.setBookInfoRule(.init(name: "$.name", author: "$.author", tocUrl: "$.toc"))
            source.setTocRule(TocRule(bookList: "$.chapters", chapterName: "$.name", chapterUrl: "$.url"))
            source.setContentRule(.init(content: "$.content"))
            let book = Book.create(in: context)
            book.name = "测试书籍"; book.author = "测试作者"
            book.origin = "old-source"; book.originName = "旧源"
            book.bookUrl = base + "/old"; book.tocUrl = base + "/oldtoc"
            book.totalChapterNum = 2; book.durChapterIndex = 1
            for index in 0..<2 {
                let chapter = BookChapter.create(in: context, bookId: book.bookId, url: "/old/\(index)", index: Int32(index), title: "旧章节")
                chapter.book = book
            }
            try context.save()
            return (book, source)
        }
        let (book, source) = created
        let definition = try BookSourceSnapshot.capture(source)
        let result = try await WebBook.searchBook(source: definition, key: "测试")
        XCTAssertEqual(result.first?.name, "测试书籍")
        XCTAssertEqual(result.first?.bookUrl, base + "/book")
        let original = try BookRequestSnapshot.capture(book)
        var candidate = original
        candidate.origin = base; candidate.bookUrl = base + "/book"; candidate.tocUrl = base + "/book"
        candidate = try await WebBook.getBookInfo(source: definition, book: candidate)
        let chapters = try await WebBook.getChapterList(source: definition, book: candidate)
        try await ChapterDirectoryUpdater.replace(book: book, source: source, original: original,
                                                  metadata: candidate, definition: definition, chapters: chapters)
        XCTAssertEqual(try ManagedObjectAccess.read(book) { $0.durChapterIndex }, 2)
        XCTAssertEqual(try ManagedObjectAccess.read(book) { $0.chapters?.count }, 4)
        let exported = try BackupStore.export(context: context)
        let count = try context.performAndWait { try context.count(for: Book.fetchRequest()) }
        XCTAssertThrowsError(try BackupStore.restore(["books": [["bookUrl": "bad", "durChapterIndex": Int64.max]]], container: container))
        XCTAssertEqual(try context.performAndWait { try context.count(for: Book.fetchRequest()) }, count)
        XCTAssertNotNil((exported["sources"] as? [[String: Any]])?.first?["ruleSearch"])
    }
}
