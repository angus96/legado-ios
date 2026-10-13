import CoreData

enum CoreDataStoreMigration {
    /// 只在加载数据库前复制旧库，SQLite 的 WAL 由 CoreData 一并处理。
    static func prepare(legacy: URL, destination: URL, coordinator: NSPersistentStoreCoordinator) -> URL {
        guard legacy != destination,
              FileManager.default.fileExists(atPath: legacy.path),
              !FileManager.default.fileExists(atPath: destination.path) else { return destination }
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try coordinator.replacePersistentStore(at: destination, destinationOptions: nil,
                                                   withPersistentStoreFrom: legacy, sourceOptions: nil,
                                                   ofType: NSSQLiteStoreType)
            return destination
        } catch {
            // 失败后继续使用原库，不能在新位置创建空库掩盖迁移失败。
            try? coordinator.destroyPersistentStore(at: destination, ofType: NSSQLiteStoreType, options: nil)
            DebugLogger.shared.log("数据库目录迁移失败，继续使用原数据库：\(error.localizedDescription)")
            return legacy
        }
    }
}
