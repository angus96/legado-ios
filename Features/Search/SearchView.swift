import SwiftUI
import CoreData

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var showingSourcePicker = false
    @State private var showHistory = true
    @State private var navigatingToBookDetail = false
    @State private var selectedBook: Book?
    @State private var openingResultId: UUID?
    @State private var historyKeywords: [SearchKeyword] = []
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchNavBar
                progressView
                contentView
            }
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSourcePicker = true }) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showingSourcePicker) {
                SourcePickerView(selectedSources: $viewModel.selectedSources)
            }
            .navigationDestination(isPresented: $navigatingToBookDetail) {
                if let book = selectedBook {
                    BookDetailView(book: book)
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
    }
    
    private var searchNavBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索", text: $viewModel.searchText)
                .accessibilityIdentifier("search.keyword")
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit {
                    performSearch()
                }
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private var progressView: some View {
        Group {
            if viewModel.isSearching {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(height: 2)
            } else {
                Divider()
            }
        }
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
            Text("输入关键词搜索书籍")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var resultsListView: some View {
        ZStack {
            List {
                ForEach(viewModel.searchResults) { result in
                    Button(action: { selectResult(result) }) {
                        SearchItemView(result: result)
                    }
                    .buttonStyle(.plain)
                    .disabled(openingResultId == result.id)
                }
            }
            .listStyle(.plain)
            
            if viewModel.isSearching {
                VStack {
                    Spacer()
                    stopButton
                    Spacer()
                }
            }
        }
    }
    
    private var stopButton: some View {
        HStack {
            Spacer()
            VStack {
                Spacer()
                Button(action: { viewModel.cancelSearch() }) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                }
                .padding()
            }
        }
    }
    
    private func performSearch() {
        showHistory = false
        saveHistoryKeyword()
        Task {
            await viewModel.search(keyword: viewModel.searchText, sources: viewModel.selectedSources)
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

struct SearchItemView: View {
    let result: SearchViewModel.SearchResult
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BookCoverView(url: result.coverUrl, sourceId: result.sourceId)
                .frame(width: 80, height: 110)
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(result.displayName)
                        .font(.system(size: 16))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if result.sourceCount > 1 {
                        Text("\(result.sourceCount)")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }
                
                Text(result.displayAuthor)
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
                        ForEach(kind.split(separator: ",").prefix(3), id: \.self) { tag in
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
            }
        }
        .padding(.vertical, 4)
    }
}

struct SourcePickerView: View {
    @Binding var selectedSources: [BookSource]
    @Environment(\.dismiss) var dismiss
    @State private var sources: [BookSource] = []
    
    var body: some View {
        NavigationView {
            List {
                ForEach(sources, id: \.sourceId) { source in
                    HStack {
                        Text(source.displayName)
                        Spacer()
                        if selectedSources.contains(where: { $0.sourceId == source.sourceId }) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggleSource(source) }
                }
            }
            .navigationTitle("选择书源")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .task { await loadSources() }
        }
    }
    
    private func loadSources() async {
        do {
            sources = try CoreDataStack.shared.viewContext.fetch(BookSource.fetchRequest())
        } catch {
            DebugLogger.shared.log("加载书源失败: \(error.localizedDescription)")
        }
    }
    
    private func toggleSource(_ source: BookSource) {
        if let index = selectedSources.firstIndex(where: { $0.sourceId == source.sourceId }) {
            selectedSources.remove(at: index)
        } else {
            selectedSources.append(source)
        }
    }
}

#Preview {
    SearchView()
}
