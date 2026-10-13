import Foundation
import CoreData
import Combine

@MainActor
final class BookshelfViewModel: ObservableObject {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
    }
    @Published var books: [Book] = []
    @Published var groups: [BookGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingAddUrl = false
    
    @Published var viewMode: ViewMode = .grid
    @Published var sortMode: SortMode = .readTime
    @Published var groupStyle: GroupStyle = .tabs // 分组样式：分组Tab vs 统一列表
    @Published var gridColumns: Int = 4 // 网格列数（3-6），安卓原版默认4列
    @Published var showUnread = true
    @Published var showUpdateTime = true
    @Published var showFastScroller = false
    
    var totalBookCount: Int { books.count }
    
    private let pageSize = 50
    private var currentPage = 0
    
    // 参考 Android BookshelfFragment1（分组Tab）和 BookshelfFragment2（统一列表）
    enum GroupStyle: Int, CaseIterable {
        case tabs = 0      // Fragment1: ViewPager + TabLayout，每个分组一个Tab
        case unified = 1   // Fragment2: 统一列表，分组作为分隔标题
    }
    
    enum ViewMode: Int, CaseIterable {
        case grid = 0
        case list = 1
    }
    
    enum SortMode: Int, CaseIterable {
        case readTime = 0
        case updateTime = 1
        case name = 2
        case author = 3
    }
    
    private var loadTask: Task<Void, Never>?
    
    deinit {
        loadTask?.cancel()
    }
    
    func loadBooks() async {
        guard !isLoading else { return }
        isLoading = true
        
        do {
            books = try await fetchBooks()
            groups = try await fetchGroups()
        } catch {
            errorMessage = "加载失败：\(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func refreshBooks() async {
        await loadBooks()
    }
    
    private func fetchBooks() async throws -> [Book] {
        let context = self.context
        let sortMode = self.sortMode
        
        return try await context.perform {
            let request: NSFetchRequest<Book> = Book.fetchRequest()
            request.returnsObjectsAsFaults = false
            
            switch sortMode {
            case .readTime:
                request.sortDescriptors = [NSSortDescriptor(key: "durChapterTime", ascending: false)]
            case .updateTime:
                request.sortDescriptors = [NSSortDescriptor(key: "lastCheckTime", ascending: false)]
            case .name:
                request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            case .author:
                request.sortDescriptors = [NSSortDescriptor(key: "author", ascending: true)]
            }
            
            request.sortDescriptors?.insert(NSSortDescriptor(key: "order", ascending: true), at: 0)
            return try context.fetch(request)
        }
    }
    
    private func fetchGroups() async throws -> [BookGroup] {
        let context = self.context
        
        return try await context.perform {
            let request: NSFetchRequest<BookGroup> = BookGroup.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
            request.predicate = NSPredicate(format: "show == YES")
            return try context.fetch(request)
        }
    }
    
    func removeBook(_ book: Book) {
        let objectID = book.objectID
        // 在删除 managed object 前移除 UI 引用，重复点击不会读取已经清空的 bookId。
        books.removeAll { $0.objectID == objectID || $0.isDeleted || $0.managedObjectContext == nil }
        guard !book.isDeleted, book.managedObjectContext === context else { return }
        context.delete(book)
        do {
            try context.save()
        } catch {
            context.rollback()
            errorMessage = "删除失败：\(error.localizedDescription)"
            Task { await loadBooks() }
        }
    }
    
    func toggleTop(_ book: Book) {
        guard !book.isDeleted, book.managedObjectContext === context else { return }
        book.order = book.order < 0 ? 0 : -1
        do { try context.save(); Task { await loadBooks() } }
        catch { context.rollback(); errorMessage = "置顶失败：\(error.localizedDescription)" }
    }

    func updateBook(_ book: Book) {
        guard !book.isDeleted, book.managedObjectContext === context else { return }
        Task {
            do { try await refreshDirectory(book); await loadBooks() }
            catch { errorMessage = "目录更新失败：\(error.localizedDescription)" }
        }
    }

    private func refreshDirectory(_ book: Book) async throws {
        guard !book.isDeleted, book.managedObjectContext === context else { throw CancellationError() }
        guard !book.isLocal else { return }
        guard let source = try BookSourceResolver.resolve(for: book) else { throw ReaderError.noSource }
        let original = try BookRequestSnapshot.capture(book)
        let definition = try BookSourceSnapshot.capture(source)
        let metadata = try await WebBook.getBookInfo(source: definition, book: original)
        let chapters = try await WebBook.getChapterList(source: definition, book: metadata)
        try await ChapterDirectoryUpdater.replace(book: book, source: source, original: original,
                                                  metadata: metadata, definition: definition, chapters: chapters)
        guard !book.isDeleted else { return }
        book.lastCheckTime = Int64(Date().timeIntervalSince1970 * 1000)
        try context.save()
    }

    func updateAllToc() {
        Task {
            var failures = 0
            for book in books where !book.isDeleted && book.managedObjectContext === context {
                do { try await refreshDirectory(book) }
                catch { failures += 1 }
            }
            await loadBooks()
            if failures > 0 { errorMessage = "\(failures) 本书的目录更新失败，已保留原目录。" }
        }
    }

    func addBookByUrl(_ url: String) {
        guard !url.isEmpty else { return }
        Task { @MainActor in
            let context = CoreDataStack.shared.viewContext
            
            let bookData = BookImportData(
                name: URL(string: url)?.lastPathComponent ?? "未知书籍",
                author: "",
                bookUrl: url,
                tocUrl: "",
                origin: "url",
                originName: "URL导入"
            )
            
            do {
                _ = try BookDeduplicator.importBook(bookData, context: context)
                try context.save()
                await loadBooks()
            } catch {
                errorMessage = "添加失败：\(error.localizedDescription)"
            }
        }
    }

    func pruneUnavailableBooks() {
        let remaining = books.filter { !$0.isDeleted && $0.managedObjectContext != nil }
        if remaining.count != books.count { books = remaining }
    }
}
