import Foundation
import CoreData

struct BookAPI {
    
    static func getBookshelf() -> APIResponse {
        let context = CoreDataStack.shared.viewContext
        let fetchRequest: NSFetchRequest<Book> = Book.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "durChapterTime", ascending: false)]
        
        do {
            let books = try context.fetch(fetchRequest)
            if books.isEmpty {
                return .error("还没有添加小说")
            }
            let dataArray = books.map { encodeBook($0) }
            return .success(.array(dataArray))
        } catch {
            return .error("获取书架失败: \(error.localizedDescription)")
        }
    }
    
    static func saveBook(_ body: String?) async -> APIResponse {
        guard let body = body, !body.isEmpty else {
            return .error("数据不能为空")
        }
        
        guard let data = body.data(using: .utf8) else {
            return .error("数据格式错误")
        }
        
        do {
            let decoder = JSONDecoder()
            let json = try decoder.decode(APIBookJSON.self, from: data)
            
            let context = CoreDataStack.shared.viewContext
            let book = Book.create(in: context)
            applyJSONToBook(json, book)
            try context.save()
            
            return .success(.string(""))
        } catch {
            return .error("保存书籍失败: \(error.localizedDescription)")
        }
    }
    
    static func deleteBook(_ body: String?) -> APIResponse {
        guard let body = body, !body.isEmpty else {
            return .error("数据不能为空")
        }
        
        guard let data = body.data(using: .utf8) else {
            return .error("数据格式错误")
        }
        
        do {
            let decoder = JSONDecoder()
            let json = try decoder.decode(APIBookJSON.self, from: data)
            
            let context = CoreDataStack.shared.viewContext
            let fetchRequest: NSFetchRequest<Book> = Book.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "bookUrl == %@", json.bookUrl)
            fetchRequest.fetchLimit = 1
            
            guard let book = try context.fetch(fetchRequest).first else {
                return .error("未找到书籍")
            }
            
            context.delete(book)
            try context.save()
            
            return .success(.string(""))
        } catch {
            return .error("删除书籍失败: \(error.localizedDescription)")
        }
    }
    
    static func saveBookProgress(_ body: String?) async -> APIResponse {
        guard let body = body, !body.isEmpty else {
            return .error("数据不能为空")
        }
        
        guard let data = body.data(using: .utf8) else {
            return .error("数据格式错误")
        }
        
        do {
            let decoder = JSONDecoder()
            let progress = try decoder.decode(BookProgressJSON.self, from: data)
            
            let context = CoreDataStack.shared.viewContext
            let fetchRequest: NSFetchRequest<Book> = Book.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "name == %@ AND author == %@", progress.name, progress.author)
            fetchRequest.fetchLimit = 1
            
            guard let book = try context.fetch(fetchRequest).first else {
                return .error("未找到书籍")
            }
            
            book.durChapterIndex = Int32(clamping: max(0, progress.durChapterIndex))
            book.durChapterPos = Int32(clamping: max(0, progress.durChapterPos))
            book.durChapterTitle = progress.durChapterTitle
            book.durChapterTime = Int64(progress.durChapterTime)
            
            try context.save()
            
            return .success(.string(""))
        } catch {
            return .error("保存进度失败: \(error.localizedDescription)")
        }
    }
    
    static func getChapterList(_ query: [String: String]) -> APIResponse {
        guard let bookUrl = query["url"], !bookUrl.isEmpty else {
            return .error("参数url不能为空，请指定书籍地址")
        }
        
        let context = CoreDataStack.shared.viewContext
        let fetchRequest: NSFetchRequest<BookChapter> = BookChapter.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "bookUrl == %@", bookUrl)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "index", ascending: true)]
        
        do {
            let chapters = try context.fetch(fetchRequest)
            if chapters.isEmpty {
                return refreshToc(query)
            }
            let dataArray = chapters.map { encodeChapter($0) }
            return .success(.array(dataArray))
        } catch {
            return .error("获取目录失败: \(error.localizedDescription)")
        }
    }
    
    static func getBookContent(_ query: [String: String]) -> APIResponse {
        guard let bookUrl = query["url"], !bookUrl.isEmpty else {
            return .error("参数url不能为空，请指定书籍地址")
        }
        
        guard let indexStr = query["index"], let index = Int(indexStr) else {
            return .error("参数index不能为空，请指定目录序号")
        }
        
        let context = CoreDataStack.shared.viewContext
        
        let bookFetchRequest: NSFetchRequest<Book> = Book.fetchRequest()
        bookFetchRequest.predicate = NSPredicate(format: "bookUrl == %@", bookUrl)
        bookFetchRequest.fetchLimit = 1
        
        let chapterFetchRequest: NSFetchRequest<BookChapter> = BookChapter.fetchRequest()
        chapterFetchRequest.predicate = NSPredicate(format: "bookUrl == %@ AND index == %d", bookUrl, index)
        chapterFetchRequest.fetchLimit = 1
        
        do {
            guard let book = try context.fetch(bookFetchRequest).first else {
                return .error("未找到书籍")
            }
            
            guard let chapter = try context.fetch(chapterFetchRequest).first else {
                return .error("未找到章节")
            }
            
            if let cachePath = chapter.cachePath {
                if let cachedContent = try? String(contentsOfFile: cachePath, encoding: .utf8) {
                    return .success(.string(cachedContent))
                }
            }
            
            return .error("章节内容未缓存，请先下载")
        } catch {
            return .error("获取内容失败: \(error.localizedDescription)")
        }
    }
    
    static func refreshToc(_ query: [String: String]) -> APIResponse {
        guard let bookUrl = query["url"], !bookUrl.isEmpty else {
            return .error("参数url不能为空，请指定书籍地址")
        }
        
        let context = CoreDataStack.shared.viewContext
        let bookFetchRequest: NSFetchRequest<Book> = Book.fetchRequest()
        bookFetchRequest.predicate = NSPredicate(format: "bookUrl == %@", bookUrl)
        bookFetchRequest.fetchLimit = 1
        
        guard let book = try? context.fetch(bookFetchRequest).first else {
            return .error("未找到书籍")
        }
        
        guard let source = book.source else {
            return .error("书籍无书源")
        }
        
        Task { @MainActor in
            do {
                let service = TableOfContentsService.shared
                let chapters = try await service.refreshTableOfContents(book: book, source: source)
                DebugLogger.shared.log("刷新目录成功: \(chapters.count) 章")
            } catch {
                DebugLogger.shared.log("刷新目录失败: \(error.localizedDescription)")
            }
        }
        
        return .success(.string("正在刷新目录"))
    }
    
    static func getCover(_ query: [String: String]) -> APIResponse {
        guard let path = query["path"], !path.isEmpty else {
            return .error("参数path不能为空")
        }
        
        var coverPath = path
        
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            Task {
                if let url = URL(string: path) {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                            .appendingPathComponent("covers", isDirectory: true) else { return }
                        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                        
                        let fileName = path.md5()
                        let fileURL = cacheDir.appendingPathComponent(fileName)
                        try data.write(to: fileURL)
                        DebugLogger.shared.log("封面下载成功: \(fileURL.path)")
                    } catch {
                        DebugLogger.shared.log("封面下载失败: \(error.localizedDescription)")
                    }
                }
            }
            return .success(.string(path))
        }
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) {
            return .success(.string(path))
        }
        
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return .error("无法访问文档目录") }
        let fullPath = documentsPath.appendingPathComponent(path).path
        if fileManager.fileExists(atPath: fullPath) {
            return .success(.string(fullPath))
        }
        
        return .error("封面文件不存在")
    }
    
    private static func encodeBook(_ book: Book) -> CodableValue {
        var dict: [String: CodableValue] = [:]
        dict["bookUrl"] = .string(book.bookUrl)
        dict["tocUrl"] = .string(book.tocUrl)
        dict["name"] = .string(book.name)
        dict["author"] = .string(book.author)
        dict["kind"] = .string(book.kind ?? "")
        dict["intro"] = .string(book.intro ?? "")
        dict["coverUrl"] = .string(book.coverUrl ?? "")
        dict["customCoverUrl"] = .string(book.customCoverUrl ?? "")
        dict["group"] = .int(Int(book.group))
        dict["durChapterIndex"] = .int(Int(book.durChapterIndex))
        dict["durChapterPos"] = .int(Int(book.durChapterPos))
        dict["durChapterTitle"] = .string(book.durChapterTitle ?? "")
        dict["durChapterTime"] = .int(Int(book.durChapterTime))
        dict["latestChapterTitle"] = .string(book.latestChapterTitle ?? "")
        dict["latestChapterTime"] = .int(Int(book.latestChapterTime))
        dict["totalChapterNum"] = .int(Int(book.totalChapterNum))
        dict["origin"] = .string(book.origin ?? "")
        dict["originName"] = .string(book.originName ?? "")
        dict["canUpdate"] = .bool(book.canUpdate)
        dict["order"] = .int(Int(book.order))
        return .dictionary(dict)
    }
    
    private static func encodeChapter(_ chapter: BookChapter) -> CodableValue {
        var dict: [String: CodableValue] = [:]
        dict["chapterUrl"] = .string(chapter.chapterUrl)
        dict["title"] = .string(chapter.title)
        dict["index"] = .int(Int(chapter.index))
        dict["isVip"] = .bool(chapter.isVIP)
        dict["isPay"] = .bool(chapter.isPay)
        dict["tag"] = .string(chapter.tag ?? "")
        dict["isCached"] = .bool(chapter.isCached)
        return .dictionary(dict)
    }
    
    private static func applyJSONToBook(_ json: APIBookJSON, _ book: Book) {
        book.bookUrl = json.bookUrl
        book.tocUrl = json.tocUrl ?? ""
        book.name = json.name
        book.author = json.author ?? ""
        book.kind = json.kind ?? ""
        book.intro = json.intro ?? ""
        book.coverUrl = json.coverUrl ?? ""
        book.customCoverUrl = json.customCover ?? ""
        book.group = Int64(json.group ?? 0)
        book.durChapterIndex = Int32(clamping: json.durChapterIndex ?? 0)
        book.durChapterPos = Int32(clamping: json.durChapterPos ?? 0)
        book.durChapterTitle = json.durChapterTitle ?? ""
        book.durChapterTime = Int64(json.durChapterTime ?? 0)
        book.latestChapterTitle = json.latestChapterTitle ?? ""
        book.latestChapterTime = Int64(json.latestChapterTime ?? 0)
        book.totalChapterNum = Int32(clamping: json.totalChapterNum ?? 0)
        book.origin = json.origin ?? ""
        book.originName = json.originName ?? ""
        book.canUpdate = json.canUpdate ?? true
        book.order = Int32(clamping: json.order ?? 0)
    }
}

private struct APIBookJSON: Codable {
    let bookUrl: String
    let tocUrl: String?
    let name: String
    let author: String?
    let kind: String?
    let intro: String?
    let coverUrl: String?
    let customCover: String?
    let group: Int?
    let durChapterIndex: Int?
    let durChapterPos: Int?
    let durChapterTitle: String?
    let durChapterTime: Int?
    let latestChapterTitle: String?
    let latestChapterTime: Int?
    let totalChapterNum: Int?
    let origin: String?
    let originName: String?
    let canUpdate: Bool?
    let order: Int?
}

private struct BookProgressJSON: Codable {
    let name: String
    let author: String
    let durChapterIndex: Int
    let durChapterPos: Int
    let durChapterTitle: String
    let durChapterTime: Int
}
