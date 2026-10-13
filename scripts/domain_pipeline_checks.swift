import Foundation
import CoreData

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
    print("PASS: \(message)")
}

let arguments = CommandLine.arguments
let model = try loadTestModel(URL(fileURLWithPath: arguments[3]))
let base = arguments[4]
let directory = URL(fileURLWithPath: arguments[5])
let container = NSPersistentContainer(name: "Legado", managedObjectModel: model)
let store = NSPersistentStoreDescription(url: directory.appendingPathComponent("test-\(UUID().uuidString).sqlite"))
container.persistentStoreDescriptions = [store]
container.loadPersistentStores { _, error in if let error { fatalError(error.localizedDescription) } }
CoreDataStack.shared.persistentContainer = container
let context = container.newBackgroundContext()

let created: (Book, BookSource) = try context.performAndWait {
    let source = BookSource.create(in: context)
    source.bookSourceUrl = base
    source.bookSourceName = "本机测试书源"
    source.searchUrl = base + "/search?q={{key}}"
    source.setSearchRule(BookSource.SearchRule(bookList: "$.books", name: "$.titles[{$.idx}]", author: "$.author", bookUrl: "$.url"))
    source.setBookInfoRule(BookSource.BookInfoRule(name: "$.name", author: "$.author", tocUrl: "$.toc"))
    source.setTocRule(TocRule(bookList: "$.chapters", chapterName: "$.name", chapterUrl: "$.url"))
    source.setContentRule(BookSource.ContentRule(content: "$.content"))
    let book = Book.create(in: context)
    book.name = "测试书籍"
    book.author = "测试作者"
    book.bookUrl = base + "/oldbook"
    book.tocUrl = base + "/oldtoc"
    book.origin = "old-source"
    book.originName = "旧书源"
    book.totalChapterNum = 2
    book.durChapterIndex = 1
    for index in 0..<2 {
        let chapter = BookChapter.create(in: context, bookId: book.bookId, url: "/old/\(index)", index: Int32(index), title: "旧\(index)")
        chapter.book = book
    }
    try context.save()
    return (book, source)
}
let (book, source) = created
let snapshot = try BookSourceSnapshot.capture(source)
let results = try await WebBook.searchBook(source: snapshot, key: "测试")
check(results.count == 1 && results[0].name == "测试书籍", "HTTP search executes nested JSONPath with the real source model")
check(results[0].bookUrl == base + "/book", "HTTP search resolves a relative book URL")
let original = try BookRequestSnapshot.capture(book)
var candidate = original
candidate.origin = base
candidate.bookUrl = base + "/book"
candidate.tocUrl = candidate.bookUrl
candidate.tocHtml = nil
candidate = try await WebBook.getBookInfo(source: snapshot, book: candidate)
check(candidate.tocUrl == base + "/toc", "detail fetch parses the new directory URL without mutating the book")
check(try ManagedObjectAccess.read(book) { $0.origin } == "old-source", "preparing a new source preserves the old source")
let chapters = try await WebBook.getChapterList(source: snapshot, book: candidate)
check(chapters.count == 4, "HTTP directory fetch returns complete chapters")
try await ChapterDirectoryUpdater.replace(book: book, source: source, original: original,
                                          metadata: candidate, definition: snapshot, chapters: chapters)
let replaced = try ManagedObjectAccess.read(book) { ($0.origin, $0.totalChapterNum, $0.durChapterIndex, $0.chapters?.count) }
check(replaced.0 == base && replaced.1 == 4 && replaced.2 == 2 && replaced.3 == 4,
      "source replacement commits one complete directory and maps the old reading progress")
let resolved = try BookSourceResolver.resolve(for: book)
check(resolved?.objectID == source.objectID, "reader resolves a source after its origin becomes a URL")
let chapter = try context.performAndWait { try context.fetch(BookChapter.fetchRequest()).first { $0.index == 0 }! }
let content = try await WebBook.getContent(source: snapshot, book: book, chapter: chapter)
check(content.contains("第一章测试内容"), "reading content works after switching source")

let loadedContent = try await ChapterContentLoader.load(chapter: chapter, book: book)
let savedCache = try ManagedObjectAccess.read(chapter) { ($0.isCached, $0.cachePath) }
check(loadedContent.contains("第一章测试内容") && savedCache.0 && savedCache.1 != nil,
      "normal reading saves chapter content for offline reopening")
if let path = savedCache.1 {
    check(FileManager.default.fileExists(atPath: ChapterContentLoader.cacheURL(path).path), "chapter cache exists on disk")
    try? FileManager.default.removeItem(at: ChapterContentLoader.cacheURL(path))
}
try await ManagedObjectAccess.update(book) { book in
    book.durChapterIndex = 0; book.durChapterTitle = chapters[0].title; book.durChapterPos = 3
    try book.managedObjectContext?.save()
}
try await ChapterDirectoryUpdater.replace(book: book, source: source, original: candidate,
                                          metadata: candidate, definition: snapshot, chapters: chapters)
check(try ManagedObjectAccess.read(book) { $0.durChapterPos } == 3,
      "refreshing the same source preserves the current page")

do {
    try await ChapterDirectoryUpdater.replace(book: book, source: source, original: candidate,
                                              metadata: candidate, definition: snapshot, chapters: [])
    fatalError("Empty directory accepted")
} catch { print("PASS: empty replacement directory is rejected") }
check(try ManagedObjectAccess.read(book) { $0.chapters?.count } == 4, "failed replacement keeps the old directory")
var failedRequest = candidate
failedRequest.tocUrl = base + "/failure"
do { _ = try await WebBook.getChapterList(source: snapshot, book: failedRequest); fatalError("HTTP 503 accepted") }
catch { print("PASS: HTTP 503 is rejected before parsing or changing the directory") }
check(try ManagedObjectAccess.read(book) { $0.chapters?.count } == 4, "HTTP source failure keeps the existing directory")
let cancelled = Task {
    try await Task.sleep(nanoseconds: 20_000_000)
    try await ChapterDirectoryUpdater.replace(book: book, source: source, original: candidate,
                                              metadata: candidate, definition: snapshot, chapters: chapters)
}
cancelled.cancel()
do { try await cancelled.value; fatalError("cancelled replacement committed") }
catch is CancellationError { print("PASS: cancelled source replacement cannot commit") }
check(try ManagedObjectAccess.read(book) { $0.chapters?.count } == 4, "cancelled replacement keeps the current directory")
check(ReadingProgressMapper.chapterIndex(previousIndex: -100, previousCount: 0, title: nil, newTitles: ["one"]) == 0,
      "invalid previous reading progress stays within the new directory")

let cookieManager = CookieManager(cookieStorage: URLSessionConfiguration.ephemeral.httpCookieStorage!)
DispatchQueue.concurrentPerform(iterations: 40) { index in
    cookieManager.saveCookie(url: "fixture\(index).invalid", cookieString: "value=\(index)")
    check(cookieManager.getCookie(for: "fixture\(index).invalid") == "value=\(index)", "cookie read and write use the context queue")
}
for rate in ["", "0", "/", "1/9223372036854775807", "9223372036854775807", "-1/1", "1/1/1"] {
    let limiter = ConcurrentRateLimiter(concurrentRate: rate, key: "fixture-\(rate)")
    _ = try await limiter.getConcurrentRecord()
}
print("PASS: invalid source rate settings cannot overflow time arithmetic")

let payload = try BackupStore.export(context: context)
let backedSources = payload["sources"] as! [[String: Any]]
check(backedSources.first?["ruleSearch"] != nil && backedSources.first?["ruleContent"] != nil,
      "backup includes source rules and network configuration")
let restoreContainer = NSPersistentContainer(name: "Restored", managedObjectModel: model)
restoreContainer.persistentStoreDescriptions = [NSPersistentStoreDescription(url: directory.appendingPathComponent("restored-\(UUID()).sqlite"))]
restoreContainer.loadPersistentStores { _, error in if let error { fatalError(error.localizedDescription) } }
let restored = try BackupStore.restore(payload, container: restoreContainer)
check(restored["books"] == 1 && restored["sources"] == 1 && restored["chapters"] == 4,
      "backup restores books, full source rules and chapter relationships")
let restoreContext = restoreContainer.newBackgroundContext()
try restoreContext.performAndWait {
    let restoredBook = try restoreContext.fetch(Book.fetchRequest()).first!
    check(restoredBook.source != nil && restoredBook.chapters?.count == 4,
          "restored books reconnect to their source and chapters")
    check(restoredBook.durChapterIndex == 2, "backup preserves reading progress")
}
for invalid in [["books": "bad"], ["books": [["bookUrl": "broken", "durChapterIndex": "9223372036854775807"]]], ["unrelated": []]] as [[String: Any]] {
    do { _ = try BackupStore.restore(invalid, container: restoreContainer); fatalError("invalid backup accepted") }
    catch { print("PASS: invalid backup is rejected before a database commit") }
}
check(try restoreContext.performAndWait { try restoreContext.count(for: Book.fetchRequest()) } == 1,
      "malformed or overflowing backup keeps existing books")

let migratedURL = directory.appendingPathComponent("migrated-\(UUID()).sqlite")
let prepared = CoreDataStoreMigration.prepare(legacy: store.url!, destination: migratedURL,
                                              coordinator: container.persistentStoreCoordinator)
check(prepared == migratedURL && FileManager.default.fileExists(atPath: store.url!.path),
      "store migration copies before loading and retains the original database")
let migrated = NSPersistentContainer(name: "Migrated", managedObjectModel: model)
migrated.persistentStoreDescriptions = [NSPersistentStoreDescription(url: prepared)]
migrated.loadPersistentStores { _, error in if let error { fatalError(error.localizedDescription) } }
let migratedContext = migrated.newBackgroundContext()
check(try migratedContext.performAndWait { try migratedContext.count(for: Book.fetchRequest()) } == 1,
      "migrated SQLite retains the committed books")

check(JSONNumber.int32(NSNumber(value: Int64.max)) == nil && JSONNumber.int64(NSNumber(value: UInt64.max)) == nil,
      "imported out-of-range integers are rejected without wrapping or trapping")
check(JSONNumber.int32(NSNumber(value: 0)) == 0 && JSONNumber.int32("2147483647") == Int32.max,
      "valid imported integer boundaries retain their values")
let txtFile = directory.appendingPathComponent("fixture.txt")
try "第一章 测试\n正文一\n第二章 测试\n正文二".write(to: txtFile, atomically: true, encoding: .utf8)
let automatic = try TxtFileParser.parse(file: txtFile)
let custom = try TxtFileParser.parse(file: txtFile, preferredPattern: "DOES_NOT_MATCH")
check(automatic.chapters.count != custom.chapters.count, "changing TXT directory rules invalidates the parser cache")
let txtContent = try TxtFileParser.readChapter(file: txtFile, chapterIndex: 0,
                                              metadataTag: "txt:0:0:9223372036854775807:9223372036854775807")
check(!txtContent.isEmpty, "invalid TXT ranges fall back to a valid chapter without overflowing")
let archive = ZipBuilder()
archive.addFile(name: "a.json", data: Data("{\"valid\":true}".utf8))
let archiveData = archive.build()
check(try ZipBuilder.extractZip(data: archiveData)["a.json"] == Data("{\"valid\":true}".utf8),
      "ZIP backup handles unaligned headers and verifies checksum")
for damaged in [Data(), Data(archiveData.prefix(10)), Data(archiveData.dropLast()), Data(repeating: 255, count: 40)] {
    do { _ = try ZipBuilder.extractZip(data: damaged); fatalError("damaged archive accepted") }
    catch { print("PASS: truncated ZIP reports a recoverable error") }
}
print("PASS: full domain checks ran with CoreData concurrency assertions enabled")
