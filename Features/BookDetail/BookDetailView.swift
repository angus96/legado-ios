import SwiftUI
import CoreData
import UIKit

struct BookDetailView: View {
    @StateObject private var viewModel: BookDetailViewModel
    @State private var showingChapterList = false
    @State private var showingSourceSelection = false
    @State private var navigatingToReader = false
    @State private var showingEditSheet = false
    @State private var showingSourceVariableSheet = false
    @State private var showingBookVariableSheet = false
    @State private var showingLogSheet = false
    @State private var showingGroupSelection = false
    @Environment(\.dismiss) var dismiss
    
    let book: Book
    
    init(book: Book) {
        self.book = book
        _viewModel = StateObject(wrappedValue: BookDetailViewModel(book: book))
    }
    
    @ViewBuilder
    var body: some View {
        if book.isDeleted || book.managedObjectContext == nil {
            Text("书籍已删除")
        } else {
            detailContent
        }
    }

    private var detailContent: some View {
        ZStack {
            backgroundView
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        arcHeaderView
                        infoSection
                    }
                }
                
                Divider()
                bottomActionBar
            }
        }
        .navigationTitle("书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button(action: { showingEditSheet = true }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.white)
                    }
                    
                    Button(action: { viewModel.shareBook() }) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.white)
                    }
                    
                    Menu {
                        Button(action: { viewModel.cacheAllChapters() }) {
                            Label("缓存全本", systemImage: "arrow.down.circle")
                        }
                        
                        Button(action: { Task { await viewModel.refreshBookInfo() } }) {
                            Label("刷新书籍信息", systemImage: "arrow.clockwise")
                        }
                        
                        Divider()
                        
                        Button(action: { viewModel.toggleTop() }) {
                            Label(book.order < 0 ? "取消置顶" : "置顶", systemImage: book.order < 0 ? "pin.slash" : "pin")
                        }
                        
                        Button(action: { showingSourceVariableSheet = true }) {
                            Label("设置源变量", systemImage: "gearshape.2")
                        }
                        
                        Button(action: { showingBookVariableSheet = true }) {
                            Label("设置书籍变量", systemImage: "book.circle")
                        }
                        
                        Divider()
                        
                        Button(action: { viewModel.copyBookUrl() }) {
                            Label("复制书籍链接", systemImage: "link")
                        }
                        
                        Button(action: { viewModel.copyTocUrl() }) {
                            Label("复制目录链接", systemImage: "list.bullet.rectangle")
                        }
                        
                        Divider()
                        
                        Button(action: { viewModel.clearCache() }) {
                            Label("清理缓存", systemImage: "trash")
                        }
                        
                        Button(action: { showingLogSheet = true }) {
                            Label("日志", systemImage: "doc.text")
                        }
                        
                        Divider()
                        
                        Button("从书架移除", role: .destructive) {
                            viewModel.deleteBook(book)
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .sheet(isPresented: $showingChapterList) {
            ChapterListView(viewModel: ReaderViewModel(), book: book)
        }
        .sheet(isPresented: $showingSourceSelection) {
            ChangeSourceSheet(isPresented: $showingSourceSelection, book: book) {
                viewModel.currentSource = try? BookSourceResolver.resolve(for: book)
                Task { await viewModel.loadChapters() }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            BookEditSheet(book: book)
        }
        .sheet(isPresented: $showingSourceVariableSheet) {
            VariableEditSheet(title: "设置源变量", value: $viewModel.sourceVariable) { newValue in
                viewModel.saveSourceVariable(newValue)
            }
        }
        .sheet(isPresented: $showingBookVariableSheet) {
            VariableEditSheet(title: "设置书籍变量", value: $viewModel.bookVariable) { newValue in
                viewModel.saveBookVariable(newValue)
            }
        }
        .sheet(isPresented: $showingLogSheet) {
            LogSheet()
        }
        .sheet(isPresented: $showingGroupSelection) {
            GroupSelectionSheet(book: book, selectedGroupId: $viewModel.selectedGroupId)
        }
        .navigationDestination(isPresented: $navigatingToReader) {
            ReaderView(bookId: book.bookId)
        }
        .task { await viewModel.loadChapters() }
    }
    
    private var backgroundView: some View {
        Group {
            if let coverUrl = book.displayCoverUrl, !coverUrl.isEmpty {
                BookCoverView(url: coverUrl, sourceId: book.customCoverUrl == nil ? book.source?.sourceId : nil)
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 30)
                    .overlay(Color.black.opacity(0.5))
                    .ignoresSafeArea()
            } else {
                Color.primary.colorInvert()
                    .ignoresSafeArea()
            }
        }
    }
    
    private var arcHeaderView: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 16)
            
            BookCoverView(url: book.displayCoverUrl, sourceId: book.customCoverUrl == nil ? book.source?.sourceId : nil)
                .frame(width: 110, height: 160)
                .cornerRadius(5)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            
            Spacer().frame(height: 24)
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameAndLabels
            infoRows
            extraMetadataRows
            introView
        }
        .background(Color.primary.colorInvert())
    }
    
    private var nameAndLabels: some View {
        VStack(spacing: 8) {
            Text(book.name)
                .font(.system(size: 18, weight: .medium))
                .lineLimit(1)
            
            if let kind = book.kind, !kind.isEmpty {
                HStack(spacing: 4) {
                    ForEach(kind.split(separator: ",").prefix(3), id: \.self) { tag in
                        Text(tag.trimmingCharacters(in: .whitespaces))
                            .font(.system(size: 11))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(3)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
    
    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            infoRow(icon: "person.fill", text: book.author) {
                EmptyView()
            }
            
            infoRow(icon: "globe", text: book.originName) {
                Button("换源") {
                    showingSourceSelection = true
                }
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(4)
            }
            
            infoRow(icon: "book.fill", text: book.latestChapterTitle ?? "暂无最新章节") {
                EmptyView()
            }
            
            infoRow(icon: "folder.fill", text: viewModel.groupName) {
                Button("换分组") {
                    showingGroupSelection = true
                }
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(4)
            }
            
            infoRow(icon: "list.bullet", text: "共 \(book.totalChapterNum) 章") {
                Button("查看") {
                    showingChapterList = true
                }
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func infoRow<Trailing: View>(icon: String, text: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 18)
            
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
            
            Spacer()
            
            trailing()
        }
        .padding(.vertical, 6)
    }
    
    private var introView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let intro = book.displayIntro, !intro.isEmpty {
                Text(HTMLAttributedString.make(from: intro, baseFontSize: 14))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(viewModel.isIntroExpanded ? nil : 4)
                    .lineSpacing(4)

                if intro.count > 100 {
                    Button(action: { viewModel.isIntroExpanded.toggle() }) {
                        Text(viewModel.isIntroExpanded ? "收起" : "展开")
                            .font(.system(size: 13))
                            .foregroundColor(.blue)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - 精装书扩展元数据（译者/出版社/出版日期/语言/ISBN/丛书/主题）

    private var extraMetadataRows: some View {
        let extra = book.extraMetadata
        return Group {
            if extra.hasAnyField {
                VStack(alignment: .leading, spacing: 0) {
                    if let v = nonEmpty(extra.translator) {
                        metaRow(icon: "person.2.fill", label: "译者", value: v)
                    }
                    if let v = nonEmpty(extra.publisher) {
                        metaRow(icon: "building.2", label: "出版社", value: v)
                    }
                    if let v = nonEmpty(extra.publishDate) {
                        metaRow(icon: "calendar", label: "出版日期", value: v)
                    }
                    if let v = nonEmpty(extra.series) {
                        metaRow(icon: "square.stack.3d.up", label: "丛书", value: v)
                    }
                    if let v = nonEmpty(extra.language) {
                        metaRow(icon: "character.book.closed", label: "语言", value: v)
                    }
                    if let v = nonEmpty(extra.isbn) {
                        metaRow(icon: "barcode", label: "ISBN", value: v)
                    }
                    if let subjects = extra.subjects, !subjects.isEmpty {
                        subjectsRow(subjects)
                    }
                    if let v = nonEmpty(extra.rights) {
                        metaRow(icon: "c.circle", label: "版权", value: v)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }

    private func metaRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func subjectsRow(_ subjects: [String]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "tag")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .frame(width: 18)
            Text("主题")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 48, alignment: .leading)
            FlowSubjects(subjects: subjects)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        return v
    }
    
    private var bottomActionBar: some View {
        HStack(spacing: 0) {
            Button(action: {
                viewModel.deleteBook(book)
                dismiss()
            }) {
                Text("移出书架")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            
            Button(action: {
                if viewModel.startReading() {
                    navigatingToReader = true
                }
            }) {
                Text(book.readProgress > 0 ? "继续阅读" : "开始阅读")
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
            }
            .accessibilityIdentifier("bookDetail.read")
        }
        .background(Color.primary.colorInvert())
    }
}

// MARK: - 主题标签流式布局

private struct FlowSubjects: View {
    let subjects: [String]

    var body: some View {
        if #available(iOS 16.0, *) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(subjects, id: \.self) { subject in
                    subjectChip(subject)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(subjects, id: \.self) { subject in
                    subjectChip(subject)
                }
            }
        }
    }

    private func subjectChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
            .foregroundColor(.accentColor)
            .cornerRadius(3)
    }
}

@MainActor
class BookDetailViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var isIntroExpanded = false
    @Published var currentSource: BookSource?
    @Published var previewChapters: [ChapterPreview] = []
    @Published var sourceVariable: String = ""
    @Published var bookVariable: String = ""
    @Published var selectedGroupId: Int64 = 0
    @Published var groupName: String = "默认"
    
    let book: Book
    private let context = CoreDataStack.shared.viewContext
    
    init(book: Book) {
        self.book = book
        self.currentSource = book.source
        self.selectedGroupId = book.group
        loadGroupInfo()
    }
    
    private func loadGroupInfo() {
        let request: NSFetchRequest<BookGroup> = BookGroup.fetchRequest()
        request.predicate = NSPredicate(format: "groupId == %lld", book.group)
        request.fetchLimit = 1
        if let group = try? context.fetch(request).first {
            groupName = group.groupName
        }
    }
    
    func loadChapters() async {
        let request: NSFetchRequest<BookChapter> = BookChapter.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", book.bookId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BookChapter.index, ascending: true)]
        request.fetchLimit = 5
        
        do {
            let chapters = try context.fetch(request)
            previewChapters = chapters.map { ChapterPreview(
                id: $0.chapterId,
                index: Int($0.index),
                title: $0.title,
                isCached: $0.isCached
            )}
        } catch {
            DebugLogger.shared.log("加载章节预览失败: \(error.localizedDescription)")
        }
    }
    
    @discardableResult
    func startReading() -> Bool {
        if book.durChapterIndex < 0 { book.durChapterIndex = 0 }
        if book.durChapterPos < 0 { book.durChapterPos = 0 }
        book.durChapterTime = Int64(Date().timeIntervalSince1970)
        do {
            try CoreDataStack.shared.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }
    
    func refreshBookInfo() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let source = try resolveSource()
            try await WebBook.getBookInfo(source: source, book: book)
            let chapterCount = try await refreshChapterList(source: source)
            book.totalChapterNum = Int32(chapterCount)
            try CoreDataStack.shared.save()
            await loadChapters()
        } catch {
            DebugLogger.shared.log("刷新书籍信息失败: \(error.localizedDescription)")
        }
    }
    
    func cacheAllChapters() {
        Task {
            isLoading = true
            defer { isLoading = false }
            do {
                let source = try resolveSource()
                _ = try await refreshChapterList(source: source)
                let request = BookChapter.fetchRequest(byBookId: book.bookId)
                let chapters = try context.fetch(request)
                for chapter in chapters {
                    if !chapter.isCached {
                        try await ChapterContentLoader.cache(chapter: chapter, book: book)
                    }
                }
                try CoreDataStack.shared.save()
                await loadChapters()
            } catch {
                DebugLogger.shared.log("缓存章节失败: \(error.localizedDescription)")
            }
        }
    }
    
    private func resolveSource() throws -> BookSource {
        guard let source = try BookSourceResolver.resolve(for: book) else { throw ReaderError.noSource }
        currentSource = source
        return source
    }

    private func refreshChapterList(source: BookSource) async throws -> Int {
        let original = try BookRequestSnapshot.capture(book)
        let definition = try BookSourceSnapshot.capture(source)
        let chapters = try await WebBook.getChapterList(source: definition, book: original)
        try Task.checkCancellation()
        try await ChapterDirectoryUpdater.replace(book: book, source: source, original: original,
                                                  metadata: original, definition: definition, chapters: chapters)
        return chapters.count
    }

    private func cacheChapterToDisk(chapter: BookChapter, content: String) throws {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("chapters", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let fileName = "\(chapter.bookId.uuidString)_\(chapter.index).txt"
        try content.write(to: dir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        chapter.isCached = true
        chapter.cachePath = fileName
    }
    
    func deleteBook(_ book: Book) {
        guard !book.isDeleted, book.managedObjectContext === context else { return }
        context.delete(book)
        do { try context.save() }
        catch { context.rollback() }
    }
    
    func toggleTop() {
        book.order = book.order < 0 ? 0 : -1
        try? CoreDataStack.shared.save()
    }
    
    func saveSourceVariable(_ value: String) {
        sourceVariable = value
        try? CoreDataStack.shared.save()
    }
    
    func saveBookVariable(_ value: String) {
        bookVariable = value
        try? CoreDataStack.shared.save()
    }
    
    func copyBookUrl() {
        let url = book.bookUrl
        if !url.isEmpty {
            UIPasteboard.general.string = url
        }
    }
    
    func copyTocUrl() {
        let url = book.tocUrl
        if !url.isEmpty {
            UIPasteboard.general.string = url
        }
    }
    
    func clearCache() {
        Task {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("chapters", isDirectory: true)
            let request = BookChapter.fetchRequest(byBookId: book.bookId)
            if let chapters = try? context.fetch(request) {
                for chapter in chapters {
                    if let cachePath = chapter.cachePath, !cachePath.isEmpty {
                        try? FileManager.default.removeItem(at: dir.appendingPathComponent(cachePath))
                    }
                    chapter.isCached = false
                    chapter.cachePath = nil
                }
            }
            try? CoreDataStack.shared.save()
            await loadChapters()
        }
    }
    
    func shareBook() {
    }
}

struct ChapterPreview: Identifiable {
    let id: UUID
    let index: Int
    let title: String
    let isCached: Bool
}

struct SourceSelectionSheet: View {
    let book: Book
    @Binding var selectedSource: BookSource?
    @Environment(\.dismiss) var dismiss
    @State private var sources: [BookSource] = []
    
    var body: some View {
        NavigationView {
            List {
                ForEach(sources, id: \.sourceId) { source in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(source.bookSourceName)
                            Text(source.bookSourceGroup ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if source.sourceId == selectedSource?.sourceId {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSource = source
                        dismiss()
                    }
                }
            }
            .navigationTitle("选择书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .task { await loadSources() }
        }
    }
    
    private func loadSources() async {
        let request: NSFetchRequest<BookSource> = BookSource.fetchRequest()
        request.predicate = NSPredicate(format: "enabled == YES")
        do {
            sources = try CoreDataStack.shared.viewContext.fetch(request)
        } catch {
            DebugLogger.shared.log("加载书源失败: \(error.localizedDescription)")
        }
    }
}

struct BookEditSheet: View {
    let book: Book
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var author = ""
    @State private var intro = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("基本信息") {
                    TextField("书名", text: $name)
                    TextField("作者", text: $author)
                }
                
                Section("简介") {
                    TextEditor(text: $intro)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("编辑书籍")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        book.name = name
                        book.author = author
                        book.intro = intro
                        try? CoreDataStack.shared.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = book.name
                author = book.author
                intro = book.intro ?? ""
            }
        }
    }
}

struct VariableEditSheet: View {
    let title: String
    @Binding var value: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var editingValue = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextEditor(text: $editingValue)
                        .frame(minHeight: 150)
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("变量值")
                } footer: {
                    Text("可在书源规则中通过 JS 获取此变量")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(editingValue)
                        dismiss()
                    }
                }
            }
            .onAppear { editingValue = value }
        }
    }
}

struct LogSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var logs: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(logs)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
            }
            .navigationTitle("日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { logs = await loadLogs() }
        }
    }
    
    private func loadLogs() async -> String {
        guard let logPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("legado.log") else {
            return "日志文件不存在"
        }
        do {
            return try String(contentsOf: logPath, encoding: .utf8)
        } catch {
            return "读取日志失败: \(error.localizedDescription)"
        }
    }
}

struct GroupSelectionSheet: View {
    let book: Book
    @Binding var selectedGroupId: Int64
    @Environment(\.dismiss) var dismiss
    @State private var groups: [BookGroup] = []
    
    var body: some View {
        NavigationView {
            List {
                ForEach(groups, id: \.groupId) { group in
                    Button(action: {
                        book.group = group.groupId
                        selectedGroupId = group.groupId
                        try? CoreDataStack.shared.save()
                        dismiss()
                    }) {
                        HStack {
                            Text(group.groupName)
                            Spacer()
                            if group.groupId == selectedGroupId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("选择分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .task { await loadGroups() }
        }
    }
    
    private func loadGroups() async {
        let request: NSFetchRequest<BookGroup> = BookGroup.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        do {
            groups = try CoreDataStack.shared.viewContext.fetch(request)
        } catch {
            DebugLogger.shared.log("加载分组失败: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationView {
        BookDetailView(book: Book.create(in: CoreDataStack.shared.viewContext))
    }
}
