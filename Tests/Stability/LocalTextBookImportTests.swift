import XCTest
import CoreData
@testable import Legado

@MainActor
final class LocalTextBookImportTests: XCTestCase {
    private func container() throws -> NSPersistentContainer {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Legado", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
        let container = NSPersistentContainer(name: UUID().uuidString, managedObjectModel: model)
        let store = NSPersistentStoreDescription()
        store.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [store]
        container.loadPersistentStores { _, error in XCTAssertNil(error) }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testSharedTextStaysReadableAfterOriginalIsRemovedAndDatabaseIsReopened() async throws {
        let database = try container()
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("星河.TXT")
        try "引言内容\n第1章 出发\n第一章正文，中文与 Unicode e\u{301} 都应保留。\n第2章 归来\n第二章正文。".write(to: original, atomically: true, encoding: .utf8)
        let library = root.appendingPathComponent("LocalBooks", isDirectory: true)
        let importer = LocalTextBookImporter(container: database, libraryDirectory: library)
        let book = try await importer.importBook(url: original)
        XCTAssertEqual(book.name, "星河")
        XCTAssertEqual(book.totalChapterNum, 3)
        XCTAssertTrue(book.isLocal)
        XCTAssertFalse(book.canUpdate)
        let savedFile = try XCTUnwrap(book.localFileURL)
        XCTAssertEqual(savedFile.deletingLastPathComponent(), library)
        XCTAssertNotEqual(savedFile, original)
        let id = book.objectID
        try FileManager.default.removeItem(at: original)
        database.viewContext.reset()
        let reopened = try XCTUnwrap(try database.viewContext.existingObject(with: id) as? Book)
        let chapters = try database.viewContext.fetch(BookChapter.fetchRequest(byBookId: reopened.bookId))
        XCTAssertEqual(chapters.map(\.title), ["前言", "第1章 出发", "第2章 归来"])
        XCTAssertTrue(chapters.allSatisfy { $0.book === reopened && $0.isCached })
        let body = try await ChapterContentLoader.load(chapter: chapters[1], book: reopened)
        XCTAssertTrue(body.contains("第一章正文"))
        XCTAssertTrue(body.contains("e\u{301}"))
        XCTAssertFalse(body.contains("第二章正文"))
        let lastBody = try await ChapterContentLoader.load(chapter: chapters[2], book: reopened)
        XCTAssertTrue(lastBody.contains("第二章正文"))
    }

    func testRepeatedSharingKeepsProgressAndChangedFileWithSameNameCreatesAnotherBook() async throws {
        let database = try container()
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("同名.txt")
        let content = "第1章\n第一章正文\n第2章\n第二章正文"
        try content.write(to: original, atomically: true, encoding: .utf8)
        let importer = LocalTextBookImporter(container: database, libraryDirectory: root.appendingPathComponent("LocalBooks"))
        let book = try await importer.importBook(url: original)
        book.durChapterIndex = 1; book.durChapterPos = 2; book.customIntro = "保留的简介"; book.group = 7
        try database.viewContext.save()
        let anotherLocation = root.appendingPathComponent("其他文件名.TXT")
        try content.write(to: anotherLocation, atomically: true, encoding: .utf8)
        async let first = importer.importBook(url: original)
        async let second = importer.importBook(url: anotherLocation)
        let repeats = try await [first, second]
        XCTAssertTrue(repeats.allSatisfy { $0.bookId == book.bookId })
        database.viewContext.refresh(book, mergeChanges: true)
        XCTAssertEqual(book.durChapterIndex, 1)
        XCTAssertEqual(book.durChapterPos, 2)
        XCTAssertEqual(book.customIntro, "保留的简介")
        XCTAssertEqual(book.group, 7)
        XCTAssertEqual(try database.viewContext.count(for: Book.fetchRequest()), 1)
        try "第1章\n这是同名但不同正文的文件。".write(to: original, atomically: true, encoding: .utf8)
        let different = try await importer.importBook(url: original)
        XCTAssertNotEqual(different.bookId, book.bookId)
        XCTAssertNotEqual(different.bookUrl, book.bookUrl)
        XCTAssertEqual(try database.viewContext.count(for: Book.fetchRequest()), 2)
        XCTAssertTrue(try String(contentsOf: try XCTUnwrap(book.localFileURL), encoding: .utf8).contains("第一章正文"))
    }

    func testChapterTitlesKeepPunctuationAndNoSpacesWithoutSplittingBodyLines() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("章节标题.txt")
        try "第1章初见\n第一章正文，保留完整内容。\n第2章 难道是你？\n第二章正文\n正文继续，不另起一章。".write(to: file, atomically: true, encoding: .utf8)
        let parsed = try TxtFileParser.parse(file: file)
        XCTAssertEqual(parsed.chapters.map(\.title), ["第1章初见", "第2章 难道是你？"])
        let first = try TxtFileParser.readChapter(file: file, chapterIndex: 0, metadataTag: parsed.chapters[0].metadataTag)
        let second = try TxtFileParser.readChapter(file: file, chapterIndex: 1, metadataTag: parsed.chapters[1].metadataTag)
        XCTAssertTrue(first.contains("第一章正文，保留完整内容。"))
        XCTAssertTrue(second.contains("第二章正文"))
        XCTAssertTrue(second.contains("正文继续，不另起一章。"))
    }

    func testEmptyAndFailedImportsLeaveNoBookAndCanRetry() async throws {
        let database = try container()
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("失败重试.txt")
        let library = root.appendingPathComponent("LocalBooks")
        let context = FailingTextImportContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = database.persistentStoreCoordinator
        let importer = LocalTextBookImporter(container: database, libraryDirectory: library, importContext: context)
        try " \n　\t".write(to: original, atomically: true, encoding: .utf8)
        do { _ = try await importer.importBook(url: original); XCTFail("空正文不能加入书架") }
        catch { XCTAssertTrue(error.localizedDescription.contains("正文")) }
        try "第1章\n保存失败后能够再次导入的正文。".write(to: original, atomically: true, encoding: .utf8)
        await context.perform { context.failSave = true }
        do { _ = try await importer.importBook(url: original); XCTFail("数据库保存失败应报错") }
        catch { XCTAssertTrue(error.localizedDescription.contains("模拟保存失败")) }
        XCTAssertEqual(try database.viewContext.count(for: Book.fetchRequest()), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        await context.perform { context.failSave = false }
        let retried = try await importer.importBook(url: original)
        XCTAssertEqual(retried.totalChapterNum, 1)
        XCTAssertEqual(try database.viewContext.count(for: Book.fetchRequest()), 1)
    }

    func testChineseLegacyEncodingAndUTF16KeepChapterBodies() async throws {
        let database = try container()
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let importer = LocalTextBookImporter(container: database, libraryDirectory: root.appendingPathComponent("LocalBooks"))
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        for encoding in [gb, .utf16LittleEndian, .utf16BigEndian] {
            let text = "第1章 出发\n中文正文，编码必须正确。\n第2章 归来\n完整保留第二章。"
            let file = root.appendingPathComponent("编码\(encoding.rawValue).txt")
            var data = try XCTUnwrap(text.data(using: encoding))
            if encoding == .utf16LittleEndian { data = Data([0xff, 0xfe]) + data }
            if encoding == .utf16BigEndian { data = Data([0xfe, 0xff]) + data }
            try data.write(to: file)
            let book = try await importer.importBook(url: file)
            let chapters = try database.viewContext.fetch(BookChapter.fetchRequest(byBookId: book.bookId))
            XCTAssertEqual(chapters.count, 2)
            let body = try await ChapterContentLoader.load(chapter: chapters[0], book: book)
            XCTAssertTrue(body.contains("中文正文，编码必须正确"))
        }
    }
}

private final class FailingTextImportContext: NSManagedObjectContext {
    var failSave = false
    override func save() throws {
        if failSave { throw NSError(domain: "LocalTextBookImportTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "模拟保存失败"]) }
        try super.save()
    }
}
