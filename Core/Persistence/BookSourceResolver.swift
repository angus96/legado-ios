import CoreData

enum BookSourceResolver {
    static func resolve(for book: Book) throws -> BookSource? {
        try ManagedObjectAccess.read(book) { book in
            if let source = book.source, !source.isDeleted { return source }
            guard let context = book.managedObjectContext else { return nil }
            let request: NSFetchRequest<BookSource> = BookSource.fetchRequest()
            request.fetchLimit = 1
            if let sourceID = UUID(uuidString: book.origin) {
                request.predicate = NSPredicate(format: "sourceId == %@", sourceID as CVarArg)
            } else {
                request.predicate = NSPredicate(format: "bookSourceUrl == %@", book.origin)
            }
            return try context.fetch(request).first
        }
    }
}
