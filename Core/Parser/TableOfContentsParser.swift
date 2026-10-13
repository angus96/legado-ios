//
//  TableOfContentsParser.swift
//  Legado-iOS
//
//  目录解析器
//

import Foundation
import CoreData

// MARK: - 目录规则结构体
struct RuleToc: Codable {
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var nextTocUrl: String?
    var updateTime: String?
}

// MARK: - 规则解析器占位
class RuleParser {
    static func parse(html: String, rule: String) throws -> String {
        if rule.isEmpty {
            return html
        }
        return html
    }
}

/// 目录解析器
class TableOfContentsParser {

    
    struct ChapterInfo {
        let title: String
        let url: String
        let index: Int
    }
    
    /// 从书源解析目录
    static func parse(from html: String, ruleToc: RuleToc) async throws -> [ChapterInfo] {
        var chapters: [ChapterInfo] = []
        
        // 1. 提取章节列表 HTML
        let listHTML: String
        if let chapterList = ruleToc.chapterList,
           !chapterList.isEmpty,
           let extracted = try? RuleParser.parse(html: html, rule: chapterList) {
            listHTML = extracted
        } else {
            listHTML = html
        }
        
        // 2. 提取所有章节链接
        let chapterElements = extractChapterElements(from: listHTML, rule: ruleToc)
        
        // 3. 解析每个章节
        for (index, element) in chapterElements.enumerated() {
            if let chapter = parseChapter(from: element, rule: ruleToc, index: index) {
                chapters.append(chapter)
            }
        }
        
        return chapters
    }
    
    /// 提取章节元素列表
    private static func extractChapterElements(from html: String, rule: RuleToc) -> [String] {
        var elements: [String] = []
        
        // 使用 chapterList 规则或默认的 <a> 标签
        let pattern: String
        if let listRule = rule.chapterList, !listRule.isEmpty {
            // 自定义列表规则
            pattern = "<[^>]+>.*?</[^>]+>"
        } else {
            // 默认提取所有 <a> 标签
            pattern = #"<a[^>]*href="[^"]*"[^>]*>[^<]*</a>"#
        }
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return elements
        }
        
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        
        for match in matches {
            if let range = Range(match.range, in: html) {
                elements.append(String(html[range]))
            }
        }
        
        return elements
    }
    
    /// 解析单个章节
    private static func parseChapter(from element: String, rule: RuleToc, index: Int) -> ChapterInfo? {
        // 提取 URL
        let urlPattern = #"href="([^"]+)""#
        guard let url = extractFirstMatch(in: element, pattern: urlPattern) else {
            return nil
        }
        
        // 提取标题
        let title: String
        if let nameRule = rule.chapterName,
           !nameRule.isEmpty,
           let extracted = try? RuleParser.parse(html: element, rule: nameRule) {
            title = extracted
        } else {
            // 默认提取标签内容
            title = extractFirstMatch(in: element, pattern: #">([^<]+)<"#) ?? "第\(index + 1)章"
        }
        
        return ChapterInfo(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url,
            index: index
        )
    }
    
    /// 解析下一页 URL
    static func parseNextPageURL(from html: String, rule: RuleToc, baseURL: String) -> String? {
        guard let nextPageRule = rule.nextTocUrl,
              !nextPageRule.isEmpty,
              let nextURL = try? RuleParser.parse(html: html, rule: nextPageRule) else {
            return nil
        }
        
        return resolveURL(baseURL: baseURL, relativeURL: nextURL)
    }
    
    /// 解析章节更新时间
    static func parseUpdateTime(from html: String, rule: RuleToc) -> Date? {
        guard let updateRule = rule.updateTime,
              !updateRule.isEmpty,
              let timeString = try? RuleParser.parse(html: html, rule: updateRule) else {
            return nil
        }
        
        // 尝试多种日期格式
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "MM-dd HH:mm",
            "yyyy年MM月dd日"
        ]
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: timeString) {
                return date
            }
        }
        
        return nil
    }
    
    // MARK: - 辅助方法
    
    private static func extractFirstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }
    
    private static func resolveURL(baseURL: String, relativeURL: String) -> String {
        if relativeURL.hasPrefix("http") {
            return relativeURL
        }
        
        guard let base = URL(string: baseURL) else {
            return relativeURL
        }
        
        return URL(string: relativeURL, relativeTo: base)?.absoluteString ?? relativeURL
    }
}

// MARK: - 目录获取服务
@MainActor
final class TableOfContentsService {
    static let shared = TableOfContentsService()

    func fetchTableOfContents(book: Book, source: BookSource) async throws -> [BookChapter] {
        let cached = try loadCachedChapters(book: book)
        if !cached.isEmpty { return cached }
        return try await refreshTableOfContents(book: book, source: source)
    }

    func refreshTableOfContents(book: Book, source: BookSource) async throws -> [BookChapter] {
        let original = try BookRequestSnapshot.capture(book)
        let definition = try BookSourceSnapshot.capture(source)
        let chapters = try await WebBook.getChapterList(source: definition, book: original)
        try Task.checkCancellation()
        try await ChapterDirectoryUpdater.replace(book: book, source: source, original: original,
                                                  metadata: original, definition: definition, chapters: chapters)
        return try loadCachedChapters(book: book)
    }

    private func loadCachedChapters(book: Book) throws -> [BookChapter] {
        guard let context = book.managedObjectContext else { throw ManagedObjectAccessError.unavailable }
        return try context.performAndWait { try context.fetch(BookChapter.fetchRequest(byBookId: book.bookId)) }
    }
}
