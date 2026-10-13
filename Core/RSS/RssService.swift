//
//  RssService.swift
//  Legado-iOS
//
//  RSS 获取统一入口 — 1:1 对标 Android Rss.kt
//  提供 getArticles 和 getContent 两个核心方法
//

import Foundation
import CoreData

// MARK: - RSS 服务入口（对标 Android Rss object）

enum RssService {
    
    /// 获取 RSS 文章列表 — 对标 Android Rss.getArticlesAwait()
    /// - Parameters:
    ///   - sortName: 分类名称
    ///   - sortUrl: 分类 URL（可含页码模板 {{page}}）
    ///   - rssSource: RSS 源
    ///   - page: 页码（从 1 开始）
    /// - Returns: (文章列表, 下一页URL)
    static func getArticles(
        sortName: String,
        sortUrl: String,
        rssSource: RssSource,
        page: Int
    ) async throws -> (items: [RssParseItem], nextUrl: String?) {
        let rssSource = try RssSourceSnapshot.capture(rssSource)
        // 替换页码模板
        let urlString = sortUrl
            .replacingOccurrences(of: "{{page}}", with: "\(page)")
            .replacingOccurrences(of: "{{page-1}}", with: "\(page - 1)")
        
        // 使用 HTTPClient 请求
        let (body, httpResponse) = try await HTTPClient.shared.getHtml(urlString: urlString, headers: parseHeaders(rssSource.header))
        let finalUrl = httpResponse.url?.absoluteString ?? urlString
        
        // 判断使用规则解析还是默认 XML 解析
        if RssRuleParser.shouldUseRuleParsing(source: rssSource) {
            let ruleParser = RssRuleParser()
            return ruleParser.parseXML(
                body: body,
                sortName: sortName,
                sortUrl: finalUrl,
                source: rssSource
            )
        } else {
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RssError.emptyContent(rssSource.sourceUrl)
            }
            return RssDefaultParser.parseXML(
                xml: body,
                sortName: sortName,
                sourceUrl: rssSource.sourceUrl
            )
        }
    }
    
    /// 获取 RSS 文章正文 — 对标 Android Rss.getContentAwait()
    /// - Parameters:
    ///   - article: RSS 文章（CoreData 实体）
    ///   - ruleContent: 正文规则
    ///   - rssSource: RSS 源
    /// - Returns: 正文内容（HTML）
    static func getContent(
        article: RssArticle,
        ruleContent: String?,
        rssSource: RssSource
    ) async throws -> String {
        let rssSource = try RssSourceSnapshot.capture(rssSource)
        let articleData = try ManagedObjectAccess.read(article) { ($0.articleDescription, $0.content, $0.link) }
        guard let ruleContent = ruleContent, !ruleContent.isEmpty else {
            // 无正文规则，返回文章已有的 description 或 content
            return articleData.0 ?? articleData.1 ?? ""
        }
        
        // 请求正文页面
        let baseUrl = absoluteURL(base: rssSource.sourceUrl, relative: articleData.2)
        
        let (body, _) = try await HTTPClient.shared.getHtml(urlString: baseUrl, headers: parseHeaders(rssSource.header))
        
        // 用规则引擎提取正文
        let ruleEngine = RuleEngine()
        let contentList = (try? ruleEngine.getStringList(
            ruleStr: ruleContent,
            body: body,
            baseUrl: baseUrl
        )) ?? []
        
        return contentList.joined(separator: "\n")
    }
    
    // MARK: - Private
    
    private static func absoluteURL(base: String, relative: String) -> String {
        guard !relative.isEmpty else { return "" }
        if relative.hasPrefix("http://") || relative.hasPrefix("https://") {
            return relative
        }
        guard let baseURL = URL(string: base) else { return relative }
        return URL(string: relative, relativeTo: baseURL)?.absoluteString ?? relative
    }
    
    /// 解析 JSON 格式的 headers 字符串
    private static func parseHeaders(_ headerStr: String?) -> [String: String]? {
        guard let str = headerStr, !str.isEmpty else { return nil }
        guard let data = str.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return dict
    }
}

// MARK: - RSS 错误类型

enum RssError: LocalizedError {
    case emptyContent(String)
    case invalidSource(String)
    case networkFailure(String)
    
    var errorDescription: String? {
        switch self {
        case .emptyContent(let url): return "内容为空: \(url)"
        case .invalidSource(let url): return "无效书源: \(url)"
        case .networkFailure(let msg): return "网络请求失败: \(msg)"
        }
    }
}