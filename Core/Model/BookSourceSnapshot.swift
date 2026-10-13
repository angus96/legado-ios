import Foundation
import CoreData

protocol BookSourceDefinition {
    var sourceId: UUID { get }
    var bookSourceUrl: String { get }
    var bookSourceName: String { get }
    var bookUrlPattern: String? { get }
    var searchUrl: String? { get }
    var exploreUrl: String? { get }
    var loginUrl: String? { get }
    var loginCheckJs: String? { get }
    var header: String? { get }
    var variable: String? { get }
    var enabledCookieJar: Bool { get }
    var concurrentRate: String? { get }
    var coverDecodeJs: String? { get }
    var jsLib: String? { get }
    var ruleSearchData: Data? { get }
    var ruleExploreData: Data? { get }
    var ruleBookInfoData: Data? { get }
    var ruleTocData: Data? { get }
    var ruleContentData: Data? { get }
}

extension BookSource: BookSourceDefinition {}

/// Network requests and rule parsing use copied values instead of CoreData objects.
struct BookSourceSnapshot: BookSourceDefinition {
    let sourceId: UUID
    let bookSourceUrl: String
    let bookSourceName: String
    let bookUrlPattern: String?
    let searchUrl: String?
    let exploreUrl: String?
    let loginUrl: String?
    let loginCheckJs: String?
    let header: String?
    let variable: String?
    let enabledCookieJar: Bool
    let concurrentRate: String?
    let coverDecodeJs: String?
    let jsLib: String?
    let ruleSearchData: Data?
    let ruleExploreData: Data?
    let ruleBookInfoData: Data?
    let ruleTocData: Data?
    let ruleContentData: Data?

    private init(_ source: BookSourceDefinition) {
        sourceId = source.sourceId
        bookSourceUrl = source.bookSourceUrl
        bookSourceName = source.bookSourceName
        bookUrlPattern = source.bookUrlPattern
        searchUrl = source.searchUrl
        exploreUrl = source.exploreUrl
        loginUrl = source.loginUrl
        loginCheckJs = source.loginCheckJs
        header = source.header
        variable = source.variable
        enabledCookieJar = source.enabledCookieJar
        concurrentRate = source.concurrentRate
        coverDecodeJs = source.coverDecodeJs
        jsLib = source.jsLib
        ruleSearchData = source.ruleSearchData
        ruleExploreData = source.ruleExploreData
        ruleBookInfoData = source.ruleBookInfoData
        ruleTocData = source.ruleTocData
        ruleContentData = source.ruleContentData
    }

    static func capture(_ source: BookSourceDefinition) throws -> BookSourceSnapshot {
        if let snapshot = source as? BookSourceSnapshot { return snapshot }
        if let managedSource = source as? BookSource {
            return try ManagedObjectAccess.read(managedSource) { BookSourceSnapshot($0) }
        }
        return BookSourceSnapshot(source)
    }
}

extension BookSourceDefinition {
    private func decodeRule<Rule: Decodable>(_ data: Data?, as type: Rule.Type) -> Rule? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func getSearchRule() -> BookSource.SearchRule? { decodeRule(ruleSearchData, as: BookSource.SearchRule.self) }
    func getExploreRule() -> BookSource.ExploreRule? { decodeRule(ruleExploreData, as: BookSource.ExploreRule.self) }
    func getBookInfoRule() -> BookSource.BookInfoRule? { decodeRule(ruleBookInfoData, as: BookSource.BookInfoRule.self) }
    func getTocRule() -> TocRule? { decodeRule(ruleTocData, as: TocRule.self) }
    func getContentRule() -> BookSource.ContentRule? { decodeRule(ruleContentData, as: BookSource.ContentRule.self) }
}
