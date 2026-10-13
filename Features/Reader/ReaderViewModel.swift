//
//  ReaderViewModel.swift
//  Legado-iOS
//
//  阅读器 ViewModel
//

import Foundation
import SwiftUI
import CoreData

@MainActor
class ReaderViewModel: ObservableObject, ReadViewCallBack {
    private let readBook = ReadBook.shared
    
    // MARK: - ReadBookCallBack 协议实现
    func upContent() {
        curTextChapter = readBook.curTextChapter
        prevTextChapter = readBook.prevTextChapter
        nextTextChapter = readBook.nextTextChapter
        
        if let textChapter = curTextChapter {
            let pages = textChapter.pages
            totalPages = pages.count
            currentChapterIndex = readBook.durChapterIndex
            currentChapter = chapters[safe: currentChapterIndex]
            if !pages.isEmpty {
                currentPageIndex = min(max(0, readBook.durChapterPos), pages.count - 1)
                durChapterPos = Int32(clamping: currentPageIndex)
                chapterContent = textChapter.getContent()
            }
        }
    }
    
    func upMenuView() {
        currentChapterIndex = readBook.durChapterIndex
        durChapterPos = Int32(clamping: readBook.durChapterPos)
    }
    
    func upPageAnim() {
    }
    
    // MARK: - ReadViewCallBack 协议实现
    func showActionMenu() {}
    func hideActionMenu() {}
    func addBookmark() {}
    func showTextActionMenu() {}
    func screenOffTimerStart() {}
    func upSystemUiVisibility() {}
    func autoPageStop() {}
    
    // MARK: - Published 属性
    @Published var chapterContent: String?
    @Published var chapterContentHTML: String?
    @Published var currentChapter: BookChapter?
    @Published var currentChapterIndex: Int = 0
    @Published var totalChapters: Int = 0
    @Published var chapters: [BookChapter] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentBook: Book?
    @Published var durChapterPos: Int32 = 0
    @Published var theme: ReaderTheme = .light
    @Published var useReplaceRule: Bool = true
    
    @Published var chapterHTMLURL: URL?
    @Published var epubBaseURL: URL?
    
    // MARK: - 三章节预加载状态（来自ReadBook）
    @Published var prevTextChapter: TextChapter?
    @Published var curTextChapter: TextChapter?
    @Published var nextTextChapter: TextChapter?
    
    // MARK: - 分页状态
    @Published var currentPageIndex: Int = 0 {
        didSet {
            if oldValue != currentPageIndex {
                updatePagingProgressIfNeeded()
            }
        }
    }
    @Published var totalPages: Int = 0
    
    // MARK: - 阅读设置
    @Published var fontSize: CGFloat = 18 {
        didSet {
            UserDefaults.standard.set(Double(fontSize), forKey: "reader.fontSize")
        }
    }
    @Published var lineSpacing: CGFloat = 8 {
        didSet {
            UserDefaults.standard.set(Double(lineSpacing), forKey: "reader.lineSpacing")
        }
    }
    @Published var pagePadding: EdgeInsets = EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16) {
        didSet {
            UserDefaults.standard.set(Double(pagePadding.leading), forKey: "reader.pageMargin")
        }
    }
    @Published var backgroundColor: Color = .white
    @Published var textColor: Color = .black
    @Published var imageStyle: ImageStyle = .original
    
    // MARK: - 新增阅读设置
    @Published var paragraphSpacing: CGFloat = 12
    @Published var letterSpacing: CGFloat = 0
    
    // MARK: - 私有属性
    private var ruleEngine: RuleEngine = RuleEngine()
    private var loadTask: Task<Void, Never>?
    private var chapterLoadID = UUID()
    private var bookLoadID = UUID()
    var cacheManager: ChapterCacheManager { ChapterCacheManager.shared }

    init() {
        loadReaderPreferences()
    }

    private func loadReaderPreferences() {
        let defaults = UserDefaults.standard

        let storedFontSize = defaults.double(forKey: "reader.fontSize")
        if storedFontSize > 0 {
            fontSize = CGFloat(storedFontSize)
        }

        let storedLineSpacing = defaults.double(forKey: "reader.lineSpacing")
        if storedLineSpacing > 0 {
            lineSpacing = CGFloat(storedLineSpacing)
        }

        let storedMargin = defaults.double(forKey: "reader.pageMargin")
        if storedMargin > 0 {
            let margin = CGFloat(storedMargin)
            pagePadding = EdgeInsets(top: 20, leading: margin, bottom: 20, trailing: margin)
        }

        if let storedTheme = defaults.string(forKey: "reader.theme") {
            applyTheme(themeFromStorage(storedTheme))
        }
    }

    private func themeFromStorage(_ raw: String) -> ReaderTheme {
        switch raw {
        case "暗色":
            return .dark
        case "羊皮纸":
            return .sepia
        case "护眼":
            return .eyeProtection
        default:
            return .light
        }
    }
    
    // MARK: - 颜色主题
    enum ReaderTheme {
        case light
        case dark
        case sepia
        case eyeProtection
        
        var backgroundColor: Color {
            switch self {
            case .light: return Color.white
            case .dark: return Color.black
            case .sepia: return Color(red: 0.96, green: 0.91, blue: 0.83)
            case .eyeProtection: return Color(red: 0.75, green: 0.84, blue: 0.71)
            }
        }
        
        var textColor: Color {
            switch self {
            case .light: return Color.black
            case .dark: return Color.white
            case .sepia: return Color(red: 0.33, green: 0.28, blue: 0.22)
            case .eyeProtection: return Color.black
            }
        }
    }
    
    // MARK: - 加载书籍
    func loadBook(byId bookId: UUID) {
        loadTask?.cancel()
        let requestID = UUID()
        bookLoadID = requestID
        chapterLoadID = UUID()
        isLoading = true
        DebugLogger.shared.log("ReaderViewModel.loadBook 开始: bookId=\(bookId)")

        loadTask = Task {
            do {
                try Task.checkCancellation()
                
                let context = CoreDataStack.shared.viewContext
                
                let request: NSFetchRequest<Book> = Book.fetchRequest()
                request.predicate = NSPredicate(format: "bookId == %@", bookId as CVarArg)
                request.fetchLimit = 1
                
                guard let book = try context.fetch(request).first else {
                    DebugLogger.shared.log("ReaderViewModel: 书籍不存在 bookId=\(bookId)")
                    errorMessage = "书籍不存在"
                    isLoading = false
                    return
                }
                
                DebugLogger.shared.log("ReaderViewModel: 找到书籍 name=\(book.name), type=\(book.type), origin=\(book.origin)")
                
                currentBook = book

                applyReadConfig(book)

                readBook.callBack = self
                readBook.resetData(book)

                try await loadChapters(book: book)
                guard !Task.isCancelled, bookLoadID == requestID else { return }
                
                let chapterIndex = min(max(0, Int(book.durChapterIndex)), chapters.count - 1)
                readBook.durChapterIndex = chapterIndex
                if chapterIndex >= 0 && chapterIndex < chapters.count {
                    currentChapterIndex = chapterIndex
                    durChapterPos = book.durChapterPos
                    currentChapter = chapters[chapterIndex]
                    
                    try await loadChapter(at: chapterIndex, restorePageIndex: Int(book.durChapterPos))
                    
                    guard !Task.isCancelled, bookLoadID == requestID else { return }
                    readBook.loadContent(resetPageOffset: false)
                }
                
                if bookLoadID == requestID { isLoading = false }
            } catch is CancellationError {
                DebugLogger.shared.log("ReaderViewModel: 加载被取消")
                if bookLoadID == requestID { isLoading = false }
            } catch {
                guard bookLoadID == requestID else { return }
                DebugLogger.shared.log("ReaderViewModel: 加载失败 \(error.localizedDescription)")
                errorMessage = "加载失败：\(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    func loadBook(_ book: Book) {
        loadBook(byId: book.bookId)
    }
    
    func cleanup() {
        bookLoadID = UUID()
        chapterLoadID = UUID()
        loadTask?.cancel()
        loadTask = nil
        if readBook.callBack === self {
            readBook.callBack = nil
        }
        readBook.releaseAndCancel()
        Task { @MainActor in
            cacheManager.cancelPreload()
        }
    }
    
    // MARK: - 加载目录
    private func loadChapters(book: Book) async throws {
        DebugLogger.shared.log("loadChapters: bookId=\(book.bookId), name=\(book.name), totalChapterNum=\(book.totalChapterNum)")
        
        let request = BookChapter.fetchRequest(byBookId: book.bookId)
        
        let context = CoreDataStack.shared.viewContext
        var chapters = try context.fetch(request)
        
        DebugLogger.shared.log("loadChapters: 从 CoreData 获取到 \(chapters.count) 章")

        if chapters.isEmpty {
            if book.isLocal {
                chapters = try await restoreLocalChaptersIfNeeded(for: book, preferredChapterIndex: Int(book.durChapterIndex))
            } else {
                guard let source = try BookSourceResolver.resolve(for: book) else { throw ReaderError.noSource }

                let original = try BookRequestSnapshot.capture(book)
                let definition = try BookSourceSnapshot.capture(source)
                let webChapters = try await WebBook.getChapterList(source: definition, book: original)
                try Task.checkCancellation()
                guard !webChapters.isEmpty else { throw ReaderError.noChapters }
                try await ChapterDirectoryUpdater.replace(book: book, source: source, original: original,
                                                          metadata: original, definition: definition, chapters: webChapters)

                chapters = try context.fetch(request)
            }
        }

        self.chapters = chapters
        self.totalChapters = chapters.count
        book.totalChapterNum = Int32(clamping: chapters.count)
        readBook.chapterSize = chapters.count
        readBook.simulatedChapterSize = chapters.count

        if chapters.isEmpty {
            throw ReaderError.noChapters
        }
    }
    
    // MARK: - 加载章节
    func loadChapter(at index: Int, restorePageIndex: Int? = nil) async throws {
        guard index >= 0 && index < chapters.count else {
            throw ReaderError.invalidChapterIndex
        }
        
        let chapter = chapters[index]
        let bookID = currentBook?.objectID
        let requestID = UUID()
        chapterLoadID = requestID
        func validateRequest() throws {
            guard !Task.isCancelled, chapterLoadID == requestID,
                  currentBook?.objectID == bookID, !chapter.isDeleted else { throw CancellationError() }
        }
        isLoading = true
        currentChapterIndex = index
        currentChapter = chapter
        if let restorePageIndex {
            currentPageIndex = max(0, restorePageIndex)
            durChapterPos = Int32(clamping: currentPageIndex)
        } else {
            currentPageIndex = 0
            durChapterPos = 0
        }
        
        do {
            DebugLogger.shared.log("loadChapter: index=\(index), chapterId=\(chapter.chapterId), isCached=\(chapter.isCached), cachePath=\(chapter.cachePath ?? "nil")")
            
            if let book = currentBook {
                DebugLogger.shared.log("loadChapter: book.type=\(book.type), bookUrl=\(book.bookUrl), folderName=\(book.folderName ?? "nil")")
            }
            
            if let book = currentBook, (book.type == 1 || book.bookUrl.lowercased().hasSuffix(".epub")),
               let epubDirPath = book.folderName, !epubDirPath.isEmpty,
               let htmlPath = chapter.cachePath, !htmlPath.isEmpty {
                
                let epubDir = URL(fileURLWithPath: epubDirPath)
                let htmlURL = epubDir.appendingPathComponent(htmlPath)
                
                DebugLogger.shared.log("loadChapter: EPUB 检查路径=\(htmlURL.path), 存在=\(FileManager.default.fileExists(atPath: htmlURL.path))")
                
                if FileManager.default.fileExists(atPath: htmlURL.path) {
                    DebugLogger.shared.log("loadChapter: EPUB 提取文本 path=\(htmlURL.path)")
                    let htmlContent = try String(contentsOf: htmlURL, encoding: .utf8)
                    let textContent = HTMLToTextConverter.convert(html: htmlContent, baseURL: epubDir)
                    chapterContent = applyReplaceRulesIfNeeded(textContent, chapter: chapter)
                    chapterContentHTML = htmlContent
                    chapterHTMLURL = htmlURL
                    epubBaseURL = epubDir
                    isLoading = false
                    return
                }
            }
            
            // 尝试从缓存加载
            if let cachedContent = try? await loadCachedChapter(chapter) {
                try validateRequest()
                DebugLogger.shared.log("loadChapter: 从缓存加载成功，长度=\(cachedContent.count)")
                chapterContent = applyReplaceRulesIfNeeded(cachedContent, chapter: chapter)
                chapterContentHTML = nil
                isLoading = false
                return
            }
            
            DebugLogger.shared.log("loadChapter: 缓存未命中，尝试 fetchChapterContent")
            let content = try await fetchChapterContent(chapter)
            try validateRequest()

            if let book = currentBook, book.isLocal {
                chapterContent = applyReplaceRulesIfNeeded(content, chapter: chapter)
                chapterContentHTML = nil
                chapterHTMLURL = nil
                epubBaseURL = nil
            } else {
                chapterContentHTML = content
                let textContent = HTMLToTextConverter.convert(html: content, baseURL: nil)
                chapterContent = applyReplaceRulesIfNeeded(textContent, chapter: chapter)
                try await cacheChapter(chapter, content: textContent)
            }
            
            isLoading = false
            
            // 预加载前后章节
            if let book = currentBook {
                await cacheManager.preloadAroundChapter(
                    index: index,
                    chapters: chapters,
                    book: book
                )
            }
        } catch is CancellationError {
            if chapterLoadID == requestID { isLoading = false }
            throw CancellationError()
        } catch {
            guard chapterLoadID == requestID else { throw error }
            errorMessage = "加载章节失败：\(error.localizedDescription)"
            isLoading = false
            throw error
        }
    }
    
    // MARK: - 章节导航
    func prevChapter() async {
        guard currentChapterIndex > 0 else { return }
        readBook.moveToPrevChapter(true, upContentInPlace: false)
        currentChapterIndex = readBook.durChapterIndex
        currentChapter = chapters[safe: currentChapterIndex]
        saveProgress()
    }
    
    func nextChapter() async {
        guard currentChapterIndex < totalChapters - 1 else { return }
        readBook.moveToNextChapter(true, false)
        currentChapterIndex = readBook.durChapterIndex
        currentChapter = chapters[safe: currentChapterIndex]
        saveProgress()
    }
    
    func jumpToChapter(_ index: Int) {
        guard index >= 0 && index < totalChapters else { return }
        
        readBook.durChapterIndex = index
        readBook.durChapterPos = 0
        readBook.clearTextChapter()
        readBook.loadContent()
        currentChapterIndex = index
        currentChapter = chapters[index]
        saveProgress()
    }

    func loadChapter() async {
        do {
            try await loadChapter(at: currentChapterIndex)
        } catch {
            errorMessage = "加载章节失败：\(error.localizedDescription)"
        }
    }

    func loadChapterList() async {
        guard let book = currentBook else { return }
        do {
            try await loadChapters(book: book)
        } catch {
            errorMessage = "加载目录失败：\(error.localizedDescription)"
        }
    }
    
    // MARK: - 阅读配置
    func applyReadConfig(_ book: Book) {
        var config = book.readConfigObj

        if config.imageStyle == nil || config.imageStyle?.isEmpty == true {
            if let sourceId = UUID(uuidString: book.origin) {
                let request: NSFetchRequest<BookSource> = BookSource.fetchRequest()
                request.fetchLimit = 1
                request.predicate = NSPredicate(format: "sourceId == %@", sourceId as CVarArg)
                if let source = try? CoreDataStack.shared.viewContext.fetch(request).first {
                    var resolvedStyle = source.getContentRule()?.imageStyle
                    if (resolvedStyle == nil || resolvedStyle?.isEmpty == true), book.type == 2 {
                        resolvedStyle = ImageStyle.full.rawValue
                    }
                    if let resolvedStyle, !resolvedStyle.isEmpty {
                        config.imageStyle = resolvedStyle
                        book.readConfigObj = config
                    }
                }
            }
        }

        seedGlobalPageAnimationIfNeeded(from: config)

        // 应用主题
        applyTheme(themeFromStorage(UserDefaults.standard.string(forKey: "reader.theme") ?? "亮色"))

        useReplaceRule = config.useReplaceRule
        imageStyle = ImageStyle(rawValue: config.imageStyle ?? "") ?? .original
    }

    private func seedGlobalPageAnimationIfNeeded(from config: ReadConfig) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "pageAnimation") == nil else {
            return
        }
        defaults.set(Self.pageAnimationRawValue(from: config.pageAnim), forKey: "pageAnimation")
    }

    private static func pageAnimationRawValue(from configValue: Int32) -> Int {
        let animation = PageAnimation(rawValue: configValue) ?? .cover
        switch animation {
        case .cover:
            return PageAnimationType.cover.rawValue
        case .simulation:
            return PageAnimationType.simulation.rawValue
        case .slide:
            return PageAnimationType.slide.rawValue
        case .scroll:
            return PageAnimationType.scroll.rawValue
        }
    }
    
    func applyTheme(_ theme: ReaderTheme) {
        self.theme = theme
        backgroundColor = theme.backgroundColor
        textColor = theme.textColor

        UserDefaults.standard.set(storageThemeValue(theme), forKey: "reader.theme")
    }

    private func storageThemeValue(_ theme: ReaderTheme) -> String {
        switch theme {
        case .light:
            return "亮色"
        case .dark:
            return "暗色"
        case .sepia:
            return "羊皮纸"
        case .eyeProtection:
            return "护眼"
        }
    }

    private func applyReplaceRulesIfNeeded(_ text: String, chapter: BookChapter) -> String {
        guard let book = currentBook else { return text }
        if !useReplaceRule {
            return text
        }
        return ReplaceEngineEnhanced.shared.applyForReader(
            text: text,
            bookId: book.bookId,
            chapterId: chapter.chapterId,
            context: CoreDataStack.shared.viewContext
        )
    }

    func turnToNextPage() -> Bool {
        guard totalPages > 0 else { return false }
        guard currentPageIndex + 1 < totalPages else { return false }
        currentPageIndex += 1
        return true
    }

    func turnToPreviousPage() -> Bool {
        guard totalPages > 0 else { return false }
        guard currentPageIndex > 0 else { return false }
        currentPageIndex -= 1
        return true
    }

    private func updatePagingProgressIfNeeded() {
        let clamped = max(0, currentPageIndex)
        let newPos = Int32(clamping: clamped)
        if durChapterPos != newPos {
            durChapterPos = newPos
        }
        saveProgress()
    }

    func setTheme(_ theme: ReaderTheme) async {
        applyTheme(theme)
    }

    func setFontSize(_ size: CGFloat) async {
        let clamped = min(max(size, 8), 32)
        fontSize = clamped
    }

    func setImageStyle(_ style: ImageStyle) async {
        imageStyle = style
        guard let book = currentBook else { return }
        book.imageDisplayStyle = style.rawValue
        try? CoreDataStack.shared.save()
    }
    
    // MARK: - 缓存管理
    private func loadCachedChapter(_ chapter: BookChapter) async throws -> String {
        DebugLogger.shared.log("loadCachedChapter: chapterId=\(chapter.chapterId), isCached=\(chapter.isCached), cachePath=\(chapter.cachePath ?? "nil")")
        // 从文件系统加载缓存的章节内容
        guard chapter.isCached, let cachePath = chapter.cachePath, !cachePath.isEmpty else {
            DebugLogger.shared.log("loadCachedChapter: 章节未缓存或 cachePath 为空")
            throw ReaderError.notCached
        }
        
        let cacheURL: URL
        if cachePath.hasPrefix("/") {
            cacheURL = URL(fileURLWithPath: cachePath)
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            cacheURL = documents.appendingPathComponent("chapters").appendingPathComponent(cachePath)
        }
        
        DebugLogger.shared.log("loadCachedChapter: 检查文件路径=\(cacheURL.path)")
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            DebugLogger.shared.log("loadCachedChapter: 文件不存在")
            throw ReaderError.notCached
        }
        
        let content = try String(contentsOf: cacheURL, encoding: .utf8)
        DebugLogger.shared.log("loadCachedChapter: 加载成功，长度=\(content.count)")
        return content
    }
    
    private func fetchChapterContent(_ chapter: BookChapter) async throws -> String {
        guard let book = currentBook else {
            throw ReaderError.noBook
        }
        
        if book.isLocal {
            return try await loadLocalChapterContent(chapter)
        }
        
        return try await ChapterContentLoader.load(chapter: chapter, book: book)
    }

    /// 加载本地 TXT 书籍的章节内容
    private func loadLocalChapterContent(_ chapter: BookChapter) async throws -> String {
        guard let book = currentBook else { throw ReaderError.noBook }
        let resolvedChapter = try await resolveLocalChapter(at: Int(chapter.index), for: book)
        
        if book.isLocalEPUB {
            guard let epubDirPath = book.folderName, !epubDirPath.isEmpty,
                  let htmlPath = resolvedChapter.cachePath, !htmlPath.isEmpty else {
                throw ReaderError.notCached
            }

            let epubDir = URL(fileURLWithPath: epubDirPath)
            let htmlURL = epubDir.appendingPathComponent(htmlPath)

            DebugLogger.shared.log("EPUB 本地回退读取: bookId=\(book.bookId), chapter=\(resolvedChapter.index), path=\(htmlURL.path)")

            guard FileManager.default.fileExists(atPath: htmlURL.path) else {
                throw ReaderError.notCached
            }

            let htmlContent = try String(contentsOf: htmlURL, encoding: .utf8)
            return HTMLToTextConverter.convert(html: htmlContent, baseURL: epubDir)
        }
        
        guard let fileURL = book.localFileURL else {
            throw ReaderError.parseFailed("本地文件路径无效")
        }

        let content = try readLocalText(from: fileURL)
        let localChapters = splitLocalChapters(content: content)
        let idx = Int(resolvedChapter.index)
        guard idx >= 0 && idx < localChapters.count else { throw ReaderError.notCached }
        return localChapters[idx].content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveLocalChapter(at index: Int, for book: Book) async throws -> BookChapter {
        let resolvedChapters = try await restoreLocalChaptersIfNeeded(for: book, preferredChapterIndex: index)

        guard index >= 0 && index < resolvedChapters.count else {
            throw ReaderError.invalidChapterIndex
        }

        if currentBook?.objectID == book.objectID {
            chapters = resolvedChapters
            totalChapters = resolvedChapters.count
            currentChapter = resolvedChapters[index]
        }

        return resolvedChapters[index]
    }

    private func restoreLocalChaptersIfNeeded(for book: Book, preferredChapterIndex: Int? = nil) async throws -> [BookChapter] {
        let context = CoreDataStack.shared.viewContext
        let request = BookChapter.fetchRequest(byBookId: book.bookId)
        var storedChapters = try context.fetch(request)

        let shouldRestore: Bool = {
            if storedChapters.isEmpty {
                return true
            }

            if book.isLocalEPUB {
                if book.folderName?.isEmpty != false {
                    return true
                }

                if let epubDirPath = book.folderName,
                   !FileManager.default.fileExists(atPath: epubDirPath) {
                    return true
                }

                if let preferredChapterIndex {
                    guard preferredChapterIndex >= 0, preferredChapterIndex < storedChapters.count else {
                        return true
                    }

                    guard let cachePath = storedChapters[preferredChapterIndex].cachePath,
                          !cachePath.isEmpty,
                          let epubDirPath = book.folderName else {
                        return true
                    }

                    let chapterURL = URL(fileURLWithPath: epubDirPath).appendingPathComponent(cachePath)
                    return !FileManager.default.fileExists(atPath: chapterURL.path)
                }
            }

            return false
        }()

        guard shouldRestore else {
            return storedChapters
        }

        guard let fileURL = book.localFileURL else {
            throw ReaderError.parseFailed("本地文件路径无效")
        }

        for storedChapter in storedChapters {
            context.delete(storedChapter)
        }

        if book.isLocalEPUB {
            let epubBook = try EPUBParser.parseSync(file: fileURL, bookId: book.bookId)
            book.name = epubBook.title
            book.author = epubBook.author
            book.totalChapterNum = Int32(epubBook.chapters.count)
            book.folderName = epubBook.epubDirectory.path

            if (book.intro?.isEmpty ?? true), let description = epubBook.metadata.description {
                book.intro = description
            }

            // 将扩展元数据落到 Book.extraMetadata 供详情页展示
            let md = epubBook.metadata
            var extra = ExtraBookMetadata()
            extra.translator = md.translator
            extra.publisher = md.publisher
            extra.publishDate = md.date
            extra.language = md.language
            extra.isbn = md.isbn ?? md.identifier
            extra.series = md.series
            extra.subjects = md.subjects.isEmpty ? nil : md.subjects
            extra.rights = md.rights
            if extra.hasAnyField {
                book.extraMetadata = extra
            }

            if book.durChapterTitle?.isEmpty ?? true {
                book.durChapterTitle = epubBook.chapters.first?.title
            }

            for chapter in epubBook.chapters {
                let chapterObj = BookChapter.create(
                    in: context,
                    bookId: book.bookId,
                    url: chapter.href,
                    index: Int32(chapter.index),
                    title: chapter.title
                )
                chapterObj.book = book
                chapterObj.isCached = true
                chapterObj.cachePath = chapter.htmlPath
            }
        } else {
            let content = try readLocalText(from: fileURL)
            let parsedChapters = splitLocalChapters(content: content)
            book.totalChapterNum = Int32(parsedChapters.count)

            if book.durChapterTitle?.isEmpty ?? true {
                book.durChapterTitle = parsedChapters.first?.title
            }

            for (index, parsedChapter) in parsedChapters.enumerated() {
                let chapterObj = BookChapter.create(
                    in: context,
                    bookId: book.bookId,
                    url: "local:\(index)",
                    index: Int32(index),
                    title: parsedChapter.title
                )
                chapterObj.book = book
                chapterObj.wordCount = Int32(parsedChapter.content.count)
                chapterObj.isCached = true
            }
        }

        try CoreDataStack.shared.save()
        context.refresh(book, mergeChanges: true)
        storedChapters = try context.fetch(request)
        return storedChapters
    }

    private func readLocalText(from fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)

        if data.starts(with: [0xEF, 0xBB, 0xBF]), let text = String(data: data, encoding: .utf8) {
            return text
        }

        if data.starts(with: [0xFF, 0xFE]), let text = String(data: data, encoding: .utf16LittleEndian) {
            return text
        }

        if data.starts(with: [0xFE, 0xFF]), let text = String(data: data, encoding: .utf16BigEndian) {
            return text
        }

        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        if let text = String(data: data, encoding: .utf16) {
            return text
        }

        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )

        if let text = String(data: data, encoding: gb18030) {
            return text
        }

        throw ReaderError.parseFailed("无法识别 TXT 编码")
    }

    private func splitLocalChapters(content: String) -> [(title: String, content: String)] {
        let chapterPatterns = [
            #"^第[零一二三四五六七八九十百千万0-9]+[章回卷节部篇]"#,
            #"^第[0-9]+章"#,
            #"^Chapter [0-9]+"#,
            #"^\s*第[0-9一二三四五六七八九十]+节"#
        ]

        var parsedChapters: [(title: String, content: String)] = []
        var currentTitle: String?
        var currentContent = ""

        for line in content.components(separatedBy: .newlines) {
            var isChapterStart = false

            for pattern in chapterPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
                    let range = NSRange(line.startIndex..., in: line)
                    if regex.firstMatch(in: line, range: range) != nil {
                        isChapterStart = true
                        break
                    }
                }
            }

            if isChapterStart {
                if let title = currentTitle, !currentContent.isEmpty {
                    parsedChapters.append((title, currentContent.trimmingCharacters(in: .whitespacesAndNewlines)))
                }

                currentTitle = line.trimmingCharacters(in: .whitespacesAndNewlines)
                currentContent = ""
            } else {
                currentContent += line + "\n"
            }
        }

        if let title = currentTitle {
            parsedChapters.append((title, currentContent.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        if parsedChapters.isEmpty {
            return [("第一章", content)]
        }

        return parsedChapters
    }
    
    private func cacheChapter(_ chapter: BookChapter, content: String) async throws {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let chapterDir = documents.appendingPathComponent("chapters", isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: chapterDir.path) {
            try FileManager.default.createDirectory(at: chapterDir, withIntermediateDirectories: true)
        }
        
        let fileName = "\(chapter.bookId.uuidString)_\(chapter.index).txt"
        let fileURL = chapterDir.appendingPathComponent(fileName)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        
        chapter.isCached = true
        chapter.cachePath = fileName
        try? CoreDataStack.shared.save()
    }
    
    // MARK: - 保存进度
    func saveProgress() {
        guard let book = currentBook else { return }
        
        book.durChapterIndex = Int32(clamping: max(0, currentChapterIndex))
        book.durChapterTime = Int64(Date().timeIntervalSince1970)
        book.durChapterPos = durChapterPos
        
        if let chapter = currentChapter {
            book.durChapterTitle = chapter.title
        }
        
        try? CoreDataStack.shared.save()
    }

    func saveReadingProgress() async {
        saveProgress()
    }
    
}

extension ReaderViewModel {
    var currentContent: String? {
        get { chapterContent }
        set { chapterContent = newValue }
    }

    var chapterList: [BookChapter] {
        chapters
    }
}

enum ReaderError: LocalizedError {
    case noChapters
    case invalidChapterIndex
    case notCached
    case networkFailure
    case noBook
    case noSource
    case parseFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noChapters: return "没有章节"
        case .invalidChapterIndex: return "无效的章节索引"
        case .notCached: return "章节未缓存"
        case .networkFailure: return "网络加载失败"
        case .noBook: return "未找到书籍"
        case .noSource: return "未找到书源"
        case .parseFailed(let reason): return "解析失败：\(reason)"
        }
    }
}
struct ReaderSettingsView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("字体")) {
                    Stepper("字号：\(Int(viewModel.fontSize))", value: $viewModel.fontSize, in: 12...32, step: 1)
                }
                
                Section(header: Text("间距")) {
                    Stepper("行距：\(Int(viewModel.lineSpacing))", value: $viewModel.lineSpacing, in: 4...20, step: 1)
                }

                Section(header: Text("图片")) {
                    Picker("图片样式", selection: Binding(
                        get: { viewModel.imageStyle },
                        set: { newValue in
                            Task { await viewModel.setImageStyle(newValue) }
                        }
                    )) {
                        ForEach(ImageStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                }
                
                Section(header: Text("主题")) {
                    Button("亮色") {
                        viewModel.applyTheme(.light)
                    }
                    
                    Button("暗色") {
                        viewModel.applyTheme(.dark)
                    }
                    
                    Button("护眼") {
                        viewModel.applyTheme(.eyeProtection)
                    }
                    
                    Button("羊皮纸") {
                        viewModel.applyTheme(.sepia)
                    }
                }
            }
            .navigationTitle("阅读设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
