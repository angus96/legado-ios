//
//  ChapterDrawer.swift
//  Legado-iOS
//
//  对应 Android DrawerLayout + TabLayout：右侧滑入抽屉，4 Tab（目录/书签/书源/搜索）
//  替代原先章节列表的 .sheet 形态，贴近 Android ReadBookActivity 体验
//

import SwiftUI
import CoreData

struct ChapterDrawer: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: ReaderViewModel
    let book: Book

    let onChangeSource: () -> Void
    let onSearchInBook: () -> Void

    enum DrawerTab: Int, CaseIterable {
        case toc = 0, bookmarks, sources, search

        var title: String {
            switch self {
            case .toc: return "目录"
            case .bookmarks: return "书签"
            case .sources: return "书源"
            case .search: return "搜索"
            }
        }
    }

    @State private var selectedTab: DrawerTab = .toc
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    tabHeader
                    Divider()
                    contentPane
                }
                .frame(width: geo.size.width * 0.82)
                .background(Color(.systemBackground))
                .offset(x: dragOffset)
                .gesture(dragGesture)
                .transition(.move(edge: .trailing))
            }
        }
    }

    private var tabHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text(book.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Picker("", selection: $selectedTab) {
                ForEach(DrawerTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var contentPane: some View {
        switch selectedTab {
        case .toc:
            TOCPane(viewModel: viewModel, book: book, onSelect: close)
        case .bookmarks:
            BookmarksPane(viewModel: viewModel, book: book, onSelect: close)
        case .sources:
            SourcesPane(book: book, onChangeSource: {
                close()
                onChangeSource()
            })
        case .search:
            SearchPane(onOpen: {
                close()
                onSearchInBook()
            })
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { v in
                if v.translation.width > 0 {
                    dragOffset = v.translation.width
                }
            }
            .onEnded { v in
                if v.translation.width > 100 {
                    close()
                }
                withAnimation { dragOffset = 0 }
            }
    }

    private func close() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

// MARK: - Tab 1: 目录

private struct TOCPane: View {
    @ObservedObject var viewModel: ReaderViewModel
    let book: Book
    let onSelect: () -> Void

    @State private var chapters: [BookChapter] = []
    @State private var searchText = ""
    @State private var sortAscending = true
    @State private var showingCache = false

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            chapterList
        }
        .task { await loadChapters() }
        .sheet(isPresented: $showingCache, onDismiss: {
            Task { await loadChapters() }
        }) {
            ChapterCacheView(book: book)
        }
    }

    private var searchHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索章节", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            Button(action: { sortAscending.toggle() }) {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    .frame(width: 28, height: 28)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
            .foregroundColor(.primary)

            if !book.isLocal {
                Button { showingCache = true } label: {
                    Image(systemName: "arrow.down.circle")
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("缓存章节")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var filtered: [BookChapter] {
        let ordered = sortAscending ? chapters : chapters.reversed()
        if searchText.isEmpty { return ordered }
        return ordered.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var useHierarchy: Bool { book.isHardcover }

    private var chapterList: some View {
        List {
            ForEach(filtered, id: \.chapterId) { chapter in
                Button(action: {
                    viewModel.jumpToChapter(Int(chapter.index))
                    onSelect()
                }) {
                    row(for: chapter)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(
                    top: 6,
                    leading: 12 + indent(for: chapter),
                    bottom: 6,
                    trailing: 12
                ))
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func row(for chapter: BookChapter) -> some View {
        HStack(spacing: 8) {
            if useHierarchy, isVolume(chapter) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
            }
            Text(chapter.title)
                .font(.system(size: useHierarchy && isVolume(chapter) ? 15 : 14,
                              weight: useHierarchy && isVolume(chapter) ? .semibold : .regular))
                .foregroundColor(chapter.index == book.durChapterIndex ? .accentColor : .primary)
                .lineLimit(1)

            Spacer()

            if chapter.isVIP {
                Text("VIP")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.orange, lineWidth: 1)
                    )
            }

            if chapter.isCached {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if chapter.index == book.durChapterIndex {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    private func indent(for chapter: BookChapter) -> CGFloat {
        guard useHierarchy else { return 0 }
        return isVolume(chapter) ? 0 : 16
    }

    // 启发式：标题以 "卷"/"第X卷"/"第X部"/"Part"/"Book" 开头视为卷级
    private func isVolume(_ chapter: BookChapter) -> Bool {
        let title = chapter.title.trimmingCharacters(in: .whitespaces)
        let patterns = [
            #"^第[零一二三四五六七八九十百千0-9]+[卷部]"#,
            #"^卷[零一二三四五六七八九十百千0-9]+"#,
            #"(?i)^(part|book)\s+[ivxlcdm0-9]+"#,
            #"^上[册卷部]$|^中[册卷部]$|^下[册卷部]$"#
        ]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p),
               re.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil {
                return true
            }
        }
        return false
    }

    private func loadChapters() async {
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<BookChapter> = BookChapter.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", book.bookId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \BookChapter.index, ascending: true)]
        do {
            chapters = try context.fetch(request)
        } catch {
            DebugLogger.shared.log("加载章节列表失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - Tab 2: 书签

private struct BookmarksPane: View {
    @ObservedObject var viewModel: ReaderViewModel
    let book: Book
    let onSelect: () -> Void

    @State private var bookmarks: [Bookmark] = []

    var body: some View {
        Group {
            if bookmarks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("暂无书签")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(bookmarks, id: \.bookmarkId) { bookmark in
                        Button(action: {
                            viewModel.jumpToChapter(Int(bookmark.chapterIndex))
                            onSelect()
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bookmark.chapterTitle)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(bookmark.content)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await loadBookmarks() }
    }

    private func loadBookmarks() async {
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<Bookmark> = Bookmark.fetchRequest()
        request.predicate = NSPredicate(format: "bookId == %@", book.bookId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Bookmark.chapterIndex, ascending: true)]
        bookmarks = (try? context.fetch(request)) ?? []
    }
}

// MARK: - Tab 3: 书源

private struct SourcesPane: View {
    let book: Book
    let onChangeSource: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    Text("当前书源")
                        .font(.system(size: 14))
                    Spacer()
                }
                Text(book.originName)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal, 12)

            Button(action: onChangeSource) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("换源")
                }
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding(.horizontal, 12)

            Spacer()
        }
    }
}

// MARK: - Tab 4: 搜索

private struct SearchPane: View {
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("全文搜索")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Button(action: onOpen) {
                Text("打开搜索")
                    .font(.system(size: 14, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            Spacer()
        }
    }
}
