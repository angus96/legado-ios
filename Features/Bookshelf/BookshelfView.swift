import SwiftUI
import CoreData

struct BookshelfView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = BookshelfViewModel()
    @StateObject private var localBookViewModel = LocalBookViewModel()
    @State private var showingSearch = false
    @State private var showingAddMenu = false
    @State private var showingLayoutConfig = false
    @State private var selectedGroupId: Int64?
    
    var body: some View {
        VStack(spacing: 0) {
            // 分组样式：Fragment1（分组Tab）或 Fragment2（统一列表）
            if viewModel.groupStyle == .tabs && !viewModel.groups.isEmpty {
                groupTabs
            }
            bookshelfContent
        }
        .navigationTitle("书架")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showingLayoutConfig = true }) {
                    Image(systemName: viewModel.viewMode == .grid ? "square.grid.2x2" : "list.bullet")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: { showingSearch = true }) {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityIdentifier("bookshelf.search")
                    
                    Menu {
                        Button(action: importLocalBook) {
                            Label("导入本地", systemImage: "folder")
                        }
                        NavigationLink(destination: LocalBookView(onImportTapped: importLocalBook)) {
                            Label("本地书籍", systemImage: "books.vertical")
                        }
                        Button(action: { viewModel.showingAddUrl = true }) {
                            Label("添加网址", systemImage: "link")
                        }
                        Divider()
                        NavigationLink(destination: BookshelfManagePanel(viewModel: viewModel)) {
                            Label("书架管理", systemImage: "slider.horizontal.3")
                        }
                        NavigationLink(destination: GroupManagePanel()) {
                            Label("分组管理", systemImage: "folder.badge.gearshape")
                        }
                        Divider()
                        NavigationLink(destination: DownloadManagePanel()) {
                            Label("下载管理", systemImage: "arrow.down.circle")
                        }
                        Button(action: { viewModel.updateAllToc() }) {
                            Label("更新目录", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchView()
        }
        .sheet(isPresented: $viewModel.showingAddUrl) {
            AddBookByUrlSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingLayoutConfig) {
            BookshelfConfigSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.loadBooks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                         object: viewContext)) { _ in
            viewModel.pruneUnavailableBooks()
        }
        .refreshable {
            await viewModel.refreshBooks()
        }
        .alert("书架操作失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
    }
    
    private var groupTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                GroupTabButton(
                    title: "全部",
                    isSelected: selectedGroupId == nil,
                    count: viewModel.totalBookCount
                ) {
                    selectedGroupId = nil
                }
                
                ForEach(viewModel.groups, id: \.groupId) { group in
                    GroupTabButton(
                        title: group.groupName,
                        isSelected: selectedGroupId == group.groupId,
                        count: 0
                    ) {
                        selectedGroupId = group.groupId
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 44)
        .background(Color(.systemGray6))
    }
    
    // MARK: - 书架内容
    @ViewBuilder
    private var bookshelfContent: some View {
        if viewModel.groupStyle == .unified {
            unifiedListView
        } else {
            let books = filteredBooks
            
            if books.isEmpty && !viewModel.isLoading {
                emptyView
            } else {
                switch viewModel.viewMode {
                case .grid:
                    gridView(books)
                case .list:
                    listView(books)
                }
            }
        }
    }
    
    // Fragment2: 统一列表模式，分组作为分隔标题
    @ViewBuilder
    private var unifiedListView: some View {
        let groupedBooks = booksByGroup
        
        if groupedBooks.isEmpty && !viewModel.isLoading {
            emptyView
        } else {
            switch viewModel.viewMode {
            case .grid:
                unifiedGridView(groupedBooks)
            case .list:
                unifiedListViewRows(groupedBooks)
            }
        }
    }
    
    // 按分组整理书籍（Fragment2 模式）
    private var booksByGroup: [(group: BookGroup?, books: [Book])] {
        var result: [(group: BookGroup?, books: [Book])] = []
        
        // 先添加无分组的书籍
        let ungroupedBooks = viewModel.books.filter { $0.group == 0 }
        if !ungroupedBooks.isEmpty {
            result.append((group: nil, books: ungroupedBooks))
        }
        
        // 再添加各分组的书籍
        for group in viewModel.groups {
            let groupBooks = viewModel.books.filter { $0.group == group.groupId }
            if !groupBooks.isEmpty {
                result.append((group: group, books: groupBooks))
            }
        }
        
        return result
    }
    
    private func unifiedGridView(_ groupedBooks: [(group: BookGroup?, books: [Book])]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(groupedBooks.enumerated()), id: \.element.group?.groupId) { index, item in
                    let isFirstGroup = index == 0
                    let isLastGroup = index == groupedBooks.count - 1
                    
                    VStack(spacing: 8) {
                        // 分组标题
                        if let group = item.group {
                            Text(group.groupName)
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                        }
                        
                        let rowCount = (item.books.count + viewModel.gridColumns - 1) / viewModel.gridColumns
                        
                        LazyVGrid(columns: gridColumnsArray, spacing: 12) {
                            ForEach(Array(item.books.enumerated()), id: \.element.objectID) { bookIndex, book in
                                let rowIndex = bookIndex / viewModel.gridColumns
                                let isFirstRow = rowIndex == 0
                                let isLastRow = rowIndex == rowCount - 1
                                
                                NavigationLink(value: book.bookId) {
                                    BookGridCell(book: book, showUnread: viewModel.showUnread)
                                        .padding(.top, isFirstRow ? 12 : 0)
                                        .padding(.bottom, isLastRow ? 36 : 12)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    bookContextMenu(book)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .padding(.top, isFirstGroup ? 12 : 0)
                    .padding(.bottom, isLastGroup ? 24 : 12)
                }
            }
        }
        .navigationDestination(for: UUID.self) { bookId in
            ReaderView(bookId: bookId)
        }
    }
    
    // 统一列表视图（Fragment2）
    private func unifiedListViewRows(_ groupedBooks: [(group: BookGroup?, books: [Book])]) -> some View {
        List {
            ForEach(groupedBooks, id: \.group?.groupId) { item in
                Section {
                    ForEach(item.books, id: \.bookId) { book in
                        NavigationLink(value: book.bookId) {
                            BookListCell(
                                book: book,
                                showUnread: viewModel.showUnread,
                                showUpdateTime: viewModel.showUpdateTime
                            )
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                viewModel.removeBook(book)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    if let group = item.group {
                        Text(group.groupName)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: UUID.self) { bookId in
            ReaderView(bookId: bookId)
        }
    }
    
    private var filteredBooks: [Book] {
        guard let groupId = selectedGroupId else {
            return viewModel.books
        }
        return viewModel.books.filter { $0.group == groupId }
    }
    
    // 网格列数动态配置（参考 Android 3-6列）
    private var gridColumnsArray: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: viewModel.gridColumns)
    }
    
    // MARK: - 空视图
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("书架空空如也")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("点击右上角 + 导入书籍")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func gridView(_ books: [Book]) -> some View {
        let rowCount = (books.count + viewModel.gridColumns - 1) / viewModel.gridColumns
        
        return ScrollView {
            LazyVGrid(columns: gridColumnsArray, spacing: 12) {
                ForEach(Array(books.enumerated()), id: \.element.objectID) { index, book in
                    let rowIndex = index / viewModel.gridColumns
                    let isFirstRow = rowIndex == 0
                    let isLastRow = rowIndex == rowCount - 1
                    
                    NavigationLink(value: book.bookId) {
                        BookGridCell(book: book, showUnread: viewModel.showUnread)
                            .padding(.top, isFirstRow ? 12 : 0)
                            .padding(.bottom, isLastRow ? 36 : 12)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        bookContextMenu(book)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .navigationDestination(for: UUID.self) { bookId in
            ReaderView(bookId: bookId)
        }
    }
    
    // MARK: - 列表视图（参考 Android item_bookshelf_list）
    private func listView(_ books: [Book]) -> some View {
        List {
            ForEach(Array(books.enumerated()), id: \.element.objectID) { index, book in
                let isFirst = index == 0
                let isLast = index == books.count - 1
                
                NavigationLink(value: book.bookId) {
                    BookListCell(
                        book: book,
                        showUnread: viewModel.showUnread,
                        showUpdateTime: viewModel.showUpdateTime
                    )
                    .padding(.top, isFirst ? 12 : 0)
                    .padding(.bottom, isLast ? 36 : 12)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        viewModel.removeBook(book)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: UUID.self) { bookId in
            ReaderView(bookId: bookId)
        }
    }
    
    // MARK: - 书籍上下文菜单
    @ViewBuilder
    private func bookContextMenu(_ book: Book) -> some View {
        Button {
            viewModel.toggleTop(book)
        } label: {
            Label(book.order < 0 ? "取消置顶" : "置顶", systemImage: "pin")
        }
        
        Button {
            viewModel.updateBook(book)
        } label: {
            Label("更新目录", systemImage: "arrow.clockwise")
        }
        
        NavigationLink(destination: BookDetailView(book: book)) {
            Label("书籍详情", systemImage: "info.circle")
        }
        
        Divider()
        
        Button(role: .destructive) {
            viewModel.removeBook(book)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }
    
    // MARK: - 导入本地书籍
    private func importLocalBook() {
        DocumentPickerHelper.shared.present(contentTypes: [.plainText, .text, .epub, .data]) { urls in
            guard let url = urls.first else { return }
            Task { @MainActor in
                try? await localBookViewModel.importBook(url: url)
                await viewModel.loadBooks()
            }
        }
    }
}

// MARK: - 分组标签按钮
struct GroupTabButton: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(isSelected ? .blue : .primary)
            .frame(minWidth: 60)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            )
        }
    }
}

// MARK: - 网格单元格（参考 Android item_bookshelf_grid）
struct BookGridCell: View {
    let book: Book
    let showUnread: Bool
    @AppStorage("cover.cornerRadius") private var cornerRadius = 12.0
    @AppStorage("cover.shadowEnabled") private var shadowEnabled = true
    @AppStorage("cover.showProgress") private var showProgress = true
    
    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                BookCoverView(url: book.displayCoverUrl, sourceId: book.customCoverUrl == nil ? book.source?.sourceId : nil)
                    .aspectRatio(3/4, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .shadow(color: shadowEnabled ? .black.opacity(0.15) : .clear, radius: shadowEnabled ? 2 : 0, x: 0, y: shadowEnabled ? 1 : 0)
                
                if showUnread && book.hasNewChapter {
                    Text("新")
                        .font(.system(size: 10))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: -4, y: 4)
                }
                
                if showProgress && book.durChapterIndex > 0 && book.totalChapterNum > 0 {
                    VStack {
                        Spacer()
                        GeometryReader { progGeo in
                            Rectangle()
                                .fill(Color.green)
                                .frame(width: progGeo.size.width * min(1.0, Double(book.durChapterIndex) / Double(max(1, book.totalChapterNum))), height: 3)
                        }
                        .frame(height: 3)
                    }
                }
                
                if book.isUpdating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(4)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .offset(x: -4, y: 4)
                }
            }
            
            Text(book.name)
                .font(.system(size: 12))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .frame(height: 28)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 列表单元格（参考 Android item_bookshelf_list）
struct BookListCell: View {
    let book: Book
    let showUnread: Bool
    let showUpdateTime: Bool
    @AppStorage("cover.cornerRadius") private var cornerRadius = 12.0
    
    var body: some View {
        HStack(spacing: 10) {
            // 封面
            BookCoverView(url: book.displayCoverUrl, sourceId: book.customCoverUrl == nil ? book.source?.sourceId : nil)
                .frame(width: 66, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            
            // 书籍信息
            VStack(alignment: .leading, spacing: 4) {
                // 书名 + 未读角标
                HStack(spacing: 4) {
                    Text(book.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if showUnread && book.hasNewChapter {
                        Text("新")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                    
                    if book.isUpdating {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                }
                
                // 作者（带图标）
                HStack(spacing: 2) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(book.author.isEmpty ? "未知" : book.author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if showUpdateTime, book.latestChapterTime > 0 {
                        Text("·")
                            .foregroundColor(.secondary)
                        
                        Text(Date(timeIntervalSince1970: TimeInterval(book.latestChapterTime / 1000)).formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 阅读进度（带图标）
                HStack(spacing: 2) {
                    Image(systemName: "book.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(book.readProgressText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // 最新章节（带图标）
                if let latestChapter = book.latestChapterTitle, !latestChapter.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "text.page.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(latestChapter)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - 添加网址弹窗
struct AddBookByUrlSheet: View {
    let viewModel: BookshelfViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("输入书籍网址", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("添加网址")
                } footer: {
                    Text("支持直接输入书籍详情页URL")
                }
            }
            .navigationTitle("添加书籍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        viewModel.addBookByUrl(url)
                        dismiss()
                    }
                    .disabled(url.isEmpty)
                }
            }
        }
    }
}

// MARK: - 书架配置弹窗（参考 Android BookshelfConfigDialog）
struct BookshelfConfigSheet: View {
    @ObservedObject var viewModel: BookshelfViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("分组样式") {
                    Picker("样式", selection: $viewModel.groupStyle) {
                        Text("分组Tab").tag(BookshelfViewModel.GroupStyle.tabs)
                        Text("统一列表").tag(BookshelfViewModel.GroupStyle.unified)
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("布局方式") {
                    Picker("布局", selection: $viewModel.viewMode) {
                        Text("网格布局").tag(BookshelfViewModel.ViewMode.grid)
                        Text("列表布局").tag(BookshelfViewModel.ViewMode.list)
                    }
                    .pickerStyle(.segmented)
                    
                    if viewModel.viewMode == .grid {
                        Stepper("网格列数: \(viewModel.gridColumns)", value: $viewModel.gridColumns, in: 3...6)
                    }
                }
                
                Section("排序方式") {
                    Picker("排序", selection: $viewModel.sortMode) {
                        Text("按阅读时间").tag(BookshelfViewModel.SortMode.readTime)
                        Text("按更新时间").tag(BookshelfViewModel.SortMode.updateTime)
                        Text("按书名").tag(BookshelfViewModel.SortMode.name)
                        Text("按作者").tag(BookshelfViewModel.SortMode.author)
                    }
                }
                
                Section("显示选项") {
                    Toggle("显示未读角标", isOn: $viewModel.showUnread)
                    Toggle("显示更新时间", isOn: $viewModel.showUpdateTime)
                    Toggle("显示快速滚动条", isOn: $viewModel.showFastScroller)
                }
            }
            .navigationTitle("书架设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

extension Book {
    var hasNewChapter: Bool {
        latestChapterTime > durChapterTime
    }
    
    var readProgressText: String {
        if totalChapterNum == 0 { return "未读" }
        let percent = Int(Double(durChapterIndex) / Double(totalChapterNum) * 100)
        return "阅读 \(durChapterIndex + 1)/\(totalChapterNum) (\(percent)%)"
    }
    
    var isUpdating: Bool { false }
}

struct BookCoverView: View {
    let url: String?
    let sourceId: UUID?
    @State private var image: UIImage?
    @State private var requestIdentity: String = ""

    private var loadIdentity: String {
        "\(url ?? "")|\(sourceId?.uuidString ?? "")"
    }
    
    var body: some View {
        GeometryReader { geo in
            let targetSize = geo.size
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: targetSize.width, height: targetSize.height)
                        .clipped()
                } else {
                    ZStack {
                        Color(.systemGray5)
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
            }
        }
        .task(id: loadIdentity) {
            let identity = loadIdentity
            requestIdentity = identity
            image = nil
            guard let urlString = url, !urlString.isEmpty else { return }
            let loadedImage = await ImageCacheManager.shared.loadImage(from: urlString, sourceId: sourceId)
            guard !Task.isCancelled, requestIdentity == identity else { return }
            image = loadedImage
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let imageName: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: imageName)
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text(title)
                .font(.title2)
                .fontWeight(.medium)
            
            Text(subtitle)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BookshelfManagePanel: View {
    @ObservedObject var viewModel: BookshelfViewModel

    var body: some View {
        Form {
            Section(header: Text("显示方式")) {
                Picker("布局", selection: $viewModel.viewMode) {
                    Text("网格").tag(BookshelfViewModel.ViewMode.grid)
                    Text("列表").tag(BookshelfViewModel.ViewMode.list)
                }
                .pickerStyle(.segmented)
            }

            Section(header: Text("排序方式")) {
                Picker("排序", selection: $viewModel.sortMode) {
                    Text("最近阅读").tag(BookshelfViewModel.SortMode.readTime)
                    Text("更新时间").tag(BookshelfViewModel.SortMode.updateTime)
                    Text("书名").tag(BookshelfViewModel.SortMode.name)
                    Text("作者").tag(BookshelfViewModel.SortMode.author)
                }
            }

            Section(header: Text("附加选项")) {
                Toggle("显示未读标记", isOn: $viewModel.showUnread)
                Toggle("显示更新时间", isOn: $viewModel.showUpdateTime)
                Toggle("显示快速滚动条", isOn: $viewModel.showFastScroller)
            }
        }
        .navigationTitle("书架管理")
    }
}

struct GroupManagePanel: View {
    @State private var groups: [BookGroup] = []
    @State private var newGroupName = ""

    var body: some View {
        List {
            Section(header: Text("新增分组")) {
                HStack {
                    TextField("分组名称", text: $newGroupName)
                    Button("添加") {
                        addGroup()
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section(header: Text("已有分组")) {
                ForEach(groups, id: \.groupId) { group in
                    HStack {
                        Text(group.groupName)
                        Spacer()
                        if group.isSystem {
                            Text("系统")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteGroup)
            }
        }
        .navigationTitle("分组管理")
        .task {
            loadGroups()
        }
    }

    private func loadGroups() {
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<BookGroup> = BookGroup.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        groups = (try? context.fetch(request)) ?? []
    }

    private func addGroup() {
        let name = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let context = CoreDataStack.shared.viewContext
        _ = BookGroup.create(in: context, groupName: name)
        try? context.save()
        newGroupName = ""
        loadGroups()
    }

    private func deleteGroup(at offsets: IndexSet) {
        let context = CoreDataStack.shared.viewContext
        for index in offsets {
            let group = groups[index]
            guard !group.isSystem else { continue }
            context.delete(group)
        }
        try? context.save()
        loadGroups()
    }
}

struct DownloadManagePanel: View {
    var body: some View {
        EmptyStateView(
            title: "暂无下载任务",
            subtitle: "缓存章节或批量下载后会显示在这里",
            imageName: "arrow.down.circle"
        )
        .navigationTitle("下载管理")
    }
}

#Preview {
    NavigationStack {
        BookshelfView()
    }
}
