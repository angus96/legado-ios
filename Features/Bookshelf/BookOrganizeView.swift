import SwiftUI
import CoreData

struct BookOrganizeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var viewModel = BookOrganizeViewModel()
    @State private var editMode: EditMode = .inactive
    @State private var showingAddGroup = false
    @State private var showingMoveSheet = false
    @State private var showingSortSheet = false
    @State private var searchText = ""
    @State private var newGroupName = ""
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isBatchMode {
                batchToolBar
            }

            if viewModel.organizeMode == .byGroup {
                groupOrganizeContent
            } else {
                bookListOrganizeContent
            }
        }
        .navigationTitle("书籍整理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(viewModel.isBatchMode ? "取消" : "编辑") {
                    if viewModel.isBatchMode {
                        viewModel.exitBatchMode()
                        editMode = .inactive
                    } else {
                        viewModel.enterBatchMode()
                        editMode = .active
                    }
                }
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: { viewModel.organizeMode = .byGroup }) {
                        Label("按分组整理", systemImage: "folder")
                    }
                    Button(action: { viewModel.organizeMode = .byBook }) {
                        Label("按书籍整理", systemImage: "book")
                    }
                    Divider()
                    Button(action: { showingSortSheet = true }) {
                        Label("排序方式", systemImage: "arrow.up.arrow.down")
                    }
                    Button(action: { viewModel.sortAscending.toggle() }) {
                        Label(
                            viewModel.sortAscending ? "升序" : "降序",
                            systemImage: viewModel.sortAscending ? "arrow.up" : "arrow.down"
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .environment(\.editMode, $editMode)
        .searchable(text: $searchText, prompt: "搜索书籍")
        .sheet(isPresented: $showingAddGroup) {
            addGroupSheet
        }
        .sheet(isPresented: $showingMoveSheet) {
            moveBookToGroupSheet
        }
        .confirmationDialog("排序方式", isPresented: $showingSortSheet) {
            ForEach(BookOrganizeViewModel.SortMode.allCases, id: \.self) { mode in
                Button(mode.title) {
                    viewModel.sortMode = mode
                }
            }
        }
        .confirmationDialog("确认删除", isPresented: $showingDeleteConfirm) {
            Button("删除选中书籍", role: .destructive) {
                viewModel.deleteSelectedBooks()
            }
            Button("取消", role: .cancel) {}
        }
        .task {
            await viewModel.loadData()
        }
        .onChange(of: searchText) { newValue in
            viewModel.searchText = newValue
        }
    }

    private var batchToolBar: some View {
        VStack(spacing: 12) {
            HStack {
                Button("全选") { viewModel.selectAll() }
                Spacer()
                Text("已选 \(viewModel.selectedBookIds.count) 本")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(viewModel.selectedBookIds.count == viewModel.books.count ? "取消全选" : "全选") {
                    if viewModel.selectedBookIds.count == viewModel.books.count {
                        viewModel.deselectAll()
                    } else {
                        viewModel.selectAll()
                    }
                }
            }

            HStack(spacing: 24) {
                BatchActionItem(icon: "folder.badge.plus", title: "移动") {
                    showingMoveSheet = true
                }
                .disabled(viewModel.selectedBookIds.isEmpty)

                BatchActionItem(icon: "pin", title: "置顶") {
                    viewModel.pinSelectedBooks()
                }
                .disabled(viewModel.selectedBookIds.isEmpty)

                BatchActionItem(icon: "arrow.down.circle", title: "缓存") {
                    viewModel.cacheSelectedBooks()
                }
                .disabled(viewModel.selectedBookIds.isEmpty)

                BatchActionItem(icon: "trash", title: "删除", color: .red) {
                    showingDeleteConfirm = true
                }
                .disabled(viewModel.selectedBookIds.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.05), radius: 3, y: -1)
    }

    private var groupOrganizeContent: some View {
        List {
            Section {
                ForEach(viewModel.groups, id: \.groupId) { group in
                    NavigationLink {
                        GroupDetailOrganizeView(group: group, viewModel: viewModel)
                    } label: {
                        groupRow(group)
                    }
                }
                .onMove { from, to in
                    viewModel.moveGroup(from: from, to: to)
                }
            } header: {
                HStack {
                    Text("分组列表")
                    Spacer()
                    Button(action: { showingAddGroup = true }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
            }

            Section {
                NavigationLink {
                    GroupDetailOrganizeView(group: nil, viewModel: viewModel)
                } label: {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundColor(.gray)
                        Text("未分组")
                        Spacer()
                        Text("\(viewModel.ungroupedBookCount)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func groupRow(_ group: BookGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: group.enableRefresh ? "folder.fill" : "folder")
                .foregroundColor(.blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.groupName)
                    .font(.body)
                Text("\(viewModel.bookCountInGroup(group.groupId)) 本")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !group.show {
                Image(systemName: "eye.slash")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }

    private var bookListOrganizeContent: some View {
        List(selection: viewModel.isBatchMode ? $viewModel.selectedBookIds : nil) {
            ForEach(viewModel.filteredBooks) { book in
                BookOrganizeRow(book: book, isBatchMode: viewModel.isBatchMode, isSelected: viewModel.selectedBookIds.contains(book.bookId)) {
                    viewModel.toggleSelection(book.bookId)
                }
                .tag(book.bookId)
            }
            .onMove { from, to in
                viewModel.moveBooks(from: from, to: to)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var addGroupSheet: some View {
        NavigationView {
            Form {
                Section("新建分组") {
                    TextField("分组名称", text: $newGroupName)
                }

                Section("已有分组") {
                    ForEach(viewModel.groups, id: \.groupId) { group in
                        HStack {
                            Text(group.groupName)
                            Spacer()
                            Button(action: { viewModel.deleteGroup(group) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("分组管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showingAddGroup = false
                        newGroupName = ""
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        viewModel.addGroup(name: newGroupName)
                        newGroupName = ""
                        showingAddGroup = false
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var moveBookToGroupSheet: some View {
        NavigationView {
            List {
                Section {
                    Button(action: {
                        viewModel.moveSelectedBooks(toGroup: 0)
                        showingMoveSheet = false
                    }) {
                        HStack {
                            Image(systemName: "tray")
                            Text("移出分组")
                            Spacer()
                        }
                    }
                }

                ForEach(viewModel.groups, id: \.groupId) { group in
                    Button(action: {
                        viewModel.moveSelectedBooks(toGroup: group.groupId)
                        showingMoveSheet = false
                    }) {
                        HStack {
                            Image(systemName: "folder")
                            Text(group.groupName)
                            Spacer()
                            Text("\(viewModel.bookCountInGroup(group.groupId))")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("移动到分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingMoveSheet = false }
                }
            }
        }
    }
}

struct BatchActionItem: View {
    let icon: String
    let title: String
    var color: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(color)
            }
        }
    }
}

struct BookOrganizeRow: View {
    let book: Book
    let isBatchMode: Bool
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isBatchMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .gray)
                    .font(.title3)
                    .onTapGesture { onToggle() }
            }

            BookCoverView(url: book.displayCoverUrl, sourceId: book.customCoverUrl == nil ? book.source?.sourceId : nil)
                .frame(width: 44, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(book.name)
                    .font(.body)
                    .lineLimit(1)

                Text(book.author.isEmpty ? "未知作者" : book.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(book.readProgressText)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let latest = book.latestChapterTitle, !latest.isEmpty {
                        Text("·")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                        Text(latest)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if book.order > 0 {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isBatchMode { onToggle() }
        }
    }
}

struct GroupDetailOrganizeView: View {
    let group: BookGroup?
    @ObservedObject var viewModel: BookOrganizeViewModel
    @State private var showingMoveSheet = false

    private var title: String {
        group?.groupName ?? "未分组"
    }

    private var books: [Book] {
        if let group = group {
            return viewModel.books.filter { $0.group == group.groupId }
        }
        return viewModel.books.filter { $0.group == 0 }
    }

    var body: some View {
        List {
            if books.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("该分组暂无书籍")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                }
            } else {
                Section {
                    ForEach(books, id: \.bookId) { book in
                        BookOrganizeRow(
                            book: book,
                            isBatchMode: viewModel.isBatchMode,
                            isSelected: viewModel.selectedBookIds.contains(book.bookId)
                        ) {
                            viewModel.toggleSelection(book.bookId)
                        }
                    }
                    .onMove { from, to in
                        viewModel.moveBooks(from: from, to: to)
                    }
                } header: {
                    HStack {
                        Text("\(books.count) 本")
                        Spacer()
                        if let group = group {
                            Button(action: { viewModel.toggleGroupRefresh(group) }) {
                                Label(
                                    group.enableRefresh ? "关闭刷新" : "开启刷新",
                                    systemImage: group.enableRefresh ? "arrow.clockwise" : "arrow.clockwise.slash"
                                )
                                .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
    }
}

@MainActor
final class BookOrganizeViewModel: ObservableObject {
    @Published var books: [Book] = []
    @Published var groups: [BookGroup] = []
    @Published var isBatchMode = false
    @Published var selectedBookIds: Set<UUID> = []
    @Published var organizeMode: OrganizeMode = .byGroup
    @Published var sortMode: SortMode = .readTime
    @Published var sortAscending = false
    @Published var searchText = ""

    enum OrganizeMode {
        case byGroup
        case byBook
    }

    enum SortMode: Int, CaseIterable {
        case readTime = 0
        case updateTime = 1
        case name = 2
        case author = 3
        case manual = 4

        var title: String {
            switch self {
            case .readTime: return "最近阅读"
            case .updateTime: return "更新时间"
            case .name: return "书名"
            case .author: return "作者"
            case .manual: return "手动排序"
            }
        }
    }

    var filteredBooks: [Book] {
        var result = books
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var ungroupedBookCount: Int {
        books.filter { $0.group == 0 }.count
    }

    func loadData() async {
        let context = CoreDataStack.shared.viewContext
        var fetchedBooks: [Book] = []
        var fetchedGroups: [BookGroup] = []
        do {
            fetchedBooks = try await context.perform {
                let request: NSFetchRequest<Book> = Book.fetchRequest()
                request.returnsObjectsAsFaults = false
                return try context.fetch(request)
            }
            fetchedGroups = try await context.perform {
                let request: NSFetchRequest<BookGroup> = BookGroup.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
                return try context.fetch(request)
            }
        } catch {
                DebugLogger.shared.error("BookOrganize fetch failed: \(error.localizedDescription)")
            }
        self.books = fetchedBooks
        self.groups = fetchedGroups
    }

    func bookCountInGroup(_ groupId: Int64) -> Int {
        books.filter { $0.group == groupId }.count
    }

    func enterBatchMode() {
        isBatchMode = true
        selectedBookIds.removeAll()
    }

    func exitBatchMode() {
        isBatchMode = false
        selectedBookIds.removeAll()
    }

    func selectAll() {
        selectedBookIds = Set(books.map { $0.bookId })
    }

    func deselectAll() {
        selectedBookIds.removeAll()
    }

    func toggleSelection(_ bookId: UUID) {
        if selectedBookIds.contains(bookId) {
            selectedBookIds.remove(bookId)
        } else {
            selectedBookIds.insert(bookId)
        }
    }

    func addGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let context = CoreDataStack.shared.viewContext
        _ = BookGroup.create(in: context, groupName: trimmed)
        try? context.save()
        Task { await loadData() }
    }

    func deleteGroup(_ group: BookGroup) {
        guard !group.isSystem else { return }
        let context = CoreDataStack.shared.viewContext
        context.delete(group)
        try? context.save()
        Task { await loadData() }
    }

    func moveGroup(from source: IndexSet, to destination: Int) {
        let context = CoreDataStack.shared.viewContext
        var mutable = groups
        mutable.move(fromOffsets: source, toOffset: destination)
        for (index, group) in mutable.enumerated() {
            group.order = Int32(index)
        }
        try? context.save()
    }

    func moveBooks(from source: IndexSet, to destination: Int) {
        guard sortMode == .manual else { return }
        let context = CoreDataStack.shared.viewContext
        var mutable = books
        mutable.move(fromOffsets: source, toOffset: destination)
        for (index, book) in mutable.enumerated() {
            book.order = Int32(index)
        }
        try? context.save()
    }

    func moveSelectedBooks(toGroup groupId: Int64) {
        let context = CoreDataStack.shared.viewContext
        for book in books where selectedBookIds.contains(book.bookId) {
            book.group = groupId
        }
        try? context.save()
        Task { await loadData() }
    }

    func pinSelectedBooks() {
        let context = CoreDataStack.shared.viewContext
        let maxOrder = books.map { $0.order }.max() ?? 0
        var idx = maxOrder + 1
        for book in books where selectedBookIds.contains(book.bookId) {
            book.order = idx
            idx += 1
        }
        try? context.save()
    }

    func cacheSelectedBooks() {
        let selected = books.filter { selectedBookIds.contains($0.bookId) }
        for book in selected {
            BackgroundCacheService.shared.scheduleCacheTask(for: book)
        }
    }

    func deleteSelectedBooks() {
        let context = CoreDataStack.shared.viewContext
        let selected = books.filter { !$0.isDeleted && $0.managedObjectContext != nil && selectedBookIds.contains($0.bookId) }
        let objectIDs = Set(selected.map(\.objectID))
        books.removeAll { objectIDs.contains($0.objectID) }
        selectedBookIds.removeAll()
        for book in selected {
            context.delete(book)
        }
        do { try context.save() }
        catch { context.rollback() }
        Task { await loadData() }
    }

    func toggleGroupRefresh(_ group: BookGroup) {
        group.enableRefresh.toggle()
        try? CoreDataStack.shared.viewContext.save()
    }
}
