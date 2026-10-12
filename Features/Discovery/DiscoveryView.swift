import SwiftUI
import CoreData
import JavaScriptCore

struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            
            if viewModel.exploreGroups.isEmpty && !viewModel.isLoading {
                emptyView
            } else {
                exploreList
            }
        }
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadExploreGroups() }
        .refreshable { await viewModel.refresh() }
        .sheet(item: $viewModel.selectedExplore) { selection in
            NavigationView {
                ExploreResultsView(selection: selection)
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索书源", text: $searchText)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _ in
                    viewModel.filterGroups(keyword: searchText)
                }
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("暂无发现内容")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("请确保已添加支持发现功能的书源")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var exploreList: some View {
        List {
            ForEach(viewModel.filteredGroups, id: \.sourceId) { group in
                ExploreGroupRow(group: group) {
                    viewModel.toggleGroup(group.sourceId)
                }
                
                if viewModel.isExpanded(group.sourceId) {
                    ExploreKindFlexBox(group: group, kinds: group.exploreKinds) { kind in
                        viewModel.openExplore(group: group, kind: kind)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8))
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
    }
}

struct ExploreGroupRow: View {
    let group: ExploreGroup
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(group.sourceName)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if group.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(group.isExpanded ? 90 : 0))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
}

struct ExploreKindFlexBox: View {
    let group: ExploreGroup
    let kinds: [ExploreKind]
    let onKindTap: (ExploreKind) -> Void
    
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(kinds, id: \.title) { kind in
                ExploreKindChip(title: kind.title) {
                    onKindTap(kind)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

struct ExploreKindChip: View {
    let title: String
    let action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + rowHeight)
        }
    }
}

struct ExploreKind: Identifiable {
    let id = UUID()
    let title: String
    let url: String
}

struct ExploreGroup: Identifiable {
    let id = UUID()
    let sourceId: UUID
    let sourceName: String
    var exploreKinds: [ExploreKind] = []
    var isLoading = false
    var isExpanded = false
}

struct ExploreSelection: Identifiable, Hashable {
    let id = UUID()
    let sourceId: UUID
    let sourceName: String
    let kindTitle: String
    let url: String
}

@MainActor
class DiscoveryViewModel: ObservableObject {
    @Published var exploreGroups: [ExploreGroup] = []
    @Published var filteredGroups: [ExploreGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedExplore: ExploreSelection?
    
    private var expandedGroups: Set<UUID> = []
    private var currentKeyword: String = ""
    
    func loadExploreGroups() async {
        isLoading = true
        
        let context = CoreDataStack.shared.viewContext
        let request = BookSource.fetchRequest()
        request.predicate = NSPredicate(format: "enabled == YES AND enabledExplore == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "bookSourceName", ascending: true)]
        
        if let sources = try? context.fetch(request) {
            var groups: [ExploreGroup] = []
            for source in sources {
                var group = ExploreGroup(sourceId: source.sourceId, sourceName: source.bookSourceName)
                
                if let exploreUrl = source.exploreUrl, !exploreUrl.isEmpty {
                    group.exploreKinds = await parseExploreUrl(exploreUrl, source: source)
                }
                groups.append(group)
            }
            exploreGroups = groups
            filteredGroups = exploreGroups
        }
        
        isLoading = false
    }
    
    func refresh() async {
        await loadExploreGroups()
    }
    
    func filterGroups(keyword: String) {
        currentKeyword = keyword
        if keyword.isEmpty {
            filteredGroups = exploreGroups
        } else {
            filteredGroups = exploreGroups.filter {
                $0.sourceName.localizedCaseInsensitiveContains(keyword) ||
                $0.exploreKinds.contains(where: { $0.title.localizedCaseInsensitiveContains(keyword) })
            }
        }
    }
    
    func toggleGroup(_ sourceId: UUID) {
        if let index = exploreGroups.firstIndex(where: { $0.sourceId == sourceId }) {
            exploreGroups[index].isExpanded.toggle()
            expandedGroups.insert(sourceId)
            filterGroups(keyword: currentKeyword)
        }
    }
    
    func isExpanded(_ sourceId: UUID) -> Bool {
        exploreGroups.first { $0.sourceId == sourceId }?.isExpanded ?? false
    }
    
    func openExplore(group: ExploreGroup, kind: ExploreKind) {
        selectedExplore = ExploreSelection(
            sourceId: group.sourceId,
            sourceName: group.sourceName,
            kindTitle: kind.title,
            url: kind.url
        )
    }
    
    private func parseExploreUrl(_ exploreUrl: String, source: BookSource) async -> [ExploreKind] {
        let resolvedRule = resolveExploreRule(exploreUrl, source: source)
        let trimmed = resolvedRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let data = trimmed.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { item in
                let title = (item["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = (item["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? title

                guard let title, !title.isEmpty, let url, !url.isEmpty else { return nil }
                return ExploreKind(title: title, url: url)
            }
        }

        if let data = trimmed.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return jsonObject.compactMap { key, value in
                if let url = value as? String {
                    let title = key.trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (title.isEmpty || resolvedURL.isEmpty) ? nil : ExploreKind(title: title, url: resolvedURL)
                }

                if let dict = value as? [String: Any] {
                    let title = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? key.trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = (dict["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !title.isEmpty, let url, !url.isEmpty else { return nil }
                    return ExploreKind(title: title, url: url)
                }

                return nil
            }
        }

        return trimmed
            .components(separatedBy: CharacterSet.newlines)
            .flatMap { $0.components(separatedBy: "&&") }
            .compactMap { item in
                let trimmedItem = item.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedItem.isEmpty else { return nil }
                let parts = trimmedItem.components(separatedBy: "::")
                if parts.count >= 2 {
                    let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    return (title.isEmpty || url.isEmpty) ? nil : ExploreKind(title: title, url: url)
                }
                return ExploreKind(title: trimmedItem, url: trimmedItem)
            }
    }

    private func resolveExploreRule(_ exploreUrl: String, source: BookSource) -> String {
        let trimmed = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("@js:") {
            return evaluateExploreJavaScript(String(trimmed.dropFirst(4)), source: source) ?? ""
        }

        if trimmed.lowercased().hasPrefix("<js>") && trimmed.lowercased().hasSuffix("</js>") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 4)
            let end = trimmed.index(trimmed.endIndex, offsetBy: -5)
            return evaluateExploreJavaScript(String(trimmed[start..<end]), source: source) ?? ""
        }

        return exploreUrl
    }

    private func evaluateExploreJavaScript(_ script: String, source: BookSource) -> String? {
        let context = ExecutionContext()
        context.source = source
        context.baseURL = URL(string: source.bookSourceUrl)

        if let variable = source.variable,
           let data = variable.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in json {
                context.jsContext.setObject(value, forKeyedSubscript: key as NSString)
            }
        }

        guard let value = context.jsContext.evaluateScript(script) else {
            return nil
        }

        if let array = value.toArray(),
           JSONSerialization.isValidJSONObject(array),
           let data = try? JSONSerialization.data(withJSONObject: array),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        if let dict = value.toDictionary(),
           JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        if let string = value.toString(), !string.isEmpty, string != "undefined", string != "null" {
            return string
        }

        return nil
    }
}

@MainActor
final class ExploreResultsViewModel: ObservableObject {
    @Published var results: [SearchViewModel.SearchResult] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasMore = true

    let selection: ExploreSelection
    private var currentPage = 1
    private var source: BookSource?

    init(selection: ExploreSelection) {
        self.selection = selection
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<BookSource> = BookSource.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "sourceId == %@", selection.sourceId as CVarArg)

        do {
            guard let source = try context.fetch(request).first else {
                errorMessage = "书源不存在"
                return
            }
            self.source = source

            let items = try await loadPage(page: 1, source: source)
            results = items
            hasMore = !items.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded() async {
        guard !isLoading, hasMore, let source else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let nextPage = currentPage + 1
            let newItems = try await loadPage(page: nextPage, source: source)
            let existingKeys = Set(results.map { "\($0.name.lowercased())|\($0.author.lowercased())|\($0.bookUrl)" })
            let filtered = newItems.filter {
                !existingKeys.contains("\($0.name.lowercased())|\($0.author.lowercased())|\($0.bookUrl)")
            }

            if filtered.isEmpty {
                hasMore = false
                return
            }

            currentPage = nextPage
            results.append(contentsOf: filtered)
        } catch {
            hasMore = false
        }
    }

    private func loadPage(page: Int, source: BookSource) async throws -> [SearchViewModel.SearchResult] {
        let items = try await WebBook.exploreBook(source: source, url: selection.url, page: page)
        return items.map {
            SearchViewModel.SearchResult(
                name: $0.name,
                author: $0.author,
                coverUrl: $0.coverUrl,
                intro: $0.intro,
                kind: $0.kind,
                lastChapter: $0.lastChapter,
                sourceName: source.bookSourceName,
                sourceId: source.sourceId,
                bookUrl: $0.bookUrl
            )
        }
    }

    func addToBookshelf(result: SearchViewModel.SearchResult) async throws -> Book {
        let context = CoreDataStack.shared.viewContext

        let bookData = BookImportData(
            name: result.name,
            author: result.author,
            bookUrl: result.bookUrl,
            tocUrl: "",
            origin: result.sourceId.uuidString,
            originName: result.sourceName,
            coverUrl: result.coverUrl,
            intro: result.intro,
            latestChapterTitle: result.lastChapter
        )

        let book = try BookDeduplicator.importBook(bookData, context: context)

        let sourceRequest: NSFetchRequest<BookSource> = BookSource.fetchRequest()
        sourceRequest.fetchLimit = 1
        sourceRequest.predicate = NSPredicate(format: "sourceId == %@", result.sourceId as CVarArg)
        if let source = try? context.fetch(sourceRequest).first {
            book.source = source
        }

        try CoreDataStack.shared.save()
        return book
    }
}

struct ExploreResultsView: View {
    let selection: ExploreSelection
    @StateObject private var viewModel: ExploreResultsViewModel
    @State private var selectedBook: Book?
    @State private var navigatingToBookDetail = false
    @State private var openingResultId: UUID?

    init(selection: ExploreSelection) {
        self.selection = selection
        _viewModel = StateObject(wrappedValue: ExploreResultsViewModel(selection: selection))
    }

    var body: some View {
        List {
            ForEach(viewModel.results) { result in
                Button(action: { selectResult(result) }) {
                    SearchItemView(result: result)
                }
                .buttonStyle(.plain)
                .disabled(openingResultId == result.id)
            }

            if viewModel.hasMore, !viewModel.results.isEmpty {
                Button(action: {
                    Task { await viewModel.loadMoreIfNeeded() }
                }) {
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text("加载更多")
                                .foregroundColor(.blue)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .navigationTitle(selection.kindTitle)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.results.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 42))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("暂无发现结果")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .task { await viewModel.load() }
        .alert("错误", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .navigationDestination(isPresented: $navigatingToBookDetail) {
            if let book = selectedBook {
                BookDetailView(book: book)
            }
        }
    }

    private func selectResult(_ result: SearchViewModel.SearchResult) {
        guard openingResultId == nil else { return }
        openingResultId = result.id
        Task {
            defer { openingResultId = nil }
            do {
                selectedBook = try await viewModel.addToBookshelf(result: result)
                navigatingToBookDetail = true
            } catch {
                viewModel.errorMessage = "加入书架失败：\(error.localizedDescription)"
            }
        }
    }
}

#Preview {
    NavigationStack {
        DiscoveryView()
    }
}
