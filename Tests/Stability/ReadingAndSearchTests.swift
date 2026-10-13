import XCTest
import CoreData
import UIKit
@testable import Legado

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

    func testLayoutPreservesShortLongAndUnicodeParagraphsAndDrawsEveryLine() async throws {
        let database = try container()
        let book = Book.create(in: database.viewContext)
        let provider = ChapterProvider.shared
        provider.updateViewSize(width: 390, height: 720)
        provider.updateStyle(titleFont: .systemFont(ofSize: 22), contentFont: .systemFont(ofSize: 20))
        let paragraphs = ["短句。", "ASCII abcXYZ123，组合字符 e\u{301}，家庭👨‍👩‍👧‍👦。"] +
            (0..<60).map { "第\($0)段：" + String(repeating: "山川与星河都在这里，每个段落的末尾必须保留。", count: 5) + "段落结束。" }
        let textChapter = chapter()
        let layout = TextChapterLayout(textChapter: textChapter, textPages: [], book: book,
                                       bookContent: BookContent(textList: paragraphs))
        await layout.startLayout()
        XCTAssertNil(layout.exception)
        XCTAssertGreaterThan(textChapter.pageSize, 4)
        func compact(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
        XCTAssertEqual(compact(textChapter.getContent()), compact("测试章节" + paragraphs.joined()))
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
        let book = Book.create(in: context)
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
        let book = Book.create(in: context)
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
        let model = SearchViewModel(context: database.viewContext, sourceTimeout: 0.15) { source, key in
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

    func testCrossChapterBackwardsReflowAndScrollingKeepTextAndPosition() async throws {
        let database = try container()
        let context = database.viewContext
        let book = Book.create(in: context)
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
