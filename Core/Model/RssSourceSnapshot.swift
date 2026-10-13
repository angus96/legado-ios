import Foundation

protocol RssSourceDefinition {
    var sourceUrl: String { get }
    var sourceName: String { get }
    var header: String? { get }
    var ruleArticles: String? { get }
    var ruleNextPage: String? { get }
    var ruleTitle: String? { get }
    var ruleLink: String? { get }
    var ruleDescription: String? { get }
    var ruleContent: String? { get }
    var rulePubDate: String? { get }
    var ruleImage: String? { get }
}

extension RssSource: RssSourceDefinition {}

struct RssSourceSnapshot: RssSourceDefinition {
    let sourceUrl: String
    let sourceName: String
    let header: String?
    let ruleArticles: String?
    let ruleNextPage: String?
    let ruleTitle: String?
    let ruleLink: String?
    let ruleDescription: String?
    let ruleContent: String?
    let rulePubDate: String?
    let ruleImage: String?

    static func capture(_ definition: RssSourceDefinition) throws -> RssSourceSnapshot {
        if let snapshot = definition as? RssSourceSnapshot { return snapshot }
        guard let source = definition as? RssSource else { throw ManagedObjectAccessError.unavailable }
        return try ManagedObjectAccess.read(source) {
            RssSourceSnapshot(sourceUrl: $0.sourceUrl, sourceName: $0.sourceName, header: $0.header,
                              ruleArticles: $0.ruleArticles, ruleNextPage: $0.ruleNextPage,
                              ruleTitle: $0.ruleTitle, ruleLink: $0.ruleLink,
                              ruleDescription: $0.ruleDescription, ruleContent: $0.ruleContent,
                              rulePubDate: $0.rulePubDate, ruleImage: $0.ruleImage)
        }
    }
}
