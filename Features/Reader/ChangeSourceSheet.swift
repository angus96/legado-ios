//
//  ChangeSourceSheet.swift
//  Legado-iOS
//
//  换源对话框 - 参考 Android ChangeBookSourceDialog
//  在阅读界面中支持一键换源，对比不同书源的最新章节
//

import SwiftUI
import CoreData

// MARK: - 换源数据模型

/// 换源搜索结果
struct ChangeSourceResult: Identifiable {
    let id = UUID()
    let source: BookSource
    let latestChapter: String
    let chapterCount: Int
    let bookUrl: String
    let tocUrl: String
    let isCurrentSource: Bool
    var isLoading: Bool = false
    var loadError: String?
}

// MARK: - 换源 ViewModel

@MainActor
class ChangeSourceViewModel: ObservableObject {
    typealias SearchOperation = (BookSourceSnapshot, String) async throws -> [SearchBookResult]
    @Published var results: [ChangeSourceResult] = []
    @Published var isSearching = false
    @Published var searchProgress: Double = 0
    @Published var errorMessage: String?
    
    private var searchTask: Task<Void, Never>?
    private var searchID = UUID()
    private let ruleEngine = RuleEngine()
    private let context: NSManagedObjectContext
    private let searchOperation: SearchOperation

    init(context: NSManagedObjectContext = CoreDataStack.shared.viewContext,
         searchOperation: @escaping SearchOperation = { try await WebBook.searchBook(source: $0, key: $1, timeout: 12) }) {
        self.context = context
        self.searchOperation = searchOperation
    }

    func removeUnavailableResults() {
        let request = BookSource.fetchRequest()
        request.predicate = NSPredicate(format: "enabled == YES")
        let available = Set(((try? context.fetch(request)) ?? []).map(\.sourceId))
        results.removeAll { $0.source.isDeleted || $0.source.managedObjectContext == nil || !available.contains($0.source.sourceId) }
    }

    func useResults(_ candidates: [BookSearchSource], for book: Book) {
        cancelSearch()
        let context = book.managedObjectContext ?? CoreDataStack.shared.viewContext
        results = candidates.compactMap { candidate in
            let request = BookSource.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "sourceId == %@ AND enabled == YES", candidate.sourceId as CVarArg)
            guard let source = try? context.fetch(request).first else { return nil }
            return ChangeSourceResult(source: source, latestChapter: candidate.lastChapter ?? "未知", chapterCount: 0,
                                      bookUrl: candidate.bookUrl, tocUrl: "",
                                      isCurrentSource: source.sourceId == book.source?.sourceId || source.bookSourceUrl == book.origin)
        }
        errorMessage = results.isEmpty ? "本次搜索尚未找到其他书源，可点击重新搜索" : nil
        searchProgress = 1
        sortResults()
    }

    func recordFailure(_ result: ChangeSourceResult, error: Error) {
        guard let index = results.firstIndex(where: { $0.id == result.id }) else { return }
        results[index].loadError = NetworkError.message(for: error)
    }
    
    /// 搜索可用书源
    func searchSources(for book: Book) async {
        cancelSearch()
        let requestID = UUID()
        searchID = requestID
        let task = Task {
            guard self.searchID == requestID, !Task.isCancelled else { return }
            await performSearch(for: book, requestID: requestID)
        }
        searchTask = task
        await task.value
        if searchID == requestID { searchTask = nil }
    }

    private func performSearch(for book: Book, requestID: UUID) async {
        isSearching = true
        searchProgress = 0
        results = []
        errorMessage = nil
        
        let context = context
        
        // 获取所有启用的书源
        let request: NSFetchRequest<BookSource> = BookSource.fetchRequest()
        request.predicate = NSPredicate(format: "enabled == YES AND searchUrl != nil AND searchUrl != ''")
        request.sortDescriptors = [NSSortDescriptor(key: "weight", ascending: false)]
        
        guard let sources = try? context.fetch(request), !sources.isEmpty else {
            errorMessage = "没有可用的书源"
            isSearching = false
            return
        }
        
        let totalSources = sources.count
        let bookName = book.name
        let bookAuthor = book.author
        let currentOrigin = book.origin
        let currentSourceID = book.source?.sourceId ?? UUID(uuidString: book.origin)
        let searchInputs = sources.compactMap { source -> (BookSource, BookSourceSnapshot)? in
            guard let definition = try? BookSourceSnapshot.capture(source) else { return nil }
            return (source, definition)
        }
        var completedCount = 0
        let operation = searchOperation
        
        // 搜索与换源共用实际的并发限制。
        await ConcurrentSourceSearch.run(searchInputs, limit: 12) { item -> ChangeSourceResult? in
            let (source, definition) = item
            do {
                let searchResults = try await ConcurrentSourceSearch.withTimeout(seconds: 12) {
                    try await operation(definition, bookName)
                }
                let matched = searchResults.first { searchBook in
                    searchBook.name == bookName &&
                    (bookAuthor.isEmpty || searchBook.author == bookAuthor)
                }
                guard let matched else { return nil }
                return ChangeSourceResult(
                    source: source,
                    latestChapter: matched.lastChapter ?? "未知",
                    chapterCount: 0,
                    bookUrl: matched.bookUrl,
                    tocUrl: "",
                    isCurrentSource: definition.sourceId == currentSourceID || definition.bookSourceUrl == currentOrigin
                )
            } catch is CancellationError {
                return nil
            } catch {
                print("换源搜索失败[\(definition.bookSourceName)]: \(error.localizedDescription)")
                return nil
            }
        } onResult: { result in
            guard !Task.isCancelled, self.searchID == requestID else { return }
            if let result {
                self.results.append(result)
                self.sortResults()
            }
            completedCount += 1
            self.searchProgress = Double(completedCount) / Double(totalSources)
        }

        guard !Task.isCancelled, searchID == requestID else { return }
        
        isSearching = false
        
        if results.isEmpty {
            errorMessage = "未找到其他可用书源"
        }
    }
    
    /// 执行换源
    func changeSource(
        result: ChangeSourceResult,
        for book: Book
    ) async throws {
        let original = try BookRequestSnapshot.capture(book)
        let definition = try BookSourceSnapshot.capture(result.source)
        var candidate = original
        candidate.origin = definition.bookSourceUrl
        candidate.bookUrl = result.bookUrl
        candidate.tocUrl = result.tocUrl.isEmpty ? result.bookUrl : result.tocUrl
        candidate.tocHtml = nil
        if definition.getBookInfoRule() != nil {
            candidate = try await WebBook.getBookInfo(source: definition, book: candidate)
        }
        let webChapters = try await WebBook.getChapterList(source: definition, book: candidate)
        guard !webChapters.isEmpty else { throw WebBookError.noRule("新书源未返回目录，已保留原书源") }
        try Task.checkCancellation()
        candidate.latestChapterTitle = candidate.latestChapterTitle ?? result.latestChapter
        try await ChapterDirectoryUpdater.replace(book: book, source: result.source, original: original,
                                                   metadata: candidate, definition: definition, chapters: webChapters)
    }

    /// 取消搜索
    func cancelSearch() {
        searchID = UUID()
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
    
    /// 排序结果（当前源置顶，其余按章节数降序）
    private func sortResults() {
        results.sort { a, b in
            if a.isCurrentSource != b.isCurrentSource { return a.isCurrentSource }
            return a.chapterCount > b.chapterCount
        }
    }
}

// MARK: - 换源 Sheet 视图

struct ChangeSourceSheet: View {
    @StateObject private var viewModel = ChangeSourceViewModel()
    @Binding var isPresented: Bool
    let book: Book
    let initialSources: [BookSearchSource]?
    let onSourceChanged: () -> Void
    @State private var changeTask: Task<Void, Never>?
    @State private var changeError: String?
    @State private var failedSource: BookSource?
    @State private var showingSourceCheck = false

    init(isPresented: Binding<Bool>, book: Book, initialSources: [BookSearchSource]? = nil,
         onSourceChanged: @escaping () -> Void) {
        _isPresented = isPresented
        self.book = book
        self.initialSources = initialSources
        self.onSourceChanged = onSourceChanged
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索进度
                if viewModel.isSearching {
                    VStack(spacing: 8) {
                        ProgressView(value: viewModel.searchProgress)
                            .accentColor(.blue)
                        
                        Text("正在搜索可用书源... (\(Int(viewModel.searchProgress * 100))%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
                
                // 结果列表
                if viewModel.results.isEmpty && !viewModel.isSearching {
                    emptyStateView
                } else {
                    resultListView
                }
            }
            .navigationTitle("换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        viewModel.cancelSearch()
                        changeTask?.cancel()
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isSearching {
                        Button("停止") {
                            viewModel.cancelSearch()
                            viewModel.isSearching = false
                        }
                    } else {
                        Button("重新搜索") {
                            Task { await viewModel.searchSources(for: book) }
                        }
                    }
                }
            }
            .task {
                if let initialSources {
                    viewModel.useResults(initialSources, for: book)
                } else {
                    await viewModel.searchSources(for: book)
                }
            }
            .onDisappear {
                viewModel.cancelSearch()
                changeTask?.cancel()
            }
            .alert("换源失败", isPresented: Binding(
                get: { changeError != nil }, set: { if !$0 { changeError = nil } }
            )) {
                Button("校验这个书源") { showingSourceCheck = true }
                Button("确定", role: .cancel) { changeError = nil }
            } message: { Text(changeError ?? "") }
            .sheet(isPresented: $showingSourceCheck, onDismiss: { viewModel.removeUnavailableResults() }) {
                if let source = failedSource {
                    SourceDiagnosticView(source: source, bookName: book.name, failingBookURL: book.bookUrl)
                }
            }
        }
    }
    
    // MARK: - 空状态
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text(viewModel.errorMessage ?? "暂无结果")
                .foregroundColor(.secondary)
            
            Button("重新搜索") {
                Task { await viewModel.searchSources(for: book) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 结果列表
    
    private var resultListView: some View {
        List {
            ForEach(viewModel.results) { result in
                SourceResultRow(result: result) {
                    guard changeTask == nil else { return }
                    changeTask = Task {
                        defer { changeTask = nil }
                        do {
                            try await viewModel.changeSource(
                                result: result,
                                for: book
                            )
                            guard !Task.isCancelled else { return }
                            viewModel.cancelSearch()
                            onSourceChanged()
                            isPresented = false
                        } catch is CancellationError {
                            return
                        } catch {
                            viewModel.recordFailure(result, error: error)
                            failedSource = result.source
                            changeError = error.localizedDescription
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .disabled(changeTask != nil)
    }
}

// MARK: - 书源结果行

struct SourceResultRow: View {
    let result: ChangeSourceResult
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // 书源图标
                VStack {
                    Image(systemName: result.isCurrentSource ? "checkmark.circle.fill" : "doc.text")
                        .font(.title2)
                        .foregroundColor(result.isCurrentSource ? .green : .blue)
                }
                .frame(width: 40)
                
                // 书源信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(result.source.bookSourceName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if result.isCurrentSource {
                            Text("当前")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("最新: \(result.latestChapter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if result.chapterCount > 0 {
                        Text("共 \(result.chapterCount) 章")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let error = result.loadError {
                        Text(error).font(.caption).foregroundColor(.red).lineLimit(2)
                    }
                }
                
                Spacer()
                
                // 选择箭头
                if !result.isCurrentSource {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("changeSource.result." + result.source.bookSourceName)
        .disabled(result.isCurrentSource)
    }
}
