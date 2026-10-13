import Foundation
import SwiftSoup

final class RuleBasedRSSParser {
    private let ruleEngine: RuleEngine

    init(ruleEngine: RuleEngine = RuleEngine()) {
        self.ruleEngine = ruleEngine
    }

    static func shouldUseRuleParsing(source: RssSourceDefinition) -> Bool {
        guard let rule = try? RssSourceSnapshot.capture(source).ruleArticles else { return false }
        return !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func parse(data: Data, source: RssSourceDefinition, sourceUrl: String) throws -> [RSSArticle] {
        let body = decodeBody(from: data)
        return try parse(body: body, source: source, sourceUrl: sourceUrl)
    }

    func parse(body: String, source: RssSourceDefinition, sourceUrl: String) throws -> [RSSArticle] {
        let source = try RssSourceSnapshot.capture(source)
        let elements = try ruleEngine.getElements(
            ruleStr: source.ruleArticles,
            body: body,
            baseUrl: sourceUrl
        )

        var articles: [RSSArticle] = []
        articles.reserveCapacity(elements.count)

        for element in elements {
            let title = extractValue(rule: source.ruleTitle, elementContext: element, baseUrl: sourceUrl)
            let link = extractValue(rule: source.ruleLink, elementContext: element, baseUrl: sourceUrl)
            let description = extractValue(rule: source.ruleDescription, elementContext: element, baseUrl: sourceUrl)
            let content = extractValue(rule: source.ruleContent, elementContext: element, baseUrl: sourceUrl)
            let pubDateText = extractValue(rule: source.rulePubDate, elementContext: element, baseUrl: sourceUrl)

            if title.isEmpty && link.isEmpty && description.isEmpty && content.isEmpty {
                continue
            }

            let finalTitle = title.isEmpty ? (link.isEmpty ? "无标题" : link) : title
            let finalDescription = description.isEmpty ? (content.isEmpty ? nil : content) : description

            let article = RSSArticle(
                title: finalTitle,
                link: link,
                description: finalDescription,
                pubDate: parseDate(pubDateText),
                author: nil
            )
            articles.append(article)
        }

        return articles
    }

    private func extractValue(rule: String?, elementContext: ElementContext, baseUrl: String) -> String {
        let direct = ruleEngine.getString(
            ruleStr: rule,
            elementContext: elementContext,
            baseUrl: baseUrl
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if !direct.isEmpty {
            return direct
        }

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

        if let element = elementContext.element as? SwiftSoup.Element {
            return try? element.outerHtml()
        }

        return nil
    }

    private func decodeBody(from data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )

        if let gbk = String(data: data, encoding: gb18030) {
            return gbk
        }

        return String(decoding: data, as: UTF8.self)
    }

    private func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let timestamp = Double(trimmed) {
            if timestamp > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: timestamp / 1000)
            }
            if timestamp > 1_000_000_000 {
                return Date(timeIntervalSince1970: timestamp)
            }
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: trimmed) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss z",
            "EEE, dd MMM yyyy HH:mm z",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyy年MM月dd日 HH:mm:ss",
            "yyyy年MM月dd日"
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }
}
