import SwiftUI
import CoreData
import JavaScriptCore

struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @StateObject private var books = DiscoveryBookWallViewModel()
    @State private var showingSources = false
    @State private var showingSearch = false
    @State private var showingSourceManage = false
    @State private var showingSourceCheck = false
    @State private var diagnosticSource: BookSource?
    @State private var selectedBook: BookSearchResult?
    @State private var showingBookDetail = false
    
    var body: some View {
        VStack(spacing: 0) {
            header
            if let group = viewModel.selectedGroup {
                categories(group)
                if group.isLoading {
                    ProgressView("正在加载分类…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let selection = viewModel.selectedExplore {
                    DiscoveryBookWall(model: books, selection: selection, onSelect: { result in
                        selectedBook = result
                        showingBookDetail = true
                    }, onChangeSource: { showingSources = true }, onCheckSource: checkSource)
                    .id(selection.cacheKey)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "square.grid.2x2").font(.system(size: 36)).foregroundStyle(.secondary)
                        Text(group.errorMessage ?? "这个书源暂无发现分类").multilineTextAlignment(.center)
                        HStack {
                            Button("重试") { viewModel.retryGroup(group.sourceId) }.buttonStyle(.bordered)
                            Button("换个书源") { showingSources = true }.buttonStyle(.bordered)
                            Button("校验书源", action: checkSource).buttonStyle(.bordered)
                        }
                    }
                    .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if viewModel.isLoading {
                ProgressView("正在读取书源…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("暂无发现内容").font(.headline)
                    Text("请先添加并启用支持发现功能的书源").font(.footnote).foregroundStyle(.secondary)
                    Button("管理书源") { showingSourceManage = true }.buttonStyle(.borderedProminent)
                }
                .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.loadExploreGroups()
            viewModel.restoreSelection()
        }
        .task(id: viewModel.selectedExplore?.cacheKey) {
            if let selection = viewModel.selectedExplore { await books.show(selection) }
            else { books.clear() }
        }
        .onDisappear { viewModel.cancelLoading(); books.cancelLoading() }
        .sheet(isPresented: $showingSources) { DiscoverySourcePicker(model: viewModel) }
        .sheet(isPresented: $showingSearch) { SearchView() }
        .sheet(isPresented: $showingSourceManage, onDismiss: { Task { await viewModel.refresh() } }) {
            NavigationStack { SourceManageView() }
        }
        .sheet(isPresented: $showingSourceCheck, onDismiss: { Task { await viewModel.refresh() } }) {
            if let source = diagnosticSource, !source.isDeleted {
                SourceDiagnosticView(source: source, bookName: "", failingBookURL: "")
            }
        }
        .navigationDestination(isPresented: $showingBookDetail) {
            if let book = selectedBook {
                BookDetailView(result: book).id(book.id).toolbar(.visible, for: .navigationBar)
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

    private var header: some View {
        HStack(spacing: 14) {
                Text("发现").font(.title2.weight(.bold))
                Spacer(minLength: 4)
                Button { showingSources = true } label: {
                    HStack(spacing: 5) {
                        Text(viewModel.selectedGroup?.sourceName ?? "选择书源").lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium)).padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    .frame(maxWidth: 175)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("当前书源：" + (viewModel.selectedGroup?.sourceName ?? "选择书源"))
                .accessibilityIdentifier("discovery.sourcePicker")
                Button { showingSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .frame(minWidth: 32, minHeight: 44).accessibilityLabel("搜书")
                Menu {
                    Button("刷新分类") { Task { await viewModel.refresh() } }
                    Button("校验当前书源", action: checkSource).disabled(viewModel.selectedGroup == nil)
                    Button("管理书源") { showingSourceManage = true }
                } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 32, minHeight: 44) }
                .accessibilityLabel("发现页操作")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 18).padding(.vertical, 6)
        .background(Color(.systemBackground))
    }
    
    private func categories(_ group: ExploreGroup) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(group.exploreKinds) { kind in
                        let selected = viewModel.selectedExplore?.url == kind.url
                        Button { viewModel.openExplore(group: group, kind: kind) } label: {
                            VStack(spacing: 10) {
                                Text(kind.title).font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1)
                                Capsule().fill(selected ? Color.accentColor : .clear).frame(height: 3)
                            }
                            .fixedSize(horizontal: true, vertical: false).padding(.top, 13)
                            .foregroundColor(selected ? .accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                        .id(kind.url)
                        .accessibilityValue(selected ? "已选择" : "")
                        .accessibilityIdentifier("discovery.category." + kind.title)
                    }
                }.padding(.horizontal, 18)
            }
            .onChange(of: viewModel.selectedExplore?.cacheKey) { _ in
                if let url = viewModel.selectedExplore?.url { proxy.scrollTo(url, anchor: .center) }
            }
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func checkSource() {
        guard let id = viewModel.selectedSourceID else { return }
        let request = BookSource.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "sourceId == %@", id as CVarArg)
        do {
            diagnosticSource = try CoreDataStack.shared.viewContext.fetch(request).first
            showingSourceCheck = diagnosticSource != nil
        } catch {
            viewModel.errorMessage = error.localizedDescription
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
    var sourceGroup: String? = nil
    var exploreKinds: [ExploreKind] = []
    var isLoading = false
    var hasLoadedKinds = false
    var errorMessage: String?
}

struct ExploreSelection: Identifiable, Hashable {
    let id = UUID()
    let sourceId: UUID
    let sourceName: String
    let kindTitle: String
    let url: String

    var cacheKey: String { sourceId.uuidString + "|" + url }
}

@MainActor
class DiscoveryViewModel: ObservableObject {
    typealias ExploreOperation = (BookSourceSnapshot) async throws -> [ExploreKind]

    @Published var exploreGroups: [ExploreGroup] = []
    @Published var filteredGroups: [ExploreGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedExplore: ExploreSelection?
    @Published private(set) var selectedSourceID: UUID?
    
    private let context: NSManagedObjectContext
    private let operation: ExploreOperation
    private let defaults: UserDefaults?
    private var groupTasks: [UUID: Task<Void, Never>] = [:]
    private var loadID = UUID()
    private var currentKeyword: String = ""

    init(context: NSManagedObjectContext = CoreDataStack.shared.newBackgroundContext(), defaults: UserDefaults? = .standard,
         operation: @escaping ExploreOperation = { try await ExploreRuleParser.parse($0) }) {
        self.context = context
        self.defaults = defaults
        self.operation = operation
    }

    var selectedGroup: ExploreGroup? { exploreGroups.first { $0.sourceId == selectedSourceID } }

    func restoreSelection() {
        let savedID = selectedSourceID ?? defaults?.string(forKey: "discovery.selectedSourceID").flatMap(UUID.init(uuidString:))
        let group = exploreGroups.first { $0.sourceId == savedID }
            ?? exploreGroups.first { $0.hasLoadedKinds && !$0.exploreKinds.isEmpty }
            ?? exploreGroups.first
        guard let group else {
            selectedSourceID = nil
            selectedExplore = nil
            return
        }
        selectSource(group.sourceId)
    }

    func selectSource(_ sourceID: UUID) {
        guard let group = exploreGroups.first(where: { $0.sourceId == sourceID }) else { return }
        if selectedSourceID != sourceID { selectedExplore = nil }
        selectedSourceID = sourceID
        defaults?.set(sourceID.uuidString, forKey: "discovery.selectedSourceID")
        if group.hasLoadedKinds { selectRememberedKind(in: group) }
        else { loadKinds(sourceID) }
    }

    private func selectRememberedKind(in group: ExploreGroup) {
        let savedURL = (defaults?.dictionary(forKey: "discovery.selectedCategories") as? [String: String])?[group.sourceId.uuidString]
        guard let kind = group.exploreKinds.first(where: { $0.url == savedURL }) ?? group.exploreKinds.first else {
            selectedExplore = nil
            return
        }
        openExplore(group: group, kind: kind)
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
                request.propertiesToFetch = ["sourceId", "bookSourceName", "bookSourceGroup", "exploreUrl"]
                request.predicate = NSPredicate(format: "enabled == YES AND enabledExplore == YES AND exploreUrl != nil AND exploreUrl != ''")
                request.sortDescriptors = [NSSortDescriptor(key: "bookSourceName", ascending: true)]
                return try context.fetch(request).compactMap { values -> ExploreGroup? in
                    guard let id = values["sourceId"] as? UUID,
                          let name = values["bookSourceName"] as? String else { return nil }
                    var group = ExploreGroup(sourceId: id, sourceName: name)
                    group.sourceGroup = values["bookSourceGroup"] as? String
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
        restoreSelection()
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
        if selectedSourceID == sourceId { selectRememberedKind(in: exploreGroups[index]) }
    }
    
    func openExplore(group: ExploreGroup, kind: ExploreKind) {
        selectedSourceID = group.sourceId
        if selectedExplore?.sourceId == group.sourceId && selectedExplore?.url == kind.url { return }
        defaults?.set(group.sourceId.uuidString, forKey: "discovery.selectedSourceID")
        var categories = defaults?.dictionary(forKey: "discovery.selectedCategories") as? [String: String] ?? [:]
        categories[group.sourceId.uuidString] = kind.url
        defaults?.set(categories, forKey: "discovery.selectedCategories")
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

#Preview {
    NavigationStack {
        DiscoveryView()
    }
}
