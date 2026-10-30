import SwiftUI
import CoreData

@MainActor
final class DiscoveryBookWallViewModel: ObservableObject {
    typealias Operation = (BookSourceSnapshot, String, Int) async throws -> [SearchBookResult]

    @Published private(set) var results: [BookSearchResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasMore = true
    private(set) var selection: ExploreSelection?
    private(set) var currentPage = 0

    private struct CachedPage {
        let results: [BookSearchResult]
        let page: Int
        let hasMore: Bool
        let source: BookSourceSnapshot
    }
    private let context: NSManagedObjectContext
    private let operation: Operation
    private var source: BookSourceSnapshot?
    private var requestID = UUID()
    private var requestTask: Task<[SearchBookResult], Error>?
    private var cache: [String: CachedPage] = [:]
    private var cacheOrder: [String] = []

    init(context: NSManagedObjectContext = CoreDataStack.shared.newBackgroundContext(),
         operation: @escaping Operation = { try await WebBook.exploreBook(source: $0, url: $1, page: $2) }) {
        self.context = context
        self.operation = operation
    }

    func cancelLoading() {
        requestID = UUID()
        requestTask?.cancel()
        requestTask = nil
        isLoading = false
    }

    func clear() {
        cancelLoading()
        selection = nil
        source = nil
        results = []
        errorMessage = nil
        currentPage = 0
        hasMore = true
    }

    func show(_ selection: ExploreSelection) async {
        if self.selection?.cacheKey == selection.cacheKey, !results.isEmpty { return }
        cancelLoading()
        self.selection = selection
        errorMessage = nil
        if let saved = cache[selection.cacheKey] {
            results = saved.results
            source = saved.source
            currentPage = saved.page
            hasMore = saved.hasMore
            return
        }
        results = []
        source = nil
        currentPage = 0
        hasMore = true
        await reload()
    }

    func reload() async {
        guard let selection else { return }
        cancelLoading()
        let id = requestID
        isLoading = true
        errorMessage = nil
        defer { if requestID == id { isLoading = false; requestTask = nil } }
        do {
            let context = context
            let definition = try await context.perform {
                let request = BookSource.fetchRequest()
                request.fetchLimit = 1
                request.shouldRefreshRefetchedObjects = true
                request.predicate = NSPredicate(format: "sourceId == %@ AND enabled == YES AND enabledExplore == YES", selection.sourceId as CVarArg)
                guard let source = try context.fetch(request).first else { throw ExploreRuleParser.ParseError.sourceUnavailable }
                return try BookSourceSnapshot.capture(source)
            }
            try Task.checkCancellation()
            guard requestID == id else { return }
            let items = try await fetch(source: definition, selection: selection, page: 1)
            guard requestID == id, !Task.isCancelled else { return }
            source = definition
            results = convert(items, source: definition)
            currentPage = 1
            hasMore = !results.isEmpty
            rememberPage()
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            errorMessage = NetworkError.message(for: error)
        }
    }

    func loadMore() async {
        guard !isLoading, hasMore, let source, let selection else { return }
        let id = requestID
        isLoading = true
        errorMessage = nil
        defer { if requestID == id { isLoading = false; requestTask = nil } }
        do {
            let page = currentPage + 1
            let items = try await fetch(source: source, selection: selection, page: page)
            guard requestID == id, !Task.isCancelled else { return }
            let existing = Set(results.map(\.bookUrl))
            let added = convert(items, source: source).filter { !existing.contains($0.bookUrl) }
            if added.isEmpty { hasMore = false }
            else { results.append(contentsOf: added); currentPage = page }
            rememberPage()
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            errorMessage = NetworkError.message(for: error)
        }
    }

    private func fetch(source: BookSourceSnapshot, selection: ExploreSelection, page: Int) async throws -> [SearchBookResult] {
        let operation = operation
        let task = Task { try await operation(source, selection.url, page) }
        requestTask = task
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    private func convert(_ items: [SearchBookResult], source: BookSourceSnapshot) -> [BookSearchResult] {
        var seen = Set<String>()
        return items.filter { !$0.name.isEmpty && !$0.bookUrl.isEmpty && seen.insert($0.bookUrl).inserted }.map {
            BookSearchResult(name: $0.name, author: $0.author, coverUrl: $0.coverUrl, intro: $0.intro,
                             kind: $0.kind, wordCount: $0.wordCount, lastChapter: $0.lastChapter,
                             sourceName: source.bookSourceName, sourceId: source.sourceId, bookUrl: $0.bookUrl)
        }
    }

    private func rememberPage() {
        guard let selection, let source else { return }
        cache[selection.cacheKey] = CachedPage(results: results, page: currentPage, hasMore: hasMore, source: source)
        cacheOrder.removeAll { $0 == selection.cacheKey }
        cacheOrder.append(selection.cacheKey)
        if cacheOrder.count > 8 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
    }
}

struct DiscoveryBookWall: View {
    @ObservedObject var model: DiscoveryBookWallViewModel
    let selection: ExploreSelection
    let onSelect: (BookSearchResult) -> Void
    let onChangeSource: () -> Void
    let onCheckSource: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(selection.kindTitle).font(.subheadline.weight(.semibold))
                    Spacer()
                    if !model.results.isEmpty {
                        Text("\(model.results.count) 本").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { Task { await model.reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("刷新当前分类")
                        .accessibilityIdentifier("discovery.refresh")
                        .disabled(model.isLoading)
                }
                if model.results.isEmpty {
                    if model.isLoading {
                        ProgressView("正在加载书籍…").frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: model.errorMessage == nil ? "books.vertical" : "wifi.exclamationmark")
                                .font(.system(size: 36)).foregroundStyle(.secondary)
                            Text(model.errorMessage == nil ? "这个分类暂无书籍" : "这个分类暂时加载失败")
                                .font(.headline)
                            if let error = model.errorMessage {
                                Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            HStack {
                                Button("重试") { Task { await model.reload() } }.buttonStyle(.bordered)
                                Button("换个书源", action: onChangeSource).buttonStyle(.bordered)
                                Button("校验书源", action: onCheckSource).buttonStyle(.bordered)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                        .accessibilityIdentifier("discovery.emptyCategory")
                    }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(model.results) { result in
                            Button { onSelect(result) } label: { DiscoveryPoster(result: result) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("discovery.book." + result.name)
                        }
                    }
                    .accessibilityIdentifier("discovery.bookWall")
                    if let error = model.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                    if model.hasMore {
                        Button { Task { await model.loadMore() } } label: {
                            HStack {
                                if model.isLoading { ProgressView() }
                                Text(model.isLoading ? "正在加载…" : "加载更多")
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .disabled(model.isLoading)
                        .accessibilityIdentifier("discovery.loadMore")
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 24)
        }
        .refreshable { await model.reload() }
    }
}

private struct DiscoveryPoster: View {
    let result: BookSearchResult

    private var coverColor: Color {
        let colors: [Color] = [.teal, .indigo, .brown, .purple]
        let number = result.name.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % colors.count }
        return colors[number]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topLeading) {
                if let url = result.coverUrl, !url.isEmpty {
                    BookCoverView(url: url, sourceId: result.sourceId)
                } else {
                    LinearGradient(colors: [coverColor.opacity(0.8), coverColor.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.displayName).font(.system(.headline, design: .serif)).lineLimit(4)
                        Spacer(minLength: 0)
                        Text(result.displayAuthor.isEmpty ? "佚名" : result.displayAuthor)
                            .font(.caption2).lineLimit(1).opacity(0.8)
                    }
                    .foregroundColor(.white).padding(12)
                }
            }
            .aspectRatio(0.7, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.08), radius: 4, y: 3)
            .accessibilityHidden(true)
            Text(result.displayName).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
            Text(result.displayAuthor.isEmpty ? "未知作者" : result.displayAuthor)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct DiscoverySourcePicker: View {
    @ObservedObject var model: DiscoveryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedGroup = ""
    @FocusState private var searchFocused: Bool

    private func groups(for source: ExploreGroup) -> [String] {
        (source.sourceGroup ?? "").replacingOccurrences(of: "，", with: ",").components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var groups: [String] { Set(model.exploreGroups.flatMap { groups(for: $0) }).sorted() }
    private var sources: [ExploreGroup] {
        model.filteredGroups.filter { selectedGroup.isEmpty || groups(for: $0).contains(selectedGroup) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索书源或分类", text: $searchText)
                        .focused($searchFocused).submitLabel(.done)
                        .onSubmit { searchFocused = false }
                        .onChange(of: searchText) { model.filterGroups(keyword: $0) }
                        .accessibilityIdentifier("discovery.search")
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .accessibilityLabel("清空搜索")
                    }
                    if searchFocused {
                        Button("完成") { searchFocused = false }.accessibilityIdentifier("discovery.dismissKeyboard")
                    }
                }
                .padding(12).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.vertical, 10)
                if !groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            groupButton("全部", value: "")
                            ForEach(groups, id: \.self) { group in groupButton(group, value: group) }
                        }.padding(.horizontal, 16).padding(.bottom, 10)
                    }
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 10)], spacing: 10) {
                        ForEach(sources) { source in
                            Button {
                                searchFocused = false
                                model.selectSource(source.sourceId)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack(alignment: .top) {
                                        Text(source.sourceName).font(.subheadline.weight(.medium)).lineLimit(2)
                                        Spacer(minLength: 0)
                                        if model.selectedSourceID == source.sourceId { Image(systemName: "checkmark.circle.fill") }
                                    }
                                    Text(source.errorMessage != nil ? "分类加载失败" : (source.hasLoadedKinds ? "\(source.exploreKinds.count) 个分类" : "点击查看分类"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(12)
                                .background(model.selectedSourceID == source.sourceId ? Color.accentColor.opacity(0.1) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.selectedSourceID == source.sourceId ? Color.accentColor : Color(.separator).opacity(0.25), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("discovery.source." + source.sourceName)
                        }
                    }.padding(16)
                    if sources.isEmpty { Text("没有匹配的书源").foregroundStyle(.secondary).padding(24) }
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("切换书源").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("关闭") { dismiss() } } }
        }
        .onAppear { model.filterGroups(keyword: "") }
        .onDisappear { model.filterGroups(keyword: "") }
    }

    private func groupButton(_ title: String, value: String) -> some View {
        Button(title) { selectedGroup = value; searchFocused = false }
            .font(.subheadline).padding(.horizontal, 14).padding(.vertical, 7)
            .background(selectedGroup == value ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill), in: Capsule())
            .foregroundColor(selectedGroup == value ? .accentColor : .primary)
    }
}
