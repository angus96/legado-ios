import Foundation
import CoreData

/// 处理后的书籍内容结构
/// 一比一移植自 Android Legado BookContent (ContentProcessor.kt line 99-206)
struct ProcessedContent {
    let sameTitleRemoved: Bool
    let contents: [String]
    let effectiveReplaceRules: [ReplaceRule]?
}

@MainActor
class ContentProcessor {
    
    private static var processors: [String: WeakReference<ContentProcessor>] = [:]
    private static let lock = NSLock()
    
    static func get(book: Book) -> ContentProcessor {
        return get(bookName: book.name, bookOrigin: book.origin)
    }
    
    static func get(bookName: String, bookOrigin: String) -> ContentProcessor {
        let key = bookName + bookOrigin
        Self.lock.lock()
        defer { Self.lock.unlock() }
        
        if let weakRef = Self.processors[key], let processor = weakRef.value {
            return processor
        }
        
        let processor = ContentProcessor(bookName: bookName, bookOrigin: bookOrigin)
        Self.processors[key] = WeakReference(value: processor)
        return processor
    }
    
    static func upReplaceRules() {
        Self.lock.lock()
        let processorRefs = Array(Self.processors.values)
        Self.lock.unlock()
        
        for weakRef in processorRefs {
            weakRef.value?.upReplaceRules()
        }
    }
    
    private let bookName: String
    private let bookOrigin: String
    
    private var titleReplaceRules: [ReplaceRule] = []
    private var contentReplaceRules: [ReplaceRule] = []
    var removeSameTitleCache: Set<String> = []
    
    private init(bookName: String, bookOrigin: String) {
        self.bookName = bookName
        self.bookOrigin = bookOrigin
        upReplaceRules()
        upRemoveSameTitle()
    }
    
    func upReplaceRules() {
        let context = CoreDataStack.shared.viewContext
        
        let titleRequest: NSFetchRequest<ReplaceRule> = ReplaceRule.fetchRequest()
        titleRequest.predicate = NSPredicate(format: "enabled == YES AND (scope IS NULL OR scope == '' OR scope CONTAINS[cd] %@ OR scope CONTAINS[cd] %@)", bookName, bookOrigin)
        titleReplaceRules = (try? context.fetch(titleRequest)) ?? []
        
        let contentRequest: NSFetchRequest<ReplaceRule> = ReplaceRule.fetchRequest()
        contentRequest.predicate = NSPredicate(format: "enabled == YES AND (scope IS NIL OR scope == '' OR scope CONTAINS[cd] %@ OR scope CONTAINS[cd] %@)", bookName, bookOrigin)
        contentReplaceRules = (try? context.fetch(contentRequest)) ?? []
    }
    
    private func upRemoveSameTitle() {
        let context = CoreDataStack.shared.viewContext
        let request: NSFetchRequest<Book> = Book.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@ AND origin == %@", bookName, bookOrigin)
        request.fetchLimit = 1
        
        guard let book = try? context.fetch(request).first else { return }
        
        removeSameTitleCache.removeAll()
        let files = BookHelp.getChapterFiles(book).filter { $0.hasSuffix("nr") }
        removeSameTitleCache = Set(files)
    }
    
    func getTitleReplaceRules() -> [ReplaceRule] {
        return titleReplaceRules
    }
    
    func getContentReplaceRules() -> [ReplaceRule] {
        return contentReplaceRules
    }
    
    func getContent(
        book: Book,
        chapter: BookChapter,
        content: String,
        includeTitle: Bool = true,
        useReplace: Bool = true,
        chineseConvert: Bool = true,
        reSegment: Bool = true
    ) -> ProcessedContent {
        var mContent = content
        var sameTitleRemoved = false
        var effectiveReplaceRules: [ReplaceRule]? = nil
        
        if content != "null" {
            let fileName = chapter.getFileName("nr")
            
            if !removeSameTitleCache.contains(fileName) {
                do {
                    let name = Pattern.quote(book.name)
                    var title = chapter.title.escapeRegex().replacingOccurrences(of: "\\s+", with: "\\s*", options: .regularExpression)
                    
                    let pattern1 = "^(\\s|\\p{P}|\(name))*\(title)(\\s)*"
                    if let regex = try? NSRegularExpression(pattern: pattern1, options: [.caseInsensitive]) {
                        let range = NSRange(mContent.startIndex..., in: mContent)
                        if let match = regex.firstMatch(in: mContent, options: [], range: range) {
                            if let matchRange = Range(match.range, in: mContent) {
                                mContent = String(mContent[matchRange.upperBound...])
                                sameTitleRemoved = true
                            }
                        }
                    }
                    
                    if !sameTitleRemoved && useReplace && book.getUseReplaceRule() {
                        let displayTitle = chapter.getDisplayTitle(replaceRules: titleReplaceRules, useReplace: useReplace, chineseConvert: false)
                        title = Pattern.quote(displayTitle)
                        let pattern2 = "^(\\s|\\p{P}|\(name))*\(title)(\\s)*"
                        
                        if let regex = try? NSRegularExpression(pattern: pattern2, options: [.caseInsensitive]) {
                            let range = NSRange(mContent.startIndex..., in: mContent)
                            if let match = regex.firstMatch(in: mContent, options: [], range: range) {
                                if let matchRange = Range(match.range, in: mContent) {
                                    mContent = String(mContent[matchRange.upperBound...])
                                    sameTitleRemoved = true
                                }
                            }
                        }
                    }
                } catch {
                    print("[ContentProcessor] 去除重复标题出错: \(error)")
                }
            }
            
            if reSegment && book.getReSegment() {
                mContent = ContentHelp.reSegment(mContent, title: chapter.title ?? "")
            }
            
            if chineseConvert {
                let chineseConverterType = AppConfig.chineseConverterType
                if chineseConverterType == 1 {
                    mContent = ChineseUtils.t2s(mContent)
                } else if chineseConverterType == 2 {
                    mContent = ChineseUtils.s2t(mContent)
                }
            }
            
            if useReplace && book.getUseReplaceRule() {
                effectiveReplaceRules = []
                mContent = mContent.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                
                for item in getContentReplaceRules() {
                    let pattern = item.pattern
                    if pattern.isEmpty { continue }
                    
                    do {
                        let tmp: String
                        if item.isRegex {
                            tmp = try mContent.replace(regex: item.regex, replacement: item.replacement ?? "", timeout: item.getValidTimeoutMillisecond())
                        } else {
                            tmp = mContent.replacingOccurrences(of: pattern, with: item.replacement ?? "")
                        }
                        
                        if mContent != tmp {
                            effectiveReplaceRules?.append(item)
                            mContent = tmp
                        }
                    } catch {
                        item.isEnabled = false
                        try? CoreDataStack.shared.save()
                        mContent = "\(item.name) \(error.localizedDescription)"
                    }
                }
            }
        }
        
        if includeTitle {
            let displayTitle = chapter.getDisplayTitle(replaceRules: getTitleReplaceRules(), useReplace: useReplace && book.getUseReplaceRule(), chineseConvert: chineseConvert)
            mContent = displayTitle + "\n" + mContent
        }
        
        var contents: [String] = []
        for str in mContent.components(separatedBy: .newlines) {
            let paragraph = str.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0020}\u{3000}"))
            
            if !paragraph.isEmpty {
                if contents.isEmpty && includeTitle {
                    contents.append(paragraph)
                } else {
                    let indent = String(repeating: ReadBookConfig.indentChar, count: ReadBookConfig.paragraphIndent.length)
                    contents.append(indent + paragraph)
                }
            }
        }
        
        return ProcessedContent(sameTitleRemoved: sameTitleRemoved, contents: contents, effectiveReplaceRules: effectiveReplaceRules)
    }
}

class WeakReference<T: AnyObject> {
    weak var value: T?
    
    init(value: T) {
        self.value = value
    }
}

enum Pattern {
    static func quote(_ string: String) -> String {
        return NSRegularExpression.escapedPattern(for: string)
    }
}

enum ContentHelp {
    /// 段落重排 — 简化版（Android 正版在 ContentHelp.swift）
    static func reSegment(_ content: String, title: String) -> String {
        // 委托给完整版 ContentHelp.reSegment
        return ContentHelpEngine.reSegment(content: content, chapterName: title)
    }
}

enum ChineseUtils {
    static func t2s(_ text: String) -> String {
        var result = text
        let traditionalToSimplified: [String: String] = [
            "書": "书", "電": "电", "見": "见", "長": "长", "發": "发",
            "問": "问", "開": "开", "關": "关", "時": "时", "國": "国",
            "們": "们", "說": "说", "對": "对", "來": "来", "為": "为",
            "與": "与", "會": "会", "這": "这", "個": "个", "能": "能"
        ]
        
        for (trad, simp) in traditionalToSimplified {
            result = result.replacingOccurrences(of: trad, with: simp)
        }
        
        return result
    }
    
    static func s2t(_ text: String) -> String {
        var result = text
        let simplifiedToTraditional: [String: String] = [
            "书": "書", "电": "電", "见": "見", "长": "長", "发": "發",
            "问": "問", "开": "開", "关": "關", "时": "時", "国": "國",
            "们": "們", "说": "說", "对": "對", "来": "來", "为": "為",
            "与": "與", "会": "會", "这": "這", "个": "個"
        ]
        
        for (simp, trad) in simplifiedToTraditional {
            result = result.replacingOccurrences(of: simp, with: trad)
        }
        
        return result
    }
}

enum AppConfig {
    static var clickActionMC: Int = 0
    static var clickActionBC: Int = 1
    static var clickActionBL: Int = 2
    static var clickActionBR: Int = 1
    static var clickActionML: Int = 2
    static var clickActionMR: Int = 1
    static var clickActionTL: Int = 2
    static var clickActionTC: Int = 0
    static var clickActionTR: Int = 1
    static var chineseConverterType: Int {
        return UserDefaults.standard.integer(forKey: "chineseConverterType")
    }
}

extension String {
    func escapeRegex() -> String {
        return NSRegularExpression.escapedPattern(for: self)
    }
    
    func replace(regex: NSRegularExpression?, replacement: String, timeout: Int) throws -> String {
        guard let regex = regex else { return self }
        let range = NSRange(self.startIndex..., in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replacement)
    }
}

extension NSRegularExpression {
    convenience init(pattern: String) throws {
        try self.init(pattern: pattern, options: [])
    }
}

extension Book {
    func getReSegment() -> Bool {
        return readConfigObj.reSegment
    }
}

extension BookChapter {
    func getFileName(_ suffix: String = "") -> String {
        let safeTitle = (title ?? "unknown").replacingOccurrences(of: "/", with: "_")
        if suffix.isEmpty {
            return "\(index)_\(safeTitle).txt"
        }
        return "\(index)_\(safeTitle).\(suffix)"
    }
    
    func getDisplayTitle(replaceRules: [ReplaceRule], useReplace: Bool, chineseConvert: Bool) -> String {
        var displayTitle = title ?? ""
        
        if useReplace {
            for rule in replaceRules {
                let pattern = rule.pattern
                if pattern.isEmpty { continue }
                if rule.isRegex {
                    if let regex = try? NSRegularExpression(pattern: pattern) {
                        let range = NSRange(displayTitle.startIndex..., in: displayTitle)
                        displayTitle = regex.stringByReplacingMatches(in: displayTitle, options: [], range: range, withTemplate: rule.replacement ?? "")
                    }
                } else {
                    displayTitle = displayTitle.replacingOccurrences(of: pattern, with: rule.replacement ?? "")
                }
            }
        }
        
        return displayTitle
    }
}