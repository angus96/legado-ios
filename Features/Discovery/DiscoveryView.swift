import SwiftUI
import CoreData
import JavaScriptCore

struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    
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
        .onDisappear {
            searchFocused = false
            viewModel.cancelLoading()
        }
        .task { await viewModel.loadExploreGroups() }
        .refreshable { await viewModel.refresh() }
        .sheet(item: $viewModel.selectedExplore) { selection in
            NavigationStack {
                ExploreResultsView(selection: selection)
            }
        }
        .alert("加载失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索书源", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .submitLabel(.done)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("discovery.search")
                .onChange(of: searchText) { _ in
                    viewModel.filterGroups(keyword: searchText)
                }
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("清空搜索")
            }
            if searchFocused {
                Button("完成") { searchFocused = false }
                    .accessibilityIdentifier("discovery.dismissKeyboard")
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
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = false }
    }
    
    private var exploreList: some View {
        List {
            ForEach(viewModel.filteredGroups, id: \.sourceId) { group in
                ExploreGroupRow(group: group) {
                    searchFocused = false
                    viewModel.toggleGroup(group.sourceId)
                }
                
                if group.isExpanded {
                    if group.isLoading {
                        HStack {
                            ProgressView()
                            Text("正在加载分类…")
                                .foregroundColor(.secondary)
                        }
                    } else if group.exploreKinds.isEmpty {
                        HStack {
                            Text(group.errorMessage ?? "该书源暂无发现分类")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("重试") { viewModel.retryGroup(group.sourceId) }
                        }
                    } else {
                        ExploreKindFlexBox(group: group, kinds: group.exploreKinds) { kind in
                            searchFocused = false
                            viewModel.openExplore(group: group, kind: kind)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8))
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if viewModel.isLoading { ProgressView() }
        }
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
            ForEach(kinds) { kind in
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
    var id: UUID { sourceId }
    let sourceId: UUID
    let sourceName: String
    var exploreKinds: [ExploreKind] = []
    var isLoading = false
    var isExpanded = false
    var hasLoadedKinds = false
    var errorMessage: String?
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
    typealias ExploreOperation = (BookSourceSnapshot) async throws -> [ExploreKind]

    @Published var exploreGroups: [ExploreGroup] = []
    @Published var filteredGroups: [ExploreGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedExplore: ExploreSelection?
    
    private let context: NSManagedObjectContext
    private let operation: ExploreOperation
    private var groupTasks: [UUID: Task<Void, Never>] = [:]
    private var loadID = UUID()
    private var currentKeyword: String = ""

    init(context: NSManagedObjectContext = CoreDataStack.shared.newBackgroundContext(),
         operation: @escaping ExploreOperation = { try await ExploreRuleParser.parse($0) }) {
        self.context = context
        self.operation = operation
    }

    func cancelLoading() {
        loadID = UUID()
        groupTasks.values.forEach { $0.cancel() }
        groupTasks.removeAll()
        isLoading = false
        for index in exploreGroups.indices { exploreGroups[index].isLoading = false }
        filterGroups(keyword: currentKeyword)
    }
    
    func loadExploreGroups() async {
        cancelLoading()
        let requestID = loadID
        isLoading = true
        errorMessage = nil
        defer { if loadID == requestID { isLoading = false } }

        do {
            let context = context
            // 只读取列表所需的字段。发现脚本可能同步请求网络，不能在这里执行。
            let groups = try await context.perform {
                let request = NSFetchRequest<NSDictionary>(entityName: "BookSource")
                request.resultType = .dictionaryResultType
                request.propertiesToFetch = ["sourceId", "bookSourceName", "exploreUrl"]
                request.predicate = NSPredicate(format: "enabled == YES AND enabledExplore == YES")
                request.sortDescriptors = [NSSortDescriptor(key: "bookSourceName", ascending: true)]
                return try context.fetch(request).compactMap { values -> ExploreGroup? in
                    guard let id = values["sourceId"] as? UUID,
                          let name = values["bookSourceName"] as? String else { return nil }
                    var group = ExploreGroup(sourceId: id, sourceName: name)
                    let rule = values["exploreUrl"] as? String ?? ""
                    if ExploreRuleParser.javaScript(in: rule) == nil {
                        group.exploreKinds = ExploreRuleParser.parseKinds(rule)
                        group.hasLoadedKinds = true
                    }
                    return group
                }
            }
            guard loadID == requestID, !Task.isCancelled else { return }
            exploreGroups = groups
            filterGroups(keyword: currentKeyword)
        } catch {
            guard loadID == requestID, !Task.isCancelled else { return }
            errorMessage = "无法读取发现书源：\(error.localizedDescription)"
        }
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
            filterGroups(keyword: currentKeyword)
            if exploreGroups[index].isExpanded && !exploreGroups[index].hasLoadedKinds {
                loadKinds(sourceId)
            }
        }
    }

    func retryGroup(_ sourceId: UUID) {
        loadKinds(sourceId)
    }

    private func loadKinds(_ sourceId: UUID) {
        guard groupTasks[sourceId] == nil,
              let index = exploreGroups.firstIndex(where: { $0.sourceId == sourceId }) else { return }
        exploreGroups[index].isLoading = true
        exploreGroups[index].errorMessage = nil
        filterGroups(keyword: currentKeyword)

        let requestID = loadID
        let context = context
        let operation = operation
        groupTasks[sourceId] = Task { [weak self] in
            do {
                let source = try await context.perform {
                    let request = BookSource.fetchRequest()
                    request.fetchLimit = 1
                    request.shouldRefreshRefetchedObjects = true
                    request.predicate = NSPredicate(format: "sourceId == %@ AND enabled == YES AND enabledExplore == YES", sourceId as CVarArg)
                    guard let source = try context.fetch(request).first else {
                        throw ExploreRuleParser.ParseError.sourceUnavailable
                    }
                    return try BookSourceSnapshot.capture(source)
                }
                try Task.checkCancellation()
                let kinds = try await operation(source)
                guard let self, self.loadID == requestID, !Task.isCancelled,
                      let index = self.exploreGroups.firstIndex(where: { $0.sourceId == sourceId }) else { return }
                self.exploreGroups[index].exploreKinds = kinds
                self.exploreGroups[index].hasLoadedKinds = true
                self.finishLoading(sourceId, index: index)
            } catch {
                guard let self, self.loadID == requestID, !Task.isCancelled,
                      let index = self.exploreGroups.firstIndex(where: { $0.sourceId == sourceId }) else { return }
                self.exploreGroups[index].errorMessage = error.localizedDescription
                self.finishLoading(sourceId, index: index)
            }
        }
    }

    private func finishLoading(_ sourceId: UUID, index: Int) {
        exploreGroups[index].isLoading = false
        groupTasks[sourceId] = nil
        filterGroups(keyword: currentKeyword)
    }
    
    func openExplore(group: ExploreGroup, kind: ExploreKind) {
        selectedExplore = ExploreSelection(
            sourceId: group.sourceId,
            sourceName: group.sourceName,
            kindTitle: kind.title,
            url: kind.url
        )
    }
    
}

enum ExploreRuleParser {
    enum ParseError: LocalizedError {
        case sourceUnavailable
        case invalidJavaScript

        var errorDescription: String? {
            switch self {
            case .sourceUnavailable: return "书源已停用或删除"
            case .invalidJavaScript: return "发现分类脚本执行失败，请检查书源规则"
            }
        }
    }

    static func parse(_ source: BookSourceSnapshot) async throws -> [ExploreKind] {
        // 显式离开主线程；脚本里的 java.ajax 等同步调用只阻塞本次分类加载。
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let rule = source.exploreUrl ?? ""
            let resolved = try javaScript(in: rule).map { try evaluateJavaScript($0, source: source) } ?? rule
            try Task.checkCancellation()
            return parseKinds(resolved)
        }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }

    static func parseKinds(_ rule: String) -> [ExploreKind] {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
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

    static func javaScript(in exploreUrl: String) -> String? {
        let trimmed = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("@js:") {
            return String(trimmed.dropFirst(4))
        }

        if trimmed.lowercased().hasPrefix("<js>") && trimmed.lowercased().hasSuffix("</js>") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 4)
            let end = trimmed.index(trimmed.endIndex, offsetBy: -5)
            return String(trimmed[start..<end])
        }

        return nil
    }

    private static func evaluateJavaScript(_ script: String, source: BookSourceSnapshot) throws -> String {
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

        guard let value = context.jsContext.evaluateScript(script), context.jsContext.exception == nil else {
            throw ParseError.invalidJavaScript
        }

        if value.isArray, let array = value.toArray(),
           JSONSerialization.isValidJSONObject(array),
           let data = try? JSONSerialization.data(withJSONObject: array),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        if value.isObject, !value.isArray, let dict = value.toDictionary(),
           JSONSerialization.isValidJSONObject(dict),
           let data = try? JSONSerialization.data(withJSONObject: dict),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        if let string = value.toString(), !string.isEmpty, string != "undefined", string != "null" {
            return string
        }

        return ""
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
        errorMessage = nil
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
            recordFailure(error)
            errorMessage = NetworkError.message(for: error)
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
            recordFailure(error)
            errorMessage = NetworkError.message(for: error)
            hasMore = false
        }
    }

    private func recordFailure(_ error: Error) {
        let detail = error as NSError
        let failingURL = (detail.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
            ?? (detail.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? selection.url
        var components = URLComponents(string: failingURL)
        components?.user = nil; components?.password = nil
        components?.query = nil; components?.fragment = nil
        DebugLogger.shared.log("发现请求失败：书源=\(selection.sourceName)，ID=\(selection.sourceId)，分类=\(selection.kindTitle)，URL=\(components?.string ?? "未知")，\(detail.domain)(\(detail.code))，\(NetworkError.message(for: error))")
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


}

struct ExploreResultsView: View {
    let selection: ExploreSelection
    @StateObject private var viewModel: ExploreResultsViewModel
    @State private var selectedResult: BookSearchResult?
    @State private var navigatingToBookDetail = false

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
            if let result = selectedResult {
                BookDetailView(result: result)
                    .id(result.id)
            }
        }
    }

    private func selectResult(_ result: SearchViewModel.SearchResult) {
        selectedResult = result
        navigatingToBookDetail = true
    }
}

#Preview {
    NavigationStack {
        DiscoveryView()
    }
}
