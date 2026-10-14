//
//  Book+CoreDataClass.swift
//  Legado-iOS
//
//  书籍实体
//

import Foundation
import CoreData

@objc(Book)
public class Book: NSManagedObject {
    // MARK: - 基本信息
    @NSManaged public var bookId: UUID
    @NSManaged public var name: String
    @NSManaged public var author: String
    @NSManaged public var kind: String?
    @NSManaged public var coverUrl: String?
    @NSManaged public var intro: String?
    
    // MARK: - 书源相关
    @NSManaged public var bookUrl: String
    @NSManaged public var tocUrl: String
    @NSManaged public var origin: String
    @NSManaged public var originName: String
    
    // MARK: - 最新章节
    @NSManaged public var latestChapterTitle: String?
    @NSManaged public var latestChapterTime: Int64
    @NSManaged public var lastCheckTime: Int64
    @NSManaged public var lastCheckCount: Int32
    @NSManaged public var totalChapterNum: Int32
    
    // MARK: - 阅读进度
    @NSManaged public var durChapterTitle: String?
    @NSManaged public var durChapterIndex: Int32
    @NSManaged public var durChapterPos: Int32
    @NSManaged public var durChapterTime: Int64
    
    // MARK: - 书架管理
    @NSManaged public var canUpdate: Bool
    @NSManaged public var order: Int32
    @NSManaged public var originOrder: Int32
    @NSManaged public var customTag: String?
    @NSManaged public var group: Int64
    
    // MARK: - 用户定制
    @NSManaged public var customCoverUrl: String?
    @NSManaged public var customIntro: String?
    
    // MARK: - 书籍类型
    @NSManaged public var type: Int32  // 0=文本，1=音频，2=图片
    
    // MARK: - 统计信息
    @NSManaged public var wordCount: String?
    
    // MARK: - 配置
    @NSManaged public var variable: String?
    @NSManaged public var charset: String?
    @NSManaged public var readConfigData: Data?
    
    // MARK: - 缓存 (@Ignore 在 Android 中)
    @NSManaged public var infoHtml: String?
    @NSManaged public var tocHtml: String?
    @NSManaged public var downloadUrls: String?
    @NSManaged public var folderName: String?
    @NSManaged public var extraMetadataJson: String?
    
    // MARK: - 系统字段
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var syncTime: Int64
    
    // MARK: - 关系
    @NSManaged public var chapters: NSSet?
    @NSManaged public var source: BookSource?
    @NSManaged public var bookmarks: NSSet?
}

// MARK: - Fetch Request
extension Book {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Book> {
        return NSFetchRequest<Book>(entityName: "Book")
    }
}

// MARK: - 计算属性
extension Book {
    var displayName: String { name }
    
    var displayAuthor: String { author }
    
    var displayCoverUrl: String? {
        customCoverUrl ?? coverUrl
    }
    
    var displayIntro: String? {
        customIntro ?? intro
    }
    
    var lastReadDate: Date { Date(timeIntervalSince1970: TimeInterval(durChapterTime)) }
    
    var readProgress: Double {
        guard totalChapterNum > 0 else { return 0 }
        return Double(durChapterIndex) / Double(totalChapterNum)
    }

    var normalizedOrigin: String {
        origin.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var localFileURL: URL? {
        let raw = bookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        if let url = URL(string: raw), url.scheme != nil {
            return url.isFileURL ? url : nil
        }

        let file = URL(fileURLWithPath: raw)
        if isLocal, file.deletingLastPathComponent().lastPathComponent == "LocalBooks",
           !FileManager.default.fileExists(atPath: file.path) {
            // 覆盖安装或设备迁移后，正文跟随当前应用的数据目录读取。
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LocalBooks", isDirectory: true).appendingPathComponent(file.lastPathComponent)
        }
        return file
    }
    
    var isLocal: Bool {
        if ["local", "本地文件"].contains(normalizedOrigin) {
            return true
        }

        if originName.trimmingCharacters(in: .whitespacesAndNewlines) == "本地文件" {
            return true
        }

        return bookUrl.hasPrefix("file://") || bookUrl.hasPrefix("/")
    }

    var isLocalEPUB: Bool {
        guard isLocal else { return false }
        return type == 1 || localFileURL?.pathExtension.lowercased() == "epub"
    }

    /// 精装书：富样式 EPUB，走 WebView 渲染路径保持原书 CSS/字体
    /// 当前简化为 isLocalEPUB（EPUB 自带 CSS/字体时 WebView 天然保真；
    /// 无 CSS 也不影响 — WebView 仍以默认样式渲染，优于自绘退化）
    var isHardcover: Bool {
        isLocalEPUB
    }
    
    var unreadChapterNum: Int {
        max(0, Int(totalChapterNum) - Int(durChapterIndex) - 1)
    }
    
    var lastChapterIndex: Int {
        max(0, Int(totalChapterNum) - 1)
    }
    
    var realAuthor: String {
        author.trimmingCharacters(in: .whitespaces)
    }
    
    var chapterSize: Int {
        return Int(totalChapterNum)
    }
    
    var pageAnim: Int {
        return Int(pageAnimation)
    }
}

// MARK: - ReadConfig 访问器
extension Book {
    var readConfigObj: ReadConfig {
        get {
            if let data = readConfigData,
               let config = try? JSONDecoder().decode(ReadConfig.self, from: data) {
                return config
            }
            return ReadConfig()
        }
        set {
            readConfigData = try? JSONEncoder().encode(newValue)
        }
    }
    
    var isReverseToc: Bool {
        get { readConfigObj.reverseToc }
        set {
            var config = readConfigObj
            config.reverseToc = newValue
            readConfigObj = config
        }
    }
    
    var pageAnimation: Int32 {
        get { readConfigObj.pageAnim }
        set {
            var config = readConfigObj
            config.pageAnim = newValue
            readConfigObj = config
        }
    }
    
    var imageDisplayStyle: String? {
        get { readConfigObj.imageStyle }
        set {
            var config = readConfigObj
            config.imageStyle = newValue
            readConfigObj = config
        }
    }
}

// MARK: - 初始化
extension Book {
    static func create(in context: NSManagedObjectContext) -> Book {
        let entity = NSEntityDescription.entity(forEntityName: "Book", in: context)!
        let book = Book(entity: entity, insertInto: context)
        book.bookId = UUID()
        book.createdAt = Date()
        book.updatedAt = Date()
        book.durChapterTime = Int64(Date().timeIntervalSince1970)
        book.canUpdate = true
        book.order = 0
        book.group = 0
        book.syncTime = 0
        book.type = 0  // 默认文本
        return book
    }
}

extension Book: Identifiable {
    public var id: UUID { bookId }
}
