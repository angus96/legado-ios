//
//  ReadBook.swift
//  Legado
//
//  基于 Android Legado 原版 ReadBook.kt 移植
//  原版路径: app/src/main/java/io/legado/app/model/ReadBook.kt
//

import Foundation
import CoreData

@MainActor
protocol ReadBookCallBack: AnyObject {
    func upContent()
    func upMenuView()
    func upPageAnim()
}

@MainActor
class ReadBook: ObservableObject {
    static let shared = ReadBook()
    
    @Published var book: Book?
    weak var callBack: ReadBookCallBack?
    var inBookshelf = false
    
    var chapterSize: Int = 0
    var simulatedChapterSize: Int = 0
    @Published var durChapterIndex: Int = 0
    @Published var durChapterPos: Int = 0
    var isLocalBook = true
    var chapterChanged = false
    
    var prevTextChapter: TextChapter?
    var curTextChapter: TextChapter?
    var nextTextChapter: TextChapter?
    
    var bookSource: BookSource?
    
    var msg: String?
    
    private var loadGeneration = UUID()
    private var loadingChapters: Set<Int> = []
    private var chapterLoadingTasks: [Int: Task<Void, Never>] = [:]
    
    var readStartTime: Date = Date()
    
    private init() {}
    
    func resetData(_ book: Book) {
        releaseAndCancel()
        self.book = book
        chapterSize = book.chapterSize
        simulatedChapterSize = chapterSize
        durChapterIndex = Int(book.durChapterIndex)
        durChapterPos = Int(book.durChapterPos)
        isLocalBook = book.isLocal
        clearTextChapter()
        callBack?.upContent()
        callBack?.upMenuView()
        callBack?.upPageAnim()
        upBookSource(book)
        loadingChapters.removeAll()
    }
    
    func upData(_ book: Book) {
        releaseAndCancel()
        self.book = book
        chapterSize = book.chapterSize
        simulatedChapterSize = chapterSize
        
        if durChapterIndex != Int(book.durChapterIndex) {
            durChapterIndex = Int(book.durChapterIndex)
            durChapterPos = Int(book.durChapterPos)
            clearTextChapter()
        }
        
        if curTextChapter?.isCompleted == false {
            curTextChapter = nil
        }
        if nextTextChapter?.isCompleted == false {
            nextTextChapter = nil
        }
        if prevTextChapter?.isCompleted == false {
            prevTextChapter = nil
        }
        
        callBack?.upMenuView()
        upBookSource(book)
        loadingChapters.removeAll()
    }
    
    private func upBookSource(_ book: Book) {
        if book.isLocal {
            bookSource = nil
        } else {
            bookSource = try? BookSourceResolver.resolve(for: book)
        }
    }
    
    func clearTextChapter() {
        prevTextChapter = nil
        curTextChapter = nil
        nextTextChapter = nil
    }
    
    func releaseAndCancel() {
        loadGeneration = UUID()
        for (_, task) in chapterLoadingTasks {
            task.cancel()
        }
        chapterLoadingTasks.removeAll()
        loadingChapters.removeAll()
    }
    
    func loadContent(resetPageOffset: Bool = true) {
        guard let book else { return }
        releaseAndCancel()
        chapterSize = max(0, Int(book.totalChapterNum))
        guard chapterSize > 0 else { return }
        durChapterIndex = min(max(0, durChapterIndex), chapterSize - 1)
        if resetPageOffset { durChapterPos = 0 }
        msg = nil
        let current = durChapterIndex
        let generation = loadGeneration
        for index in max(0, current - 1)...min(chapterSize - 1, current + 1) {
            loadingChapters.insert(index)
            chapterLoadingTasks[index] = Task { [weak self] in
                guard let self else { return }
                do {
                    let chapter = try await loadChapter(index: index, book: book)
                    try Task.checkCancellation()
                    guard loadGeneration == generation, self.book?.objectID == book.objectID else { return }
                    if index == current { curTextChapter = chapter }
                    else if index < current { prevTextChapter = chapter }
                    else { nextTextChapter = chapter }
                    loadingChapters.remove(index)
                    chapterLoadingTasks[index] = nil
                    callBack?.upContent()
                    callBack?.upMenuView()
                } catch {
                    guard loadGeneration == generation, !Task.isCancelled else { return }
                    if index == current { msg = "加载失败：\(error.localizedDescription)" }
                    loadingChapters.remove(index)
                    chapterLoadingTasks[index] = nil
                    callBack?.upContent()
                }
            }
        }
    }

    private func loadChapter(index: Int, book: Book) async throws -> TextChapter {
        guard let context = book.managedObjectContext else { throw ManagedObjectAccessError.unavailable }
        
        let chapter: BookChapter = try await context.perform {
            let request: NSFetchRequest<BookChapter> = BookChapter.fetchRequest()
            request.predicate = NSPredicate(format: "bookId == %@ AND index == %d", book.bookId as CVarArg, index)
            request.fetchLimit = 1
            
            guard let chapter = try context.fetch(request).first else {
                throw NSError(domain: "ReadBook", code: 404, userInfo: [NSLocalizedDescriptionKey: "章节不存在"])
            }
            return chapter
        }
        
        let title = chapter.title
        let content = try await getChapterContent(chapter: chapter, book: book)
        
        let textChapter = TextChapter(
            chapter: chapter,
            position: index,
            title: title,
            chaptersSize: chapterSize,
            sameTitleRemoved: false,
            isVip: false,
            isPay: false,
            effectiveReplaceRules: nil
        )
        
        let bookContent = BookContent(textList: content)
        
        let layout = TextChapterLayout(textChapter: textChapter, textPages: [], book: book, bookContent: bookContent)
        await layout.startLayout()
        try Task.checkCancellation()
        if let error = layout.exception { throw error }
        return textChapter
    }

    private func getChapterContent(chapter: BookChapter, book: Book) async throws -> [String] {
        let content = try await ChapterContentLoader.load(chapter: chapter, book: book)
        try Task.checkCancellation()
        let replaced = ReplaceEngineEnhanced.shared.applyForReader(text: content, bookId: book.bookId,
                                                                   chapterId: chapter.chapterId,
                                                                   context: book.managedObjectContext ?? CoreDataStack.shared.viewContext)
        return replaced.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    func setPageIndex(_ index: Int) {
        durChapterPos = index
        callBack?.upContent()
    }
    
    func moveToNextChapter(_ upContent: Bool, _ upContentInPlace: Bool) {
        guard durChapterIndex < chapterSize - 1 else { return }
        durChapterIndex += 1
        durChapterPos = 0
        chapterChanged = true
        
        prevTextChapter = curTextChapter
        curTextChapter = nextTextChapter
        nextTextChapter = nil
        
        if upContent {
            loadContent(resetPageOffset: !upContentInPlace)
        }
        
        saveReadProgress()
    }
    
    func moveToPrevChapter(_ upContent: Bool, upContentInPlace: Bool) {
        guard durChapterIndex > 0 else { return }
        durChapterIndex -= 1
        durChapterPos = 0
        chapterChanged = true
        
        nextTextChapter = curTextChapter
        curTextChapter = prevTextChapter
        prevTextChapter = nil
        
        if upContent {
            loadContent(resetPageOffset: !upContentInPlace)
        }
        
        saveReadProgress()
    }
    
    func pageAnim() -> Int {
        return book?.pageAnim ?? 0
    }
    
    func saveReadProgress() {
        guard let book = book else { return }
        guard let context = book.managedObjectContext else { return }
        let index = Int32(clamping: max(0, durChapterIndex))
        let position = Int32(clamping: max(0, durChapterPos))
        let origin = book.origin
        let bookURL = book.bookUrl
        context.perform {
            guard !book.isDeleted, book.origin == origin, book.bookUrl == bookURL else { return }
            book.durChapterIndex = index
            book.durChapterPos = position
            book.durChapterTime = Int64(Date().timeIntervalSince1970)
            book.updatedAt = Date()
            
            do {
                try context.save()
            } catch {
                print("保存进度失败: \(error)")
            }
        }
    }
    
    var currentChapter: TextChapter? {
        return curTextChapter
    }
    
    var prevChapter: TextChapter? {
        return prevTextChapter
    }
    
    var nextChapter: TextChapter? {
        return nextTextChapter
    }
    
    func hasPrevChapter() -> Bool {
        return durChapterIndex > 0
    }
    
    func hasNextChapter() -> Bool {
        return durChapterIndex < chapterSize - 1
    }
}

// MARK: - PageDataSource conformance
extension ReadBook: PageDataSource {
    var pageIndex: Int { durChapterPos }
}
