import Foundation
import CoreData
import BackgroundTasks

@MainActor
final class BackgroundCacheService {
    static let shared = BackgroundCacheService()
    private let taskIdentifier = "com.chrn11.legado.cachebook"
    private let pendingBookKey = "backgroundCache.bookId"

    private init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let processing = task as? BGProcessingTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in self.handleBackgroundTask(processing) }
        }
    }

    func scheduleCacheTask(for book: Book) {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            UserDefaults.standard.set(book.bookId.uuidString, forKey: pendingBookKey)
        } catch { DebugLogger.shared.log("调度后台缓存失败：\(error.localizedDescription)") }
    }

    private func handleBackgroundTask(_ task: BGProcessingTask) {
        let work = Task { @MainActor in
            do {
                guard let text = UserDefaults.standard.string(forKey: pendingBookKey), let id = UUID(uuidString: text) else {
                    task.setTaskCompleted(success: false); return
                }
                let request = Book.fetchRequest()
                request.predicate = NSPredicate(format: "bookId == %@", id as CVarArg)
                guard let book = try CoreDataStack.shared.viewContext.fetch(request).first else {
                    task.setTaskCompleted(success: false); return
                }
                try await cacheBook(book) { _ in }
                UserDefaults.standard.removeObject(forKey: pendingBookKey)
                task.setTaskCompleted(success: true)
            } catch { task.setTaskCompleted(success: false) }
        }
        task.expirationHandler = { work.cancel() }
    }

    func cacheBook(_ book: Book, progress: @escaping (Double) -> Void) async throws {
        let chapters = (book.chapters as? Set<BookChapter> ?? []).sorted { $0.index < $1.index }
        let start = min(max(0, Int(book.durChapterIndex)), chapters.count)
        guard start < chapters.count else { progress(1); return }
        let total = chapters.count - start
        for (completed, chapter) in chapters.dropFirst(start).enumerated() {
            try Task.checkCancellation()
            if !chapter.isCached { try await ChapterContentLoader.cache(chapter: chapter, book: book) }
            progress(Double(completed + 1) / Double(total))
        }
    }

    func cacheBookForeground(_ book: Book, progress: @escaping (Double) -> Void, completion: @escaping () -> Void) {
        Task { @MainActor in
            defer { completion() }
            do { try await cacheBook(book, progress: progress) }
            catch { DebugLogger.shared.log("缓存书籍失败：\(error.localizedDescription)") }
        }
    }
}
