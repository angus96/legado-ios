import CoreData

final class CoreDataStack {
    static let shared = CoreDataStack()
    
    private static let modelName = "Legado"
    
    /// App Group ID，用于 Share Extension 共享数据
    static let appGroupIdentifier = "group.com.legado.app"
    
    private(set) var loadError: Error?
    private(set) var isLoaded = false
    
lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: Self.modelName)
        
        // 使用 App Group 共享目录存储 CoreData
        let legacyURL = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("\(Self.modelName).sqlite")
        let storeURL: URL
        #if DEBUG
        if ProcessInfo.processInfo.environment["LEGADO_UI_TESTS"] == "1" { storeURL = Self.storeURL }
        else { storeURL = CoreDataStoreMigration.prepare(legacy: legacyURL, destination: Self.storeURL,
                                                        coordinator: container.persistentStoreCoordinator) }
        #else
        storeURL = CoreDataStoreMigration.prepare(legacy: legacyURL, destination: Self.storeURL,
                                                 coordinator: container.persistentStoreCoordinator)
        #endif
        let description = NSPersistentStoreDescription(url: storeURL)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { description, error in
            if let error = error {
                self.loadError = error
                self.isLoaded = false
                DebugLogger.shared.log("CoreData 加载失败: \(error)")
                return
            }
            
            self.isLoaded = true
            DebugLogger.shared.log("CoreData 加载成功: \(description.url?.path ?? "nil")")
            
            container.viewContext.automaticallyMergesChangesFromParent = true
            container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            
            let stores = container.persistentStoreCoordinator.persistentStores
            DebugLogger.shared.log("Stores 数量: \(stores.count)")
            
            for store in stores {
                DebugLogger.shared.log("Store: \(store.url?.path ?? "nil"), readOnly=\(store.isReadOnly)")
            }
            
        }
        
        return container
    }()
    
    /// 计算 CoreData store 的存储位置
    /// 优先使用 App Group 共享目录，不可用时降级到私有目录
    static var storeURL: URL {
        #if DEBUG
        if ProcessInfo.processInfo.environment["LEGADO_UI_TESTS"] == "1" {
            return FileManager.default.temporaryDirectory.appendingPathComponent("UITest-\(UUID()).sqlite")
        }
        #endif
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return groupURL.appendingPathComponent("\(modelName).sqlite")
        }
        // 降级：App Group 不可用时使用默认私有目录
        let documentsURL = NSPersistentContainer.defaultDirectoryURL()
        return documentsURL.appendingPathComponent("\(modelName).sqlite")
    }
    
    var storeCount: Int {
        persistentContainer.persistentStoreCoordinator.persistentStores.count
    }
    
    var currentStoreURL: URL? {
        persistentContainer.persistentStoreCoordinator.persistentStores.first?.url
    }
    
    var debugInfo: String {
        let stores = persistentContainer.persistentStoreCoordinator.persistentStores
        if isLoaded {
            if stores.isEmpty {
                return "⚠️ 加载成功但store为空"
            }
            let url = stores.first?.url
            let path = url?.path ?? "nil"
            let parts = path.split(separator: "/")
            let tail = parts.suffix(3).joined(separator: "/")
            let readOnly = stores.first?.isReadOnly ?? true
            return readOnly ? "⚠️ 只读: .../\(tail)" : "✅ 可写: .../\(tail)"
        } else if let error = loadError {
            return "❌ 失败: \(error.localizedDescription)"
        } else {
            return "⏳ 未初始化"
        }
    }
    
    var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }
    
func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    func save(context: NSManagedObjectContext? = nil) throws {
        let ctx = context ?? viewContext
        try ctx.performAndWait {
            guard ctx.hasChanges else { return }
            try ctx.save()
        }
    }
    
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            persistentContainer.performBackgroundTask { context in
                do {
                    let result = try block(context)
                    try context.save()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
