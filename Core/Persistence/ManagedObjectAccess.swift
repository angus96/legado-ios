import CoreData

enum ManagedObjectAccessError: LocalizedError {
    case unavailable

    var errorDescription: String? { "书籍或书源已不可用，请重新打开。" }
}

enum ManagedObjectAccess {
    /// Return plain values while accessing every managed attribute on its own context queue.
    static func read<Object: NSManagedObject, Value>(
        _ object: Object, _ operation: (Object) throws -> Value
    ) throws -> Value {
        guard let context = object.managedObjectContext else { throw ManagedObjectAccessError.unavailable }
        return try context.performAndWait {
            guard !object.isDeleted else { throw ManagedObjectAccessError.unavailable }
            return try operation(object)
        }
    }

    static func update<Object: NSManagedObject>(
        _ object: Object, _ operation: @escaping (Object) throws -> Void
    ) async throws {
        guard let context = object.managedObjectContext else { throw ManagedObjectAccessError.unavailable }
        try await context.perform {
            guard !object.isDeleted else { throw ManagedObjectAccessError.unavailable }
            try operation(object)
        }
    }
}
