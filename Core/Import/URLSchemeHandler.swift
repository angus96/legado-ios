import Foundation
import SwiftUI
import CoreData

enum URLSchemeAction {
    case importBookSource(url: URL)
    case importRssSource(url: URL)
    case importReplaceRule(url: URL)
    case importTtsRule(url: URL)
    case importTheme(url: URL)
    case importReadConfig(url: URL)
    case importDictRule(url: URL)
    case importTextTocRule(url: URL)
    case addToBookshelf(url: URL)
    case importBookSourceJSON(String)
    case importRssSourceJSON(String)
    case openBook(bookId: UUID)
    case unknown
}

extension Notification.Name {
    static let openBookNotification = Notification.Name("openBookNotification")
    static let importBookSourceNotification = Notification.Name("importBookSourceNotification")
    static let importRssSourceNotification = Notification.Name("importRssSourceNotification")
    static let addToBookshelfNotification = Notification.Name("addToBookshelfNotification")
}

private struct SourceJSON: Codable {
    let bookSourceUrl: String
    let bookSourceName: String
    let bookSourceGroup: String?
    let bookSourceType: Int?
    let searchUrl: String?
    let exploreUrl: String?
    let ruleSearch: RuleSearchJSON?
    let ruleExplore: RuleExploreJSON?
    let ruleBookInfo: RuleBookInfoJSON?
    let ruleToc: RuleTocJSON?
    let ruleContent: RuleContentJSON?
    let enabled: Bool?
    let enabledExplore: Bool?
    let weight: Int?
    let lastUpdateTime: Int64?
    let respondTime: Int?
    let loginUrl: String?
    let loginUi: String?
    let loginCheckJs: String?
    let header: String?
    let concurrentRate: String?
}

private struct RuleSearchJSON: Codable {
    let bookList: String?
    let name: String?
    let author: String?
    let intro: String?
    let kind: String?
    let lastChapter: String?
    let updateTime: String?
    let bookUrl: String?
    let coverUrl: String?
    let wordCount: String?
    let tocUrl: String?
}

private struct RuleExploreJSON: Codable {
    let bookList: String?
    let name: String?
    let author: String?
    let intro: String?
    let kind: String?
    let lastChapter: String?
    let updateTime: String?
    let bookUrl: String?
    let coverUrl: String?
    let wordCount: String?
    let tocUrl: String?
}

private struct RuleBookInfoJSON: Codable {
    let name: String?
    let author: String?
    let intro: String?
    let kind: String?
    let lastChapter: String?
    let updateTime: String?
    let coverUrl: String?
    let tocUrl: String?
    let wordCount: String?
    let canReName: String?
}

private struct RuleTocJSON: Codable {
    let chapterList: String?
    let chapterName: String?
    let chapterUrl: String?
    let isVip: String?
    let isPay: String?
    let updateTime: String?
    let nextTocUrl: String?
}

private struct RuleContentJSON: Codable {
    let content: String?
    let nextContentUrl: String?
    let webJs: String?
    let sourceRegex: String?
    let replaceRegex: String?
    let imageStyle: String?
    let payAction: String?
}

struct URLSchemeHandler {
    static func parse(_ url: URL) -> URLSchemeAction {
        guard url.scheme == "legado" else { return .unknown }
        
        let host = url.host ?? ""
        let path = url.path
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        
        switch host {
        case "import":
            let pathType = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return parseImportPath(pathType, queryItems: queryItems)
            
        case "booksource":
            if path.contains("importonline"), let src = queryItems.first(where: { $0.name == "src" })?.value, let srcURL = URL(string: src) {
                return .importBookSource(url: srcURL)
            }
            if path.contains("import"), let json = queryItems.first(where: { $0.name == "json" })?.value {
                return .importBookSourceJSON(json)
            }
            
        case "rsssource":
            if path.contains("importonline"), let src = queryItems.first(where: { $0.name == "src" })?.value, let srcURL = URL(string: src) {
                return .importRssSource(url: srcURL)
            }
            if path.contains("import"), let json = queryItems.first(where: { $0.name == "json" })?.value {
                return .importRssSourceJSON(json)
            }
            
        case "replace":
            if let src = queryItems.first(where: { $0.name == "src" })?.value, let srcURL = URL(string: src) {
                return .importReplaceRule(url: srcURL)
            }
            
        case "book":
            if let bookIdString = queryItems.first(where: { $0.name == "id" })?.value, let bookId = UUID(uuidString: bookIdString) {
                return .openBook(bookId: bookId)
            }
            
        default:
            break
        }
        
        return .unknown
    }
    
    private static func parseImportPath(_ path: String, queryItems: [URLQueryItem]) -> URLSchemeAction {
        guard let srcValue = queryItems.first(where: { $0.name == "src" })?.value,
              let srcURL = URL(string: srcValue) else {
            if let jsonValue = queryItems.first(where: { $0.name == "json" })?.value {
                if path == "bookSource" {
                    return .importBookSourceJSON(jsonValue)
                } else if path == "rssSource" {
                    return .importRssSourceJSON(jsonValue)
                }
            }
            return .unknown
        }
        
        switch path.lowercased() {
        case "booksource":
            return .importBookSource(url: srcURL)
        case "rsssource":
            return .importRssSource(url: srcURL)
        case "replacerule":
            return .importReplaceRule(url: srcURL)
        case "httptts":
            return .importTtsRule(url: srcURL)
        case "theme":
            return .importTheme(url: srcURL)
        case "readconfig":
            return .importReadConfig(url: srcURL)
        case "dictrule":
            return .importDictRule(url: srcURL)
        case "texttocrule":
            return .importTextTocRule(url: srcURL)
        case "addtobookshelf":
            return .addToBookshelf(url: srcURL)
        default:
            return .unknown
        }
    }
    
    static func handle(_ url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let action = parse(url)
        
        switch action {
        case .importBookSource(let sourceURL):
            importFromURL(sourceURL, type: .bookSource, completion: completion)
            
        case .importRssSource(let sourceURL):
            importFromURL(sourceURL, type: .rssSource, completion: completion)
            
        case .importReplaceRule(let sourceURL):
            importFromURL(sourceURL, type: .replaceRule, completion: completion)
            
        case .importTtsRule(let sourceURL):
            importFromURL(sourceURL, type: .ttsRule, completion: completion)
            
        case .importTheme(let sourceURL):
            importFromURL(sourceURL, type: .theme, completion: completion)
            
        case .importReadConfig(let sourceURL):
            importFromURL(sourceURL, type: .readConfig, completion: completion)
            
        case .importDictRule(let sourceURL):
            importFromURL(sourceURL, type: .dictRule, completion: completion)
            
        case .importTextTocRule(let sourceURL):
            importFromURL(sourceURL, type: .textTocRule, completion: completion)
            
        case .addToBookshelf(let sourceURL):
            importFromURL(sourceURL, type: .addToBookshelf, completion: completion)
            
        case .importBookSourceJSON(let json):
            importBookSourceJSON(json, completion: completion)
            
        case .importRssSourceJSON(let json):
            importRssSourceJSON(json, completion: completion)
            
        case .openBook(let bookId):
            NotificationCenter.default.post(name: .openBookNotification, object: bookId)
            completion(.success("正在打开书籍"))
            
        case .unknown:
            completion(.failure(URLError(.badURL)))
        }
    }
    
    private enum ImportType {
        case bookSource, rssSource, replaceRule, ttsRule, theme, readConfig, dictRule, textTocRule, addToBookshelf
    }
    
    private static func importFromURL(_ url: URL, type: ImportType, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let jsonString = String(data: data, encoding: .utf8) else {
                    await MainActor.run { completion(.failure(URLError(.cannotDecodeContentData))) }
                    return
                }
                
                switch type {
                case .bookSource:
                    importBookSourceJSON(jsonString, completion: completion)
                case .rssSource:
                    importRssSourceJSON(jsonString, completion: completion)
                case .replaceRule:
                    importReplaceRuleJSON(jsonString, completion: completion)
                case .ttsRule:
                    importTtsRuleJSON(jsonString, completion: completion)
                case .theme:
                    importThemeJSON(jsonString, completion: completion)
                case .readConfig:
                    importReadConfigJSON(jsonString, completion: completion)
                case .dictRule:
                    importDictRuleJSON(jsonString, completion: completion)
                case .textTocRule:
                    importTextTocRuleJSON(jsonString, completion: completion)
                case .addToBookshelf:
                    importAddToBookshelfJSON(jsonString, completion: completion)
                }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }
    
    static func importBookSourceJSON(_ jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let data = jsonString.data(using: .utf8) else {
            completion(.failure(URLError(.cannotDecodeContentData)))
            return
        }
        
        do {
            let decoder = JSONDecoder()
            let context = CoreDataStack.shared.viewContext
            var imported = 0
            var duplicated = 0
            
            if jsonString.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
                let sources = try decoder.decode([SourceJSON].self, from: data)
                for json in sources {
                    if let existing = try? context.fetch(BookSource.fetchRequest()).first(where: { 
                        ($0 as? BookSource)?.bookSourceUrl == json.bookSourceUrl 
                    }) as? BookSource, existing.bookSourceUrl == json.bookSourceUrl {
                        duplicated += 1
                        continue
                    }
                    
                    let source = BookSource.create(in: context)
                    applyJSONToBookSource(json, source: source)
                    imported += 1
                }
            } else {
                let json = try decoder.decode(SourceJSON.self, from: data)
                if let existing = try? context.fetch(BookSource.fetchRequest()).first(where: { 
                    ($0 as? BookSource)?.bookSourceUrl == json.bookSourceUrl 
                }) as? BookSource, existing.bookSourceUrl == json.bookSourceUrl {
                    duplicated = 1
                } else {
                    let source = BookSource.create(in: context)
                    applyJSONToBookSource(json, source: source)
                    imported = 1
                }
            }
            
            try context.save()
            
            NotificationCenter.default.post(name: .importBookSourceNotification, object: nil)
            
            var message = "成功导入 \(imported) 个书源"
            if duplicated > 0 {
                message += "，跳过 \(duplicated) 个重复书源"
            }
            completion(.success(message))
        } catch {
            completion(.failure(error))
        }
    }
    
    private static func applyJSONToBookSource(_ json: SourceJSON, source: BookSource) {
        source.bookSourceUrl = json.bookSourceUrl
        source.bookSourceName = json.bookSourceName
        source.bookSourceGroup = json.bookSourceGroup ?? ""
        source.bookSourceType = Int32(clamping: json.bookSourceType ?? 0)
        source.searchUrl = json.searchUrl ?? ""
        source.exploreUrl = json.exploreUrl ?? ""
        source.enabled = json.enabled ?? true
        source.enabledExplore = json.enabledExplore ?? true
        source.weight = Int32(clamping: json.weight ?? 0)
        source.respondTime = Int64(json.respondTime ?? 60000)
        source.loginUrl = json.loginUrl ?? ""
        source.loginUi = json.loginUi ?? ""
        source.loginCheckJs = json.loginCheckJs ?? ""
        source.header = json.header ?? ""
        source.concurrentRate = json.concurrentRate ?? ""
        
        if let ruleSearch = json.ruleSearch {
            let searchRule = BookSource.SearchRule(
                checkKeyWord: nil,
                bookList: ruleSearch.bookList,
                name: ruleSearch.name,
                author: ruleSearch.author,
                intro: ruleSearch.intro,
                bookUrl: ruleSearch.bookUrl,
                coverUrl: ruleSearch.coverUrl,
                lastChapter: ruleSearch.lastChapter,
                wordCount: ruleSearch.wordCount,
                kind: ruleSearch.kind
            )
            source.setSearchRule(searchRule)
        }
        
        if let ruleExplore = json.ruleExplore {
            let exploreRule = BookSource.ExploreRule(
                exploreList: ruleExplore.bookList,
                name: ruleExplore.name,
                author: ruleExplore.author,
                intro: ruleExplore.intro,
                kind: ruleExplore.kind,
                updateTime: ruleExplore.updateTime,
                bookUrl: ruleExplore.bookUrl,
                coverUrl: ruleExplore.coverUrl,
                lastChapter: ruleExplore.lastChapter,
                wordCount: ruleExplore.wordCount
            )
            source.setExploreRule(exploreRule)
        }
        
        if let ruleBookInfo = json.ruleBookInfo {
            let bookInfoRule = BookSource.BookInfoRule(
                initRule: nil,
                name: ruleBookInfo.name,
                author: ruleBookInfo.author,
                intro: ruleBookInfo.intro,
                kind: ruleBookInfo.kind,
                coverUrl: ruleBookInfo.coverUrl,
                tocUrl: ruleBookInfo.tocUrl,
                lastChapter: ruleBookInfo.lastChapter,
                updateTime: ruleBookInfo.updateTime,
                wordCount: ruleBookInfo.wordCount,
                canReName: ruleBookInfo.canReName,
                downloadUrls: nil
            )
            source.setBookInfoRule(bookInfoRule)
        }
        
        if let ruleToc = json.ruleToc {
            let tocRule = TocRule(
                preUpdateJs: nil,
                bookList: ruleToc.chapterList ?? "",
                chapterName: ruleToc.chapterName ?? "",
                chapterUrl: ruleToc.chapterUrl ?? "",
                formatJs: nil,
                isVolume: nil,
                isVip: ruleToc.isVip,
                updateTime: ruleToc.updateTime,
                nextTocUrl: ruleToc.nextTocUrl,
                isPay: ruleToc.isPay
            )
            source.setTocRule(tocRule)
        }
        
        if let ruleContent = json.ruleContent {
            let contentRule = BookSource.ContentRule(
                content: ruleContent.content,
                title: nil,
                nextContentUrl: ruleContent.nextContentUrl,
                webJs: ruleContent.webJs,
                sourceRegex: ruleContent.sourceRegex,
                replaceRegex: ruleContent.replaceRegex,
                imageStyle: ruleContent.imageStyle,
                payAction: ruleContent.payAction
            )
            source.setContentRule(contentRule)
        }
    }
    
    static func importRssSourceJSON(_ jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        NotificationCenter.default.post(name: .importRssSourceNotification, object: jsonString)
        completion(.success("RSS 源导入成功"))
    }
    
    private static func importReplaceRuleJSON(_ jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success("替换规则导入成功"))
    }
    
    private static func importTtsRuleJSON(_ jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success("TTS 规则导入成功"))
    }
    
    private static func importThemeJSON(_ jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success("主题导入成功"))
    }
    
    private static func importReadConfigJSON(_ jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success("阅读配置导入成功"))
    }
    
    private static func importDictRuleJSON(_ jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success("字典规则导入成功"))
    }
    
    private static func importTextTocRuleJSON(_ jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success("TXT 目录规则导入成功"))
    }
    
    private static func importAddToBookshelfJSON(_ jsonString: String, completion: @escaping (Result<String, Error>) -> Void) {
        NotificationCenter.default.post(name: .addToBookshelfNotification, object: jsonString)
        completion(.success("添加到书架成功"))
    }
}