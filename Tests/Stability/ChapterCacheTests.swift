import XCTest
import CoreData
@testable import Legado

@MainActor
final class ChapterCacheTests: XCTestCase {
    private func fixture(count: Int) throws -> (NSPersistentContainer, Book, [BookChapter]) {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Legado", withExtension: "momd"))
        let schema = try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
        let database = NSPersistentContainer(name: UUID().uuidString, managedObjectModel: schema)
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        database.persistentStoreDescriptions = [store]
        database.loadPersistentStores { _, error in XCTAssertNil(error) }
        let context = database.viewContext
        let book = Book.create(in: context)
        book.name = "缓存测试"; book.author = "测试作者"
        book.origin = "https://example.invalid"; book.originName = "测试书源"
        book.bookUrl = book.origin + "/book"; book.tocUrl = book.origin + "/toc"
        let chapters = (0..<count).map { index -> BookChapter in
            let chapter = BookChapter.create(in: context, bookId: book.bookId, url: "/chapter/\(index + 1)",
                                             index: Int32(index), title: "第\(index + 1)章")
            chapter.book = book
            return chapter
        }
        try context.save()
        return (database, book, chapters)
    }

    func testDefaultSelectionRangeFailuresAndRetryPreserveCachedChapters() async throws {
        let (database, book, chapters) = try fixture(count: 4)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func save(_ chapter: BookChapter) throws {
            let file = directory.appendingPathComponent(chapter.chapterId.uuidString)
            try "第\(chapter.index + 1)章缓存正文".write(to: file, atomically: true, encoding: .utf8)
            chapter.isCached = true; chapter.cachePath = file.path
            try database.viewContext.save()
        }
        try save(chapters[1])
        chapters[2].isCached = true
        chapters[2].cachePath = directory.appendingPathComponent("missing.txt").path
        try database.viewContext.save()
        var requests: [Int32] = []
        var failOnce = true
        let model = ChapterCacheViewModel(book: book) { chapter, _ in
            requests.append(chapter.index)
            if chapter.index == 3 && failOnce {
                failOnce = false
                throw URLError(.secureConnectionFailed)
            }
            try save(chapter)
        }
        await model.loadChapters()
        XCTAssertEqual(model.selectedIDs.count, 4, "缓存页默认全选")
        XCTAssertEqual(model.cachedSelectionCount, 1, "文件丢失不能算已缓存")
        model.startNumber = "4"; model.endNumber = "2"
        model.selectRange()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.selectedIDs.count, 4, "无效范围不能悄悄改变选择")
        model.startNumber = "2"; model.endNumber = "4"
        model.selectRange()
        model.startCaching()
        await model.waitForCompletion()
        XCTAssertEqual(Set(requests), Set([2, 3]))
        XCTAssertEqual(model.completedCount, 3)
        XCTAssertEqual(model.savedCount, 1)
        XCTAssertEqual(model.skippedCount, 1)
        XCTAssertEqual(model.failedCount, 1)
        XCTAssertTrue(model.failures.first?.contains("TLS") == true)
        XCTAssertEqual(model.status, "部分章节缓存失败")
        XCTAssertFalse(chapters[0].isCached, "范围外的章节不能下载")
        requests = []
        model.startCaching()
        await model.waitForCompletion()
        XCTAssertEqual(requests, [3], "再次开始只下载未完成的章节")
        XCTAssertEqual(model.savedCount, 1)
        XCTAssertEqual(model.skippedCount, 2)
        XCTAssertEqual(model.failedCount, 0)
        XCTAssertEqual(model.cachedSelectionCount, 3)
    }

    func testStoppingCancelsActiveRequestsWithoutStartingRemainingChapters() async throws {
        let (database, book, _) = try fixture(count: 20)
        var started = 0
        var active = 0
        var peak = 0
        let model = ChapterCacheViewModel(book: book) { _, _ in
            started += 1; active += 1; peak = max(peak, active)
            defer { active -= 1 }
            try await Task.sleep(nanoseconds: 30_000_000_000)
        }
        await model.loadChapters()
        model.startCaching()
        for _ in 0..<100 where started < 3 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(started, 3)
        model.stopCaching()
        await model.waitForCompletion()
        XCTAssertEqual(active, 0)
        XCTAssertEqual(peak, 3)
        XCTAssertEqual(started, 3)
        XCTAssertEqual(model.savedCount, 0)
        XCTAssertEqual(model.failedCount, 0, "用户停止不应计为下载失败")
        XCTAssertFalse(model.isCaching)
        XCTAssertEqual(model.status, "缓存已停止")
        XCTAssertEqual(try database.viewContext.count(for: BookChapter.fetchRequest()), 20)
    }

    func testDownloadedChapterCanBeReadWithoutAWorkingNetworkURL() async throws {
        let (database, book, chapters) = try fixture(count: 1)
        let source = BookSource.create(in: database.viewContext)
        source.bookSourceName = "缓存测试书源"
        source.bookSourceUrl = "http://127.0.0.1:8766"
        source.setContentRule(.init(content: "$.content"))
        book.origin = source.bookSourceUrl; book.source = source
        chapters[0].chapterUrl = source.bookSourceUrl + "/chapter/1"
        try database.viewContext.save()
        let file = ChapterContentLoader.cacheURL(chapters[0].chapterId.uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: file) }
        let model = ChapterCacheViewModel(book: book)
        await model.loadChapters()
        model.startCaching()
        await model.waitForCompletion()
        XCTAssertEqual(model.savedCount, 1)
        XCTAssertEqual(model.failedCount, 0, model.failures.joined(separator: "\n"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        chapters[0].chapterUrl = "http://127.0.0.1:1/network-must-not-be-used"
        try database.viewContext.save()
        let text = try await ChapterContentLoader.load(chapter: chapters[0], book: book)
        XCTAssertTrue(text.contains("第1章正文"))
    }
}
