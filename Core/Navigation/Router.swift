//
//  Router.swift
//  Legado-iOS
//
//  路由系统 - 页面导航管理
//

import SwiftUI

/// 路由目标
enum Route: Hashable {
    // 书架
    case bookshelf
    case bookDetail(bookUrl: String)
    case bookEdit(bookUrl: String)
    
    // 阅读
    case reader(bookUrl: String)
    case readerWithChapter(bookUrl: String, chapterIndex: Int)
    
    // 搜索
    case search
    case searchWithKeyword(keyword: String)
    
    // 发现
    case discovery
    case discoveryWithSource(sourceUrl: String)
    
    // 书源
    case sourceManage
    case sourceEdit(sourceUrl: String?)
    case sourceDebug(sourceUrl: String)
    
    // RSS
    case rssList
    case rssFeed(sourceUrl: String)
    case rssFavorites
    
    // 配置
    case settings
    case replaceRules
    case txtTocRules
    case dictRules
    case httpTTS
    case backup
    
    // 其他
    case webView(url: String)
    case qrScanner
    case statistics
    
    // MARK: - Hashable
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .bookshelf:
            hasher.combine("bookshelf")
        case .bookDetail(let bookUrl):
            hasher.combine("bookDetail")
            hasher.combine(bookUrl)
        case .bookEdit(let bookUrl):
            hasher.combine("bookEdit")
            hasher.combine(bookUrl)
        case .reader(let bookUrl):
            hasher.combine("reader")
            hasher.combine(bookUrl)
        case .readerWithChapter(let bookUrl, let chapterIndex):
            hasher.combine("readerWithChapter")
            hasher.combine(bookUrl)
            hasher.combine(chapterIndex)
        case .search:
            hasher.combine("search")
        case .searchWithKeyword(let keyword):
            hasher.combine("searchWithKeyword")
            hasher.combine(keyword)
        case .discovery:
            hasher.combine("discovery")
        case .discoveryWithSource(let sourceUrl):
            hasher.combine("discoveryWithSource")
            hasher.combine(sourceUrl)
        case .sourceManage:
            hasher.combine("sourceManage")
        case .sourceEdit(let sourceUrl):
            hasher.combine("sourceEdit")
            hasher.combine(sourceUrl)
        case .sourceDebug(let sourceUrl):
            hasher.combine("sourceDebug")
            hasher.combine(sourceUrl)
        case .rssList:
            hasher.combine("rssList")
        case .rssFeed(let sourceUrl):
            hasher.combine("rssFeed")
            hasher.combine(sourceUrl)
        case .rssFavorites:
            hasher.combine("rssFavorites")
        case .settings:
            hasher.combine("settings")
        case .replaceRules:
            hasher.combine("replaceRules")
        case .txtTocRules:
            hasher.combine("txtTocRules")
        case .dictRules:
            hasher.combine("dictRules")
        case .httpTTS:
            hasher.combine("httpTTS")
        case .backup:
            hasher.combine("backup")
        case .webView(let url):
            hasher.combine("webView")
            hasher.combine(url)
        case .qrScanner:
            hasher.combine("qrScanner")
        case .statistics:
            hasher.combine("statistics")
        }
    }
    
    static func == (lhs: Route, rhs: Route) -> Bool {
        switch (lhs, rhs) {
        case (.bookshelf, .bookshelf): return true
        case (.bookDetail(let l), .bookDetail(let r)): return l == r
        case (.bookEdit(let l), .bookEdit(let r)): return l == r
        case (.reader(let l), .reader(let r)): return l == r
        case (.readerWithChapter(let lb, let li), .readerWithChapter(let rb, let ri)): return lb == rb && li == ri
        case (.search, .search): return true
        case (.searchWithKeyword(let l), .searchWithKeyword(let r)): return l == r
        case (.discovery, .discovery): return true
        case (.discoveryWithSource(let l), .discoveryWithSource(let r)): return l == r
        case (.sourceManage, .sourceManage): return true
        case (.sourceEdit(let l), .sourceEdit(let r)): return l == r
        case (.sourceDebug(let l), .sourceDebug(let r)): return l == r
        case (.rssList, .rssList): return true
        case (.rssFeed(let l), .rssFeed(let r)): return l == r
        case (.rssFavorites, .rssFavorites): return true
        case (.settings, .settings): return true
        case (.replaceRules, .replaceRules): return true
        case (.txtTocRules, .txtTocRules): return true
        case (.dictRules, .dictRules): return true
        case (.httpTTS, .httpTTS): return true
        case (.backup, .backup): return true
        case (.webView(let l), .webView(let r)): return l == r
        case (.qrScanner, .qrScanner): return true
        case (.statistics, .statistics): return true
        default: return false
        }
    }
}

/// 路由管理器
@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    
    @Published var path = NavigationPath()
    @Published var presentedSheet: Route?
    @Published var presentedFullScreen: Route?
    
    private init() {}
    
    // MARK: - 导航方法
    
    func push(_ route: Route) {
        path.append(route)
    }
    
    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }
    
    func popToRoot() {
        path = NavigationPath()
    }
    
    func pop(to count: Int) {
        let currentCount = path.count
        if count < currentCount {
            path.removeLast(currentCount - count)
        }
    }
    
    func present(_ route: Route) {
        presentedSheet = route
    }
    
    func presentFullScreen(_ route: Route) {
        presentedFullScreen = route
    }
    
    func dismiss() {
        presentedSheet = nil
        presentedFullScreen = nil
    }
    
    // MARK: - 快捷方法
    
    func openBook(bookUrl: String) {
        push(.bookDetail(bookUrl: bookUrl))
    }
    
    func openReader(bookUrl: String, chapterIndex: Int? = nil) {
        if let chapterIndex = chapterIndex {
            push(.readerWithChapter(bookUrl: bookUrl, chapterIndex: chapterIndex))
        } else {
            push(.reader(bookUrl: bookUrl))
        }
    }
    
    func openSource(sourceUrl: String? = nil) {
        push(.sourceEdit(sourceUrl: sourceUrl))
    }
    
    func debugSource(sourceUrl: String) {
        present(.sourceDebug(sourceUrl: sourceUrl))
    }
    
    func openWebView(url: String) {
        present(.webView(url: url))
    }
}

// MARK: - View Extension

extension View {
    @MainActor
    func withRouter() -> some View {
        self.environmentObject(Router.shared)
    }
}
