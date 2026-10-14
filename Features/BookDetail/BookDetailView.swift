import SwiftUI
import CoreData
import UIKit

struct BookDetailView: View {
    @StateObject private var viewModel: BookDetailViewModel
    @State private var showingChapterList = false
    @State private var showingChapterCache = false
    @State private var showingSourceSelection = false
    @State private var navigatingToReader = false
    @State private var showingEditSheet = false
    @State private var showingSourceVariableSheet = false
    @State private var showingBookVariableSheet = false
    @State private var showingLogSheet = false
    @State private var showingGroupSelection = false
    @State private var confirmingRemoval = false
    @Environment(\.dismiss) var dismiss
    
    private var book: Book { viewModel.book }

    init(book: Book) {
        _viewModel = StateObject(wrappedValue: BookDetailViewModel(book: book))
    }

    init(result: BookSearchResult) {
        _viewModel = StateObject(wrappedValue: BookDetailViewModel(result: result))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerView
                if let message = viewModel.detailError {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "wifi.exclamationmark").foregroundStyle(.secondary)
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("重试") { Task { await viewModel.refreshBookInfo() } }
                            .font(.footnote.weight(.medium))
                    }
                    .padding(.horizontal, 4)
                }
                introView
                informationCard
                extraMetadataRows
            }
            .frame(maxWidth: 680)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomActionBar }
        .navigationTitle("书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if let url = URL(string: book.bookUrl), url.scheme != nil {
                        ShareLink(item: url) { Label("分享书籍", systemImage: "square.and.arrow.up") }
                    }
                    Button(action: { Task { await viewModel.refreshBookInfo() } }) {
                        Label("刷新书籍信息", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading || book.isLocal)
                    if viewModel.isInBookshelf {
                        Button(action: { showingChapterCache = true }) {
                            Label("缓存章节", systemImage: "arrow.down.circle")
                        }.disabled(book.isLocal)
                        Button(action: { showingEditSheet = true }) {
                            Label("编辑书籍", systemImage: "pencil")
                        }
                        Button(action: { viewModel.toggleTop() }) {
                            Label(book.order < 0 ? "取消置顶" : "置顶", systemImage: "pin")
                        }
                        Button(action: { showingGroupSelection = true }) {
                            Label("选择分组", systemImage: "folder")
                        }
                        Divider()
                        Button(action: { showingSourceVariableSheet = true }) {
                            Label("设置源变量", systemImage: "gearshape.2")
                        }
                        Button(action: { showingBookVariableSheet = true }) {
                            Label("设置书籍变量", systemImage: "book.circle")
                        }
                        Button(action: { viewModel.clearCache() }) {
                            Label("清理缓存", systemImage: "trash")
                        }
                    }
                    Button(action: { viewModel.copyBookUrl() }) {
                        Label("复制书籍链接", systemImage: "link")
                    }
                    if !book.tocUrl.isEmpty {
                        Button(action: { viewModel.copyTocUrl() }) {
                            Label("复制目录链接", systemImage: "list.bullet.rectangle")
                        }
                    }
                    Button(action: { showingLogSheet = true }) {
                        Label("日志", systemImage: "doc.text")
                    }
                    if viewModel.isInBookshelf {
                        Divider()
                        Button("从书架移除", role: .destructive) { confirmingRemoval = true }
                            .accessibilityIdentifier("bookDetail.remove")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
                .accessibilityIdentifier("bookDetail.more")
            }
        }
        .sheet(isPresented: $showingChapterList) {
            ChapterListView(viewModel: ReaderViewModel(), book: book) { chapter in
                if viewModel.startReading(chapterIndex: chapter.index, chapterTitle: chapter.title) {
                    navigatingToReader = true
                }
            }
        }
        .sheet(isPresented: $showingChapterCache, onDismiss: {
            Task { await viewModel.loadChapters() }
        }) {
            ChapterCacheView(book: book)
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
        .task { await viewModel.loadDetails() }
        .confirmationDialog("从书架移除《\(book.name)》？", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("移除", role: .destructive) {
                if viewModel.deleteBook(book) { dismiss() }
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("确定") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 20) {
            Group {
                if nonEmpty(book.displayCoverUrl) != nil {
                    BookCoverView(url: book.displayCoverUrl, sourceId: book.customCoverUrl == nil ? book.source?.sourceId : nil)
                } else {
                    ZStack(alignment: .topLeading) {
                        LinearGradient(colors: [Color(red: 0.18, green: 0.35, blue: 0.40),
                                                Color(red: 0.10, green: 0.21, blue: 0.27)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "book.closed").font(.caption)
                            Text(book.name).font(.system(.headline, design: .serif)).lineLimit(4)
                            Spacer(minLength: 0)
                            Rectangle().frame(height: 1).opacity(0.4)
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(13)
                    }
                }
            }
            .frame(width: 104, height: 148)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Text(book.name)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("bookDetail.title")
                Text(nonEmpty(book.author) ?? "未知作者")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let kind = nonEmpty(book.kind) {
                    Text(kind.replacingOccurrences(of: ",", with: " · "))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(2)
                }
                if let wordCount = nonEmpty(book.wordCount) {
                    Text(wordCount).font(.caption).foregroundStyle(.secondary)
                }
                if viewModel.isLoading {
                    ProgressView("正在加载详情").font(.caption).controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "globe").foregroundStyle(.secondary).frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text("书源").font(.caption).foregroundStyle(.secondary)
                    Text(nonEmpty(book.originName) ?? "本地书籍").font(.subheadline)
                }
                Spacer(minLength: 0)
                if viewModel.isInBookshelf && !book.isLocal {
                    Button("换源") { showingSourceSelection = true }.font(.subheadline)
                }
            }
            if let latest = nonEmpty(book.latestChapterTitle) {
                Divider()
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最新章节").font(.caption).foregroundStyle(.secondary)
                        Text(latest).font(.subheadline).lineLimit(2)
                    }
                } icon: {
                    Image(systemName: "clock").foregroundStyle(.secondary).frame(width: 22)
                }
            }
            Divider()
            Button {
                Task {
                    if await viewModel.prepareChapterList() { showingChapterList = true }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet").foregroundStyle(.secondary).frame(width: 22)
                    Text("章节目录").font(.subheadline)
                    Spacer()
                    if viewModel.isLoadingChapters {
                        ProgressView().controlSize(.small)
                    } else {
                        if book.totalChapterNum > 0 {
                            Text("共 \(book.totalChapterNum) 章").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading || viewModel.isLoadingChapters)
            .accessibilityIdentifier("bookDetail.chapters")
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private var introView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("简介").font(.headline)
            if let intro = nonEmpty(book.displayIntro) {
                Text(HTMLAttributedString.make(from: intro, baseFontSize: 15))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(viewModel.isIntroExpanded ? nil : 6)
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if intro.count > 100 {
                    Button(viewModel.isIntroExpanded ? "收起简介" : "展开全部") {
                        withAnimation(.easeInOut(duration: 0.2)) { viewModel.isIntroExpanded.toggle() }
                    }
                    .font(.subheadline.weight(.medium))
                }
            } else {
                Text(viewModel.isLoading ? "正在获取简介…" : "书源暂未提供简介")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
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
        HStack(spacing: 12) {
            Button(action: { viewModel.addToBookshelf() }) {
                Label(viewModel.isInBookshelf ? "已在书架" : "加入书架",
                      systemImage: viewModel.isInBookshelf ? "checkmark" : "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(viewModel.isInBookshelf ? Color.secondary : Color.accentColor)
                    .background(Color.accentColor.opacity(viewModel.isInBookshelf ? 0.05 : 0.10),
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(viewModel.isInBookshelf || viewModel.isLoadingChapters)
            .accessibilityIdentifier("bookDetail.add")
            Button {
                if viewModel.startReading() { navigatingToReader = true }
            } label: {
                Label(book.durChapterIndex > 0 || book.durChapterPos > 0 ? "继续阅读" : "开始阅读", systemImage: "book")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(viewModel.isLoadingChapters)
            .accessibilityIdentifier("bookDetail.read")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 680)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
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
    @Published private(set) var isLoadingChapters = false
    @Published private(set) var isInBookshelf = false
    @Published private(set) var book: Book
    @Published var errorMessage: String?
    @Published private(set) var detailError: String?
    @Published var isIntroExpanded = false
    @Published var currentSource: BookSource?
    @Published var previewChapters: [ChapterPreview] = []
    @Published var sourceVariable = ""
    @Published var bookVariable = ""
    @Published var selectedGroupId: Int64 = 0
    @Published var groupName = "默认"

    private let context: NSManagedObjectContext
    // 预览只修改独立子上下文，绝不保存到书架。其他页面保存主上下文也不会带入预览。
    private var previewContext: NSManagedObjectContext?
    private var fetchedChapters: [WebChapter] = []

    init(book: Book) {
        self.book = book
        self.context = book.managedObjectContext ?? CoreDataStack.shared.viewContext
        self.isInBookshelf = true
        self.currentSource = book.source
        self.selectedGroupId = book.group
        loadGroupInfo()
    }

    init(result: BookSearchResult, context: NSManagedObjectContext = CoreDataStack.shared.viewContext) {
        self.context = context
        let preview = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        preview.parent = context
        self.previewContext = preview
        let draft = Book.create(in: preview)
        BookImportData(name: result.name, author: result.author, bookUrl: result.bookUrl,
                       origin: result.sourceId.uuidString, originName: result.sourceName,
                       kind: result.kind, coverUrl: result.coverUrl, intro: result.intro,
                       latestChapterTitle: result.lastChapter, wordCount: result.wordCount).apply(to: draft)
        self.book = draft
        do {
            if let existing = try BookDeduplicator.findBook(byBookUrl: result.bookUrl, in: context) {
                // 浏览搜索结果不能用默认进度、空目录和空简介覆盖已有书籍。
                self.book = existing
                self.isInBookshelf = true
                self.previewContext = nil
            } else {
                let request = BookSource.fetchRequest()
                request.predicate = NSPredicate(format: "sourceId == %@", result.sourceId as CVarArg)
                request.fetchLimit = 1
                draft.source = try preview.fetch(request).first
            }
        } catch {
            errorMessage = "读取书架状态失败：\(error.localizedDescription)"
        }
        currentSource = try? BookSourceResolver.resolve(for: book)
        selectedGroupId = book.group
        loadGroupInfo()
    }

    private func loadGroupInfo() {
        let request = BookGroup.fetchRequest()
        request.predicate = NSPredicate(format: "groupId == %lld", book.group)
        request.fetchLimit = 1
        if let group = try? context.fetch(request).first { groupName = group.groupName }
    }

    func loadDetails() async {
        await loadChapters()
        if !isInBookshelf { await refreshBookInfo() }
    }

    func loadChapters() async {
        guard let bookContext = book.managedObjectContext, !book.isDeleted else { return }
        let request = BookChapter.fetchRequest(byBookId: book.bookId)
        request.fetchLimit = 5
        do {
            try await ChapterDirectoryUpdater.repairStoredDirectory(for: book)
            previewChapters = try bookContext.fetch(request).map {
                ChapterPreview(id: $0.chapterId, index: Int($0.index), title: $0.title, isCached: $0.isCached)
            }
        } catch {
            errorMessage = "加载章节失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    func addToBookshelf() -> Bool {
        if isInBookshelf { return !book.isDeleted && book.managedObjectContext != nil }
        var inserted: Book?
        do {
            // 再次查询，避免两个详情页或连续点击创建重复记录。
            if let existing = try BookDeduplicator.findBook(byBookUrl: book.bookUrl, in: context) {
                book = existing
            } else {
                let saved = Book.create(in: context)
                inserted = saved
                BookImportData(name: book.name, author: book.author, bookUrl: book.bookUrl,
                               tocUrl: book.tocUrl, origin: book.origin, originName: book.originName,
                               kind: book.kind, coverUrl: book.coverUrl, intro: book.intro,
                               latestChapterTitle: book.latestChapterTitle,
                               totalChapterNum: Int32(fetchedChapters.count), wordCount: book.wordCount).apply(to: saved)
                saved.tocHtml = book.tocHtml
                saved.downloadUrls = book.downloadUrls
                saved.source = try BookSourceResolver.resolve(for: saved)
                writePreviewChapters(to: saved, in: context)
                try context.save()
                book = saved
            }
            isInBookshelf = true
            previewContext = nil
            currentSource = try? BookSourceResolver.resolve(for: book)
            selectedGroupId = book.group
            loadGroupInfo()
            return true
        } catch {
            if let inserted { context.delete(inserted); context.processPendingChanges() }
            errorMessage = "加入书架失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func startReading(chapterIndex: Int32? = nil, chapterTitle: String? = nil) -> Bool {
        guard addToBookshelf() else { return false }
        let oldIndex = book.durChapterIndex
        let oldPosition = book.durChapterPos
        let oldTitle = book.durChapterTitle
        let oldTime = book.durChapterTime
        if let chapterIndex {
            book.durChapterIndex = max(0, chapterIndex)
            book.durChapterPos = 0
            book.durChapterTitle = chapterTitle
        } else {
            book.durChapterIndex = max(0, book.durChapterIndex)
            book.durChapterPos = max(0, book.durChapterPos)
        }
        book.durChapterTime = Int64(Date().timeIntervalSince1970)
        do { try context.save(); return true }
        catch {
            book.durChapterIndex = oldIndex; book.durChapterPos = oldPosition
            book.durChapterTitle = oldTitle; book.durChapterTime = oldTime
            errorMessage = "保存阅读位置失败：\(error.localizedDescription)"
            return false
        }
    }

    func refreshBookInfo() async {
        guard !isLoading, !book.isLocal else { return }
        let requestedBook = book
        isLoading = true
        detailError = nil
        defer { isLoading = false }
        do {
            let source = try resolveSource()
            let definition = try BookSourceSnapshot.capture(source)
            let original = try BookRequestSnapshot.capture(requestedBook)
            let metadata = try await WebBook.getBookInfo(source: definition, book: original)
            try Task.checkCancellation()
            guard book === requestedBook, !requestedBook.isDeleted else { return }
            try await metadata.applyInfo(to: requestedBook)
            if isInBookshelf { try context.save() }
        } catch is CancellationError {
        } catch {
            detailError = "详情暂时未能更新。" + NetworkError.message(for: error)
        }
    }

    func prepareChapterList() async -> Bool {
        guard !isLoadingChapters else { return false }
        isLoadingChapters = true
        defer { isLoadingChapters = false }
        do {
            guard let bookContext = book.managedObjectContext, !book.isDeleted else {
                throw ManagedObjectAccessError.unavailable
            }
            if try bookContext.count(for: BookChapter.fetchRequest(byBookId: book.bookId)) > 0 { return true }
            if book.tocUrl.isEmpty { await refreshBookInfo() }
            let requestedBook = book
            let source = try resolveSource()
            let definition = try BookSourceSnapshot.capture(source)
            let original = try BookRequestSnapshot.capture(requestedBook)
            let chapters = try await WebBook.getChapterList(source: definition, book: original)
            try Task.checkCancellation()
            guard book === requestedBook, !book.isDeleted else { return false }
            guard !chapters.isEmpty else { throw WebBookError.noRule("书源未返回章节目录") }
            if isInBookshelf {
                try await ChapterDirectoryUpdater.replace(book: book, source: source, original: original,
                                                          metadata: original, definition: definition, chapters: chapters)
            } else {
                fetchedChapters = chapters
                writePreviewChapters(to: book, in: bookContext)
                book.totalChapterNum = Int32(chapters.count)
            }
            await loadChapters()
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = "加载目录失败：\(NetworkError.message(for: error))"
            return false
        }
    }

    private func writePreviewChapters(to target: Book, in targetContext: NSManagedObjectContext) {
        for (index, item) in fetchedChapters.enumerated() {
            let chapter = BookChapter.create(in: targetContext, bookId: target.bookId, url: item.url,
                                             index: Int32(index), title: item.title)
            chapter.book = target
            chapter.isVIP = item.isVip
            chapter.isPay = item.isPay
        }
    }

    private func resolveSource() throws -> BookSource {
        guard let source = try BookSourceResolver.resolve(for: book) else { throw ReaderError.noSource }
        currentSource = source
        return source
    }

    @discardableResult
    func deleteBook(_ book: Book) -> Bool {
        guard isInBookshelf, !book.isDeleted, book.managedObjectContext === context else { return false }
        context.delete(book)
        do { try context.save(); return true }
        catch {
            context.rollback()
            errorMessage = "移除失败：\(error.localizedDescription)"
            return false
        }
    }

    func toggleTop() {
        book.order = book.order < 0 ? 0 : -1
        saveChanges()
        objectWillChange.send()
    }

    func saveSourceVariable(_ value: String) { sourceVariable = value; saveChanges() }
    func saveBookVariable(_ value: String) { bookVariable = value; saveChanges() }
    func copyBookUrl() { if !book.bookUrl.isEmpty { UIPasteboard.general.string = book.bookUrl } }
    func copyTocUrl() { if !book.tocUrl.isEmpty { UIPasteboard.general.string = book.tocUrl } }

    private func saveChanges() {
        do { try context.save() }
        catch { errorMessage = "保存失败：\(error.localizedDescription)" }
    }

    func clearCache() {
        Task {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("chapters", isDirectory: true)
            if let chapters = try? context.fetch(BookChapter.fetchRequest(byBookId: book.bookId)) {
                for chapter in chapters {
                    if let path = chapter.cachePath, !path.isEmpty {
                        try? FileManager.default.removeItem(at: dir.appendingPathComponent(path))
                    }
                    chapter.isCached = false
                    chapter.cachePath = nil
                }
            }
            saveChanges()
            await loadChapters()
        }
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
        let logPath = URL(fileURLWithPath: DebugLogger.shared.logFilePath)
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
