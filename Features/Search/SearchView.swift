import SwiftUI
import CoreData

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingSourcePicker = false
    @State private var showHistory = true
    @State private var navigatingToBookDetail = false
    @State private var selectedResult: BookSearchResult?
    @State private var sourceResult: BookSearchResult?
    @State private var historyKeywords: [SearchKeyword] = []
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchNavBar
                searchModePicker
                progressView
                contentView
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { viewModel.cancelSearch(); dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSourcePicker = true }) {
                        Label("书源", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showingSourcePicker) {
                SourcePickerView(selectedSources: $viewModel.selectedSources)
            }
            .sheet(item: $sourceResult) { result in
                SearchBookSourcesSheet(result: result, searchModel: viewModel) { selected in
                    sourceResult = nil
                    selectResult(selected)
                }
            }
            .navigationDestination(isPresented: $navigatingToBookDetail) {
                if let result = selectedResult {
                    BookDetailView(result: result)
                        .id(result.id)
                }
            }
            .alert("错误", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .onAppear { loadHistory() }
        .onDisappear { viewModel.cancelSearch() }
    }
    
    private var searchNavBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(viewModel.searchMode == .author ? "输入作者名" : (viewModel.searchMode == .title ? "输入完整书名关键词" : "输入书名或作者"), text: $viewModel.searchText)
                .accessibilityIdentifier("search.keyword")
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    performSearch()
                }
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.clearSearch(); showHistory = true }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("清空搜索")
                .accessibilityIdentifier("search.clear")
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var searchModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("搜索方式", selection: $viewModel.searchMode) {
                Text("综合").tag(SearchViewModel.SearchMode.all)
                Text("精确书名").tag(SearchViewModel.SearchMode.title)
                Text("按作者").tag(SearchViewModel.SearchMode.author)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("search.mode")
            if viewModel.searchMode == .author {
                Text("只显示作者名包含关键词的书。部分书源仅支持搜书名，可能搜不到作者。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if viewModel.searchMode == .title {
                Text("书名必须连续包含输入的全部文字，不拆词；允许书名前后有其他文字。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
    
    private var progressView: some View {
        VStack(spacing: 8) {
            if viewModel.hasSearched {
                HStack {
                    if viewModel.isSearching { ProgressView().controlSize(.small) }
                    Text("\(viewModel.wasCancelled ? "已停止" : (viewModel.isSearching ? "正在搜索" : "搜索完成")) · \(viewModel.completedSourceCount)/\(viewModel.totalSourceCount) 个书源")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("search.progress")
                    Spacer()
                    if viewModel.isSearching {
                        Button("停止") { viewModel.cancelSearch() }
                            .accessibilityIdentifier("search.stop")
                    }
                }
                if viewModel.failedSourceCount > 0 {
                    DisclosureGroup("\(viewModel.failedSourceCount) 个书源暂时无法搜索") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(viewModel.sourceErrors, id: \.self) { error in
                                Text(error).font(.caption).lineLimit(2)
                            }
                            if viewModel.failedSourceCount > viewModel.sourceErrors.count {
                                Text("仅显示前 \(viewModel.sourceErrors.count) 条原因").font(.caption)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Text("搜索 \(viewModel.selectedSources.count) 个已选书源")
                    Spacer()
                    Button("选择书源") { showingSourcePicker = true }
                }.font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var contentView: some View {
        if showHistory && viewModel.searchText.isEmpty && viewModel.searchResults.isEmpty {
            historyView
        } else if viewModel.searchResults.isEmpty {
            emptyStateView
        } else {
            resultsListView
        }
    }
    
    private var historyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("搜索历史")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: clearHistory) {
                        Text("清除")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 8) {
                    ForEach(historyKeywords, id: \.word) { keyword in
                        Button(action: {
                            viewModel.searchText = keyword.word
                            performSearch()
                        }) {
                            Text(keyword.word)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("search.empty")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if viewModel.isSearching { return "正在向书源查找书籍…" }
        if !viewModel.hasSearched {
            return viewModel.searchMode == .author ? "输入作者名开始搜索" : "输入书名或作者开始搜索"
        }
        if viewModel.wasCancelled { return "搜索已停止" }
        if viewModel.searchMode == .title { return "没有找到书名完整包含关键词的书" }
        return viewModel.searchMode == .author ? "没有找到作者匹配的书" : "没有找到相关书籍"
    }
    
    private var resultsListView: some View {
        List {
            ForEach(viewModel.searchResults) { result in
                Button(action: { selectResult(result) }) { SearchItemView(result: result, showsSourceCount: false) }
                    .buttonStyle(.plain)
                    .overlay(alignment: .topTrailing) {
                        Button { sourceResult = result } label: {
                            Text("\(result.sourceCount) 个书源")
                                .accessibilityIdentifier("search.sourceCount")
                                .font(.caption2).foregroundColor(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor).clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search.sources." + result.name)
                    }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
    }

    private func performSearch() {
        let keyword = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        isSearchFocused = false
        showHistory = false
        saveHistoryKeyword()
        Task {
            await viewModel.search(keyword: keyword, sources: viewModel.selectedSources)
        }
    }
    
    private func selectResult(_ result: SearchViewModel.SearchResult) {
        isSearchFocused = false
        selectedResult = result
        navigatingToBookDetail = true
    }
    
    private func loadHistory() {
        let request = SearchKeyword.fetchRequest() as NSFetchRequest<SearchKeyword>
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SearchKeyword.lastUseTime, ascending: false)]
        request.fetchLimit = 20
        do {
            historyKeywords = try CoreDataStack.shared.viewContext.fetch(request)
        } catch {
            DebugLogger.shared.log("加载搜索历史失败: \(error.localizedDescription)")
        }
    }
    
    private func saveHistoryKeyword() {
        let keyword = viewModel.searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }
        let context = CoreDataStack.shared.viewContext
        let request = SearchKeyword.fetchRequest() as NSFetchRequest<SearchKeyword>
        request.predicate = NSPredicate(format: "word == %@", keyword)
        if let existing = try? context.fetch(request).first {
            existing.usage += 1
            existing.lastUseTime = Int64(Date().timeIntervalSince1970 * 1000)
        } else {
            _ = SearchKeyword.create(in: context, word: keyword)
        }
        try? CoreDataStack.shared.save()
        loadHistory()
    }
    
    private func clearHistory() {
        let context = CoreDataStack.shared.viewContext
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "SearchKeyword")
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try? context.execute(deleteRequest)
        try? CoreDataStack.shared.save()
        historyKeywords = []
    }
}

struct SearchBookSourcesSheet: View {
    let result: BookSearchResult
    @ObservedObject var searchModel: SearchViewModel
    let onSelect: (BookSearchResult) -> Void
    @StateObject private var viewModel = SearchViewModel(selectionDefaults: nil)
    @Environment(\.dismiss) private var dismiss
    @State private var requestedMore = false
    @State private var checkingSource: BookSource?
    @State private var checkingBookURL = ""

    private var sources: [BookSearchSource] {
        let additional = viewModel.searchResults.first {
            $0.displayName.localizedCaseInsensitiveCompare(result.displayName) == .orderedSame &&
            (result.displayAuthor.isEmpty || $0.displayAuthor.localizedCaseInsensitiveCompare(result.displayAuthor) == .orderedSame)
        }?.availableSources ?? []
        var seen = Set<UUID>()
        let current = searchModel.searchResults.first { $0.id == result.id } ?? result
        return (current.availableSources + additional).filter { seen.insert($0.sourceId).inserted }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("优先显示本次搜索范围内已找到的书源。需要扩大范围时，再搜索全部启用的书源。")
                        .font(.footnote).foregroundColor(.secondary)
                    if viewModel.isSearching {
                        HStack {
                            ProgressView()
                            Text("正在搜索 \(viewModel.completedSourceCount)/\(viewModel.totalSourceCount) 个书源")
                            Spacer()
                            Button("停止") { viewModel.cancelSearch() }
                        }
                    } else {
                        Button("重新搜索全部启用书源") {
                            requestedMore = true
                            Task { await viewModel.search(keyword: result.name, sources: viewModel.selectedSources) }
                        }
                        .accessibilityIdentifier("search.sources.searchMore")
                        if requestedMore {
                            Text(viewModel.wasCancelled ? "搜索已停止，已找到的书源仍可选择" : "搜索完成，共找到 \(sources.count) 个书源")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Section("《\(result.name)》· \(sources.count) 个书源") {
                    ForEach(sources) { source in
                        Button { onSelect(result.using(source)) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(source.sourceName).foregroundColor(.primary)
                                if let chapter = source.lastChapter, !chapter.isEmpty {
                                    Text(chapter).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("search.source." + source.sourceName)
                        .contextMenu {
                            Button("校验这个书源") {
                                checkingBookURL = source.bookUrl
                                let request = BookSource.fetchRequest()
                                request.fetchLimit = 1
                                request.predicate = NSPredicate(format: "sourceId == %@", source.sourceId as CVarArg)
                                checkingSource = try? CoreDataStack.shared.viewContext.fetch(request).first
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: Binding(get: { checkingSource != nil }, set: { if !$0 { checkingSource = nil } })) {
                if let source = checkingSource {
                    SourceDiagnosticView(source: source, bookName: result.name, failingBookURL: checkingBookURL)
                }
            }
        }
        .onDisappear { viewModel.cancelSearch() }
    }
}

struct SearchItemView: View {
    let result: SearchViewModel.SearchResult
    var showsSourceCount = true
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BookCoverView(url: result.coverUrl, sourceId: result.sourceId)
                .frame(width: 80, height: 110)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(result.displayName)
                        .font(.system(size: 16))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if result.sourceCount > 0 {
                        Text("\(result.sourceCount) 个书源")
                            .accessibilityIdentifier("search.sourceCount")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .opacity(showsSourceCount ? 1 : 0)
                            .accessibilityHidden(!showsSourceCount)
                    }
                }
                
                Text(result.displayAuthor.isEmpty ? "未知作者" : result.displayAuthor)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let wordCount = result.wordCount, !wordCount.isEmpty {
                    Text(wordCount)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let kind = result.kind, !kind.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(kind.split(separator: ",").prefix(3).enumerated()), id: \.offset) { _, tag in
                            Text(tag.trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 10))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(2)
                        }
                    }
                }
                
                if let lastChapter = result.lastChapter, !lastChapter.isEmpty {
                    Text(lastChapter)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let intro = result.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Text(result.displaySourceName).font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }
}

struct SourcePickerView: View {
    @Binding var selectedSources: [BookSource]
    @Environment(\.dismiss) var dismiss
    @State private var sources: [BookSource] = []
    @State private var query = ""

    private var filteredSources: [BookSource] {
        sources.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) ||
            ($0.bookSourceGroup?.localizedCaseInsensitiveContains(query) ?? false) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("全选当前列表") {
                            var ids = Set(selectedSources.map(\.sourceId))
                            selectedSources += filteredSources.filter { ids.insert($0.sourceId).inserted }
                        }
                        Spacer()
                        Button("清空") { selectedSources = [] }
                    }
                    Text("已选 \(selectedSources.count) 个；书源越多，完整搜索耗时越长。")
                        .font(.caption).foregroundColor(.secondary)
                }
                ForEach(filteredSources, id: \.objectID) { source in
                    Button { toggleSource(source) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(source.displayName)
                                if let group = source.bookSourceGroup, !group.isEmpty {
                                    Text(group).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if selectedSources.contains(where: { $0.objectID == source.objectID }) {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }.foregroundColor(.primary)
                    }
                }
            }
            .searchable(text: $query, prompt: "按书源名称或分组筛选")
            .navigationTitle("选择书源")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } } }
            .task {
                let request = BookSource.fetchRequest()
                request.predicate = NSPredicate(format: "enabled == YES AND searchUrl != nil AND searchUrl != ''")
                request.sortDescriptors = [NSSortDescriptor(key: "bookSourceName", ascending: true)]
                sources = (try? CoreDataStack.shared.viewContext.fetch(request)) ?? []
            }
        }
    }

    private func toggleSource(_ source: BookSource) {
        if let index = selectedSources.firstIndex(where: { $0.objectID == source.objectID }) {
            selectedSources.remove(at: index)
        } else { selectedSources.append(source) }
    }
}
