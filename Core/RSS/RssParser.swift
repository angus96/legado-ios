//
//  RssParser.swift
//  Legado-iOS
//
//  RSS 解析器 — 1:1 对标 Android RssParserDefault.kt + RssParserByRule.kt
//  将 RSS 解析逻辑从 View 层提升到 Core 层
//

import Foundation
import SwiftSoup

// MARK: - RSS 解析结果

/// RSS 解析结果条目（纯值类型，用于 Core 层传递）
struct RssParseItem {
    var title: String
    var link: String
    var description: String?
    var content: String?
    var pubDate: String?
    var image: String?
    var author: String?
    var sort: String
    var origin: String
}

// MARK: - 默认 XML 解析器（对标 Android RssParserDefault.kt）

final class RssDefaultParser: NSObject {
    
    private var items: [RssParseItem] = []
    private var feedTitle: String?
    
    // XML 解析状态
    private var currentText = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentContent = ""
    private var currentPubDate = ""
    private var currentAuthor = ""
    private var currentImage: String?
    private var isInItem = false
    private var isInAuthor = false
    
    // RSS XML 标签名常量（对标 Android RssParserDefault.kt 私有常量）
    private static let rssItem = "item"
    private static let rssItemTitle = "title"
    private static let rssItemLink = "link"
    private static let rssItemThumbnail = "media:thumbnail"
    private static let rssItemEnclosure = "enclosure"
    private static let rssItemDescription = "description"
    private static let rssItemContent = "content:encoded"
    private static let rssItemPubDate = "pubdate"
    private static let rssItemTime = "time"
    private static let rssItemUrl = "url"
    private static let rssItemType = "type"
    
    /// 解析 RSS/Atom XML — 对标 Android RssParserDefault.parseXML()
    static func parseXML(xml: String, sortName: String, sourceUrl: String) -> (items: [RssParseItem], nextUrl: String?) {
        guard let data = xml.data(using: .utf8) else {
            return ([], nil)
        }
        let parser = RssDefaultParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        
        // 赋值 sort 和 origin
        var result = parser.items
        for i in result.indices {
            result[i].sort = sortName
            result[i].origin = sourceUrl
        }
        return (result, nil) // 默认解析无 nextUrl
    }
    
    /// 从 Data 解析
    static func parseXML(data: Data, sortName: String, sourceUrl: String) -> (items: [RssParseItem], nextUrl: String?) {
        let parser = RssDefaultParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        
        var result = parser.items
        for i in result.indices {
            result[i].sort = sortName
            result[i].origin = sourceUrl
        }
        return (result, nil)
    }
}

// MARK: - XMLParserDelegate

extension RssDefaultParser: XMLParserDelegate {
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        currentText = ""
        
        if name == Self.rssItem || name == "entry" {
            isInItem = true
            resetCurrentArticle()
            return
        }
        
        if isInItem {
            // 对标 Android: media:thumbnail
            if name == Self.rssItemThumbnail || name == "media:thumbnail" {
                if let url = attributeDict[Self.rssItemUrl], !url.isEmpty {
                    currentImage = url
                }
            }
            // 对标 Android: enclosure (type contains image/)
            if name == Self.rssItemEnclosure || name == "enclosure" {
                let type = attributeDict[Self.rssItemType] ?? ""
                if type.contains("image/") {
                    if let url = attributeDict[Self.rssItemUrl], !url.isEmpty {
                        currentImage = url
                    }
                }
            }
            if name == "link", let href = attributeDict["href"], !href.isEmpty {
                currentLink = href
            }
            if name == "author" {
                isInAuthor = true
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentText += text
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if isInItem {
            switch name {
            case Self.rssItemTitle, "title":
                if currentTitle.isEmpty { currentTitle = text }
            case Self.rssItemLink, "link", "id":
                if currentLink.isEmpty { currentLink = text }
            case Self.rssItemDescription, "description", "summary":
                if currentDescription.isEmpty {
                    currentDescription = text
                    // 对标 Android: 从 description 提取图片
                    if currentImage == nil {
                        currentImage = getImageUrl(from: text)
                    }
                }
            case Self.rssItemContent, "content:encoded", "content":
                if currentContent.isEmpty {
                    currentContent = text
                    // 对标 Android: 从 content 提取图片
                    if currentImage == nil {
                        currentImage = getImageUrl(from: text)
                    }
                } else if !text.isEmpty {
                    currentContent += "\n" + text
                }
            case Self.rssItemPubDate, "pubdate", "published", "updated", "dc:date":
                if currentPubDate.isEmpty { currentPubDate = text }
            case Self.rssItemTime, "time":
                if currentPubDate.isEmpty { currentPubDate = text }
            case "author":
                if currentAuthor.isEmpty { currentAuthor = text }
                isInAuthor = false
            case "name":
                if isInAuthor && currentAuthor.isEmpty {
                    currentAuthor = text
                }
            case Self.rssItem, "entry":
                appendCurrentArticle()
                resetCurrentArticle()
                isInItem = false
                isInAuthor = false
            default:
                break
            }
        } else if name == "title", feedTitle == nil, !text.isEmpty {
            feedTitle = text
        }
        
        currentText = ""
    }
    
    // MARK: - Private
    
    private func appendCurrentArticle() {
        let trimmedTitle = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedTitle.isEmpty || !trimmedLink.isEmpty else { return }
        
        let item = RssParseItem(
            title: trimmedTitle.isEmpty ? "无标题" : trimmedTitle,
            link: trimmedLink,
            description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            content: currentContent.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            pubDate: currentPubDate.nilIfEmpty,
            image: currentImage,
            author: currentAuthor.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            sort: "",
            origin: ""
        )
        items.append(item)
    }
    
    private func resetCurrentArticle() {
        currentText = ""
        currentTitle = ""
        currentLink = ""
        currentDescription = ""
        currentContent = ""
        currentPubDate = ""
        currentAuthor = ""
        currentImage = nil
    }
    
    /// 对标 Android RssParserDefault.getImageUrl() — 从 HTML 中提取首张图片
    private func getImageUrl(from input: String) -> String? {
        // 匹配 <img> 标签
        guard let imgRange = input.range(of: #"<img[^>]*>"#, options: .regularExpression) else {
            return nil
        }
        let imgTag = String(input[imgRange])
        // 匹配 src="..."
        guard let srcRange = imgTag.range(of: #"src\s*=\s*"([^"]+)""#, options: .regularExpression) else {
            return nil
        }
        let srcContent = String(imgTag[srcRange])
        // 提取引号内容
        let quoteStart = srcContent.firstIndex(of: "\"")
        let quoteEnd = srcContent.lastIndex(of: "\"")
        guard let start = quoteStart, let end = quoteEnd, start < end else { return nil }
        return String(srcContent[srcContent.index(after: start)..<end]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 规则解析器（对标 Android RssParserByRule.kt）

final class RssRuleParser {
    
    private let ruleEngine: RuleEngine
    
    init(ruleEngine: RuleEngine = RuleEngine()) {
        self.ruleEngine = ruleEngine
    }
    
    /// 判断是否应使用规则解析 — 对标 Android RssParserByRule 判断 ruleArticles 是否为空
    static func shouldUseRuleParsing(source: RssSourceDefinition) -> Bool {
        guard let rule = try? RssSourceSnapshot.capture(source).ruleArticles else { return false }
        return !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// 规则解析 RSS — 对标 Android RssParserByRule.parseXML()
    func parseXML(
        body: String,
        sortName: String,
        sortUrl: String,
        source: RssSourceDefinition
    ) -> (items: [RssParseItem], nextUrl: String?) {
        guard let source = try? RssSourceSnapshot.capture(source) else { return ([], nil) }
        var ruleArticles = source.ruleArticles ?? ""
        var nextUrl: String?
        var reverse = false
        
        // 对标 Android: ruleArticles 以 "-" 开头时反转列表
        if ruleArticles.hasPrefix("-") {
            reverse = true
            ruleArticles = String(ruleArticles.dropFirst())
        }
        
        // 用 RuleEngine 获取元素列表
        let elements = (try? ruleEngine.getElements(
            ruleStr: ruleArticles,
            body: body,
            baseUrl: sortUrl
        )) ?? []
        
        // 对标 Android: 解析 nextPage
        if let ruleNextPage = source.ruleNextPage, !ruleNextPage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if ruleNextPage.uppercased() == "PAGE" {
                nextUrl = sortUrl
            } else {
                let nextStr = ((try? ruleEngine.getStringList(
                    ruleStr: ruleNextPage,
                    body: body,
                    baseUrl: sortUrl
                ))?.first)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !nextStr.isEmpty {
                    nextUrl = absoluteURL(base: sortUrl, relative: nextStr)
                }
            }
        }
        
        var articleList: [RssParseItem] = []
        
        for element in elements {
            let title = extractValue(rule: source.ruleTitle, elementContext: element, baseUrl: sortUrl)
            let link = extractValue(rule: source.ruleLink, elementContext: element, baseUrl: sortUrl)
            let description = extractValue(rule: source.ruleDescription, elementContext: element, baseUrl: sortUrl)
            let image = extractValue(rule: source.ruleImage, elementContext: element, baseUrl: sortUrl)
            let pubDate = extractValue(rule: source.rulePubDate, elementContext: element, baseUrl: sortUrl)
            
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { continue }
            
            let item = RssParseItem(
                title: trimmedTitle,
                link: absoluteURL(base: source.sourceUrl, relative: link.trimmingCharacters(in: .whitespacesAndNewlines)),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                content: nil,
                pubDate: pubDate.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                image: absoluteURL(base: source.sourceUrl, relative: image.trimmingCharacters(in: .whitespacesAndNewlines)).nilIfEmpty,
                author: nil,
                sort: sortName,
                origin: source.sourceUrl
            )
            articleList.append(item)
        }
        
        if reverse {
            articleList.reverse()
        }
        
        return (articleList, nextUrl)
    }
    
    // MARK: - Private
    
    private func extractValue(rule: String?, elementContext: ElementContext, baseUrl: String) -> String {
        let direct = ruleEngine.getString(
            ruleStr: rule,
            elementContext: elementContext,
            baseUrl: baseUrl
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !direct.isEmpty {
            return direct
        }
        
        // XPath 回退
        guard let rule = rule?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rule.isEmpty,
              rule.hasPrefix("//") else {
            return ""
        }
        
        return extractXPathValue(rule: rule, elementContext: elementContext, baseUrl: baseUrl)
    }
    
    private func extractXPathValue(rule: String, elementContext: ElementContext, baseUrl: String) -> String {
        guard let html = htmlString(from: elementContext), !html.isEmpty else {
            return ""
        }
        
        let context = ExecutionContext()
        context.document = html
        context.baseURL = URL(string: baseUrl)
        
        guard let result = try? ruleEngine.executeSingle(rule: rule, context: context) else {
            return ""
        }
        
        if let value = result.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        
        if let value = result.list?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        
        return ""
    }
    
    private func htmlString(from elementContext: ElementContext) -> String? {
        if let html = elementContext.element as? String {
            return html
        }
        // SwiftSoup.Element
        if let element = elementContext.element as? SwiftSoup.Element {
            return try? element.outerHtml()
        }
        // 尝试 debug description 作为 fallback
        let desc = String(describing: elementContext.element)
        return desc.isEmpty ? nil : desc
    }
    
    /// 拼接绝对 URL
    private func absoluteURL(base: String, relative: String) -> String {
        guard !relative.isEmpty else { return "" }
        if relative.hasPrefix("http://") || relative.hasPrefix("https://") {
            return relative
        }
        guard let base = URL(string: base) else { return relative }
        return URL(string: relative, relativeTo: base)?.absoluteString ?? relative
    }
}

// MARK: - String 辅助

private extension String {
    var nilIfEmpty: String? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}