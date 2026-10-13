import Foundation

struct BookRequestSnapshot {
    var origin: String
    var bookUrl: String
    var tocUrl: String
    var name: String
    var author: String
    var kind: String?
    var intro: String?
    var coverUrl: String?
    var latestChapterTitle: String?
    var wordCount: String?
    var tocHtml: String?
    var downloadUrls: String?

    static func capture(_ book: Book) throws -> BookRequestSnapshot {
        try ManagedObjectAccess.read(book) {
            BookRequestSnapshot(origin: $0.origin, bookUrl: $0.bookUrl, tocUrl: $0.tocUrl,
                                name: $0.name, author: $0.author, kind: $0.kind, intro: $0.intro,
                                coverUrl: $0.coverUrl, latestChapterTitle: $0.latestChapterTitle,
                                wordCount: $0.wordCount, tocHtml: $0.tocHtml, downloadUrls: $0.downloadUrls)
        }
    }

    func applyInfo(to book: Book) async throws {
        try await ManagedObjectAccess.update(book) { book in
            guard book.bookUrl == self.bookUrl, book.origin == self.origin else { throw CancellationError() }
            book.name = self.name
            book.author = self.author
            book.kind = self.kind
            book.intro = self.intro
            book.coverUrl = self.coverUrl
            book.tocUrl = self.tocUrl
            book.tocHtml = self.tocHtml
            book.latestChapterTitle = self.latestChapterTitle
            book.wordCount = self.wordCount
            book.downloadUrls = self.downloadUrls
        }
    }
}
