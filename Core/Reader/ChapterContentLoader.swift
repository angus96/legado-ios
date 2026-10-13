import Foundation

enum ChapterContentLoader {
    static func load(chapter: BookChapter, book: Book) async throws -> String {
        try Task.checkCancellation()
        let chapterData = try ManagedObjectAccess.read(chapter) { ($0.isCached, $0.cachePath, Int($0.index), $0.tag) }
        let bookData = try ManagedObjectAccess.read(book) { ($0.isLocal, $0.isLocalEPUB, $0.localFileURL, $0.folderName) }
        if bookData.1, let directory = bookData.3, let path = chapterData.1 {
            let root = URL(fileURLWithPath: directory)
            let html = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            return HTMLToTextConverter.convert(html: html, baseURL: root)
        }
        if bookData.0 {
            guard let file = bookData.2 else { throw TxtFileParserError.fileNotFound }
            return try TxtFileParser.readChapter(file: file, chapterIndex: chapterData.2, metadataTag: chapterData.3)
        }
        if chapterData.0, let path = chapterData.1,
           let content = try? String(contentsOf: cacheURL(path), encoding: .utf8) { return content }
        guard let source = try BookSourceResolver.resolve(for: book) else { throw ManagedObjectAccessError.unavailable }
        return try await WebBook.getContent(source: source, book: book, chapter: chapter)
    }

    static func cache(chapter: BookChapter, book: Book) async throws {
        let original = try BookRequestSnapshot.capture(book)
        let details = try ManagedObjectAccess.read(chapter) { ($0.chapterId, $0.chapterUrl) }
        let content = try await load(chapter: chapter, book: book)
        try Task.checkCancellation()
        let fileName = "\(details.0.uuidString).txt"
        let file = cacheURL(fileName)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await ManagedObjectAccess.update(chapter) { chapter in
            guard let currentBook = chapter.book, currentBook.origin == original.origin,
                  currentBook.bookUrl == original.bookUrl, chapter.chapterUrl == details.1 else { throw CancellationError() }
            try content.write(to: file, atomically: true, encoding: .utf8)
            chapter.isCached = true
            chapter.cachePath = fileName
            try chapter.managedObjectContext?.save()
        }
    }

    static func cacheURL(_ path: String) -> URL {
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chapters", isDirectory: true).appendingPathComponent(path)
    }
}
