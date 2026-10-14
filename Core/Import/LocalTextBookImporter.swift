import Foundation
import CoreData
import CryptoKit

extension Notification.Name {
    static let localBookImported = Notification.Name("localBookImported")
}

enum LocalTextBookImportError: LocalizedError {
    case unsupportedFile
    case emptyFile
    case tooManyChapters
    case missingBook

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return "请选择 TXT 文本文件"
        case .emptyFile: return "这个 TXT 文件没有可阅读的正文"
        case .tooManyChapters: return "文件的章节数量过多，无法导入"
        case .missingBook: return "导入后的书籍无法读取，请重试"
        }
    }
}

/// 文件复制、解析和数据库提交共用一个后台队列，重复分享不会插入两本书。
@MainActor
final class LocalTextBookImporter {
    static let shared = LocalTextBookImporter(container: CoreDataStack.shared.persistentContainer)

    private let container: NSPersistentContainer
    private let importContext: NSManagedObjectContext
    private let libraryDirectory: URL

    init(container: NSPersistentContainer, libraryDirectory: URL? = nil,
         importContext: NSManagedObjectContext? = nil) {
        self.container = container
        self.importContext = importContext ?? container.newBackgroundContext()
        self.libraryDirectory = libraryDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalBooks", isDirectory: true)
    }

    func importBook(url: URL) async throws -> Book {
        guard url.isFileURL, url.pathExtension.lowercased() == "txt" else {
            throw LocalTextBookImportError.unsupportedFile
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let context = importContext
        let directory = libraryDirectory
        let objectID = try await context.perform {
            var stored: LocalTextBookFile.StoredFile?
            do {
                let file = try LocalTextBookFile.copy(url, into: directory)
                stored = file
                let request = Book.fetchRequest()
                request.predicate = NSPredicate(format: "origin == 'local' AND (bookUrl == %@ OR bookUrl ENDSWITH %@)",
                                                file.url.path, "/LocalBooks/" + file.url.lastPathComponent)
                request.fetchLimit = 1
                if let existing = try context.fetch(request).first {
                    // 同一份文件只更新本机存放路径，保留阅读位置和书籍设置。
                    if existing.bookUrl != file.url.path {
                        existing.bookUrl = file.url.path
                        for case let chapter as BookChapter in existing.chapters ?? NSSet() {
                            chapter.cachePath = file.url.path
                        }
                        try context.save()
                    }
                    return existing.objectID
                }

                let parsed = try TxtFileParser.parse(file: file.url)
                guard !parsed.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LocalTextBookImportError.emptyFile
                }
                guard parsed.chapters.count <= Int(Int32.max) else { throw LocalTextBookImportError.tooManyChapters }
                let book = Book.create(in: context)
                book.name = url.deletingPathExtension().lastPathComponent
                book.author = "未知作者"
                book.type = 0
                book.origin = "local"
                book.originName = url.lastPathComponent
                book.bookUrl = file.url.path
                book.tocUrl = parsed.tocPattern ?? ""
                book.canUpdate = false
                book.charset = parsed.encodingName
                book.intro = parsed.intro
                book.wordCount = String(parsed.wordCount)
                book.totalChapterNum = Int32(parsed.chapters.count)
                book.durChapterIndex = 0
                book.durChapterTitle = parsed.chapters.first?.title
                for item in parsed.chapters {
                    let chapter = BookChapter.create(in: context, bookId: book.bookId, url: "local:\(item.index)",
                                                     index: Int32(item.index), title: item.title)
                    chapter.book = book
                    chapter.wordCount = Int32(min(item.wordCount, Int(Int32.max)))
                    chapter.isCached = true
                    chapter.cachePath = file.url.path
                    chapter.tag = item.metadataTag
                }
                try context.save()
                return book.objectID
            } catch {
                context.rollback()
                if let stored, stored.created { try? FileManager.default.removeItem(at: stored.url) }
                throw error
            }
        }

        guard let book = try container.viewContext.existingObject(with: objectID) as? Book else {
            throw LocalTextBookImportError.missingBook
        }
        NotificationCenter.default.post(name: .localBookImported, object: book.bookId)
        return book
    }
}

private enum LocalTextBookFile {
    struct StoredFile {
        let url: URL
        let created: Bool
    }

    static func copy(_ source: URL, into directory: URL) throws -> StoredFile {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        defer { try? manager.removeItem(at: temporary) }
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readable in
            do {
                guard try readable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw LocalTextBookImportError.unsupportedFile
                }
                try manager.copyItem(at: readable, to: temporary)
            } catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }

        let handle = try FileHandle(forReadingFrom: temporary)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty { digest.update(data: data) }
        let identifier = digest.finalize().map { String(format: "%02x", $0) }.joined()
        let destination = directory.appendingPathComponent(identifier + ".txt")
        if manager.fileExists(atPath: destination.path) { return StoredFile(url: destination, created: false) }
        try manager.moveItem(at: temporary, to: destination)
        return StoredFile(url: destination, created: true)
    }
}
