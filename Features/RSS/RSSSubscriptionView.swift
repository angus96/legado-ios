import SwiftUI
import CoreData

struct RSSSubscriptionView: View {
    @StateObject private var viewModel = RSSViewModel()
    @Environment(\.managedObjectContext) private var context
    
    @State private var sources: [RssSource] = []
    @State private var showingAddSource = false
    @State private var selectedSource: RssSource?
    @State private var loadError: Error?
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar
            refreshControls
            
            if let error = loadError {
                Text("加载失败: \(error.localizedDescription)")
                    .foregroundColor(.red)
                    .padding()
            } else if filteredSources.isEmpty {
                emptyView
            } else {
                sourceGrid
            }
        }
        .navigationTitle("RSS")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSource) { source in
            RSSArticlesView(source: source)
        }
        .sheet(isPresented: $showingAddSource) {
            AddRSSSourceView()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    Task { await viewModel.refreshAllNow() }
                } label: {
                    if viewModel.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(viewModel.isRefreshing)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddSource = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            viewModel.onAppear()
            loadSources()
        }
    }
    
    private func loadSources() {
        let request = NSFetchRequest<RssSource>(entityName: "RssSource")
        request.sortDescriptors = [NSSortDescriptor(key: "customOrder", ascending: true)]
        
        do {
            sources = try context.fetch(request)
            loadError = nil
        } catch {
            loadError = error
            print("RSS sources fetch error: \(error)")
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("搜索订阅源", text: $viewModel.searchText)
                .textFieldStyle(.plain)
            
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var refreshControls: some View {
        VStack(spacing: 8) {
            Toggle(
                "自动刷新",
                isOn: Binding(
                    get: { viewModel.autoRefreshEnabled },
                    set: { viewModel.setAutoRefreshEnabled($0) }
                )
            )

            if viewModel.autoRefreshEnabled {
                HStack {
                    Text("刷新间隔")
                    Spacer()
                    Picker(
                        "刷新间隔",
                        selection: Binding(
                            get: { viewModel.refreshInterval },
                            set: { viewModel.setRefreshInterval($0) }
                        )
                    ) {
                        ForEach(viewModel.refreshIntervalOptions) { option in
                            Text(option.title).tag(option.seconds)
                        }
                    }
                    .labelsHidden()
                }

                Text("后台刷新为 iOS 最佳努力调度，可能延迟执行")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = viewModel.lastRefreshMessage, !message.isEmpty {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("暂无订阅源")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("点击右上角 + 添加订阅源")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var sourceGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(filteredSources, id: \.objectID) { source in
                    RSSSourceItem(source: source, statusText: viewModel.statusText(for: source)) {
                        selectedSource = source
                    }
                    .contextMenu {
                        Button("立即刷新") {
                            Task { await viewModel.refresh(source: source) }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private var filteredSources: [RssSource] {
        if viewModel.searchText.isEmpty {
            return Array(sources)
        }
        return sources.filter {
            $0.sourceName.localizedCaseInsensitiveContains(viewModel.searchText) ||
            $0.sourceUrl.localizedCaseInsensitiveContains(viewModel.searchText)
        }
    }
}

struct RSSSourceItem: View {
    let source: RssSource
    let statusText: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 16) {
                AsyncImage(url: source.sourceIcon.flatMap { URL(string: $0) }) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        ZStack {
                            Color(.systemGray5)
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Text(source.sourceName)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(16)
        }
        .buttonStyle(.plain)
    }
}

struct RSSArticlesView: View {
    let source: RssSource
    @Environment(\.dismiss) private var dismiss
    @State private var selectedArticleLink: String?
    @State private var selectedArticleTitle: String?
    @State private var selectedArticleOrigin: String?
    @State private var selectedArticleAuthor: String?
    @State private var articles: [RSSArticle] = []
    @State private var isLoading = true
    @State private var articleStyle: Int = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("加载中...")
                } else if articles.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "newspaper")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无文章")
                            .foregroundColor(.secondary)
                    }
                } else {
                    articlesContent
                }
            }
            .navigationTitle(source.sourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("列表视图") { articleStyle = 0 }
                        Button("网格2列") { articleStyle = 2 }
                        Button("瀑布流") { articleStyle = 3 }
                        Button("网格3列") { articleStyle = 4 }
                    } label: {
                        Image(systemName: styleIcon)
                    }
                }
            }
            .task { await loadArticles() }
            .navigationDestination(isPresented: Binding(
                get: { selectedArticleLink != nil },
                set: { if !$0 { selectedArticleLink = nil; selectedArticleTitle = nil; selectedArticleAuthor = nil } }
            )) {
                if let link = selectedArticleLink {
                    RssReadView(
                        articleLink: link,
                        articleTitle: selectedArticleTitle ?? "",
                        articleOrigin: selectedArticleAuthor ?? ""
                    )
                }
            }
        }
    }
    
    private var styleIcon: String {
        switch articleStyle {
        case 2: return "square.grid.2x2"
        case 3: return "rectangle.grid.2x2"
        case 4: return "square.grid.3x3"
        default: return "list.bullet"
        }
    }
    
    private var articlesContent: some View {
        Group {
            switch articleStyle {
            case 2:
                gridArticlesView(columns: 2, padding: 8)
            case 3:
                staggeredGridView
            case 4:
                gridArticlesView(columns: 3, padding: 4)
            default:
                listArticlesView
            }
        }
    }
    
    private var listArticlesView: some View {
        List(articles) { article in
            articleLink(article)
        }
        .listStyle(.plain)
    }
    
    private func gridArticlesView(columns: Int, padding: CGFloat) -> some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: padding), count: columns), spacing: padding) {
                ForEach(articles) { article in
                    articleLink(article)
                        .padding(padding)
                }
            }
            .padding(.horizontal, padding)
        }
    }
    
    private var staggeredGridView: some View {
        let isLandscape = horizontalSizeClass == .regular
        let columns = isLandscape ? 3 : 2
        
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columns), spacing: 30) {
                ForEach(articles) { article in
                    articleLink(article)
                        .padding(20)
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private func articleLink(_ article: RSSArticle) -> some View {
        Button {
            selectedArticleLink = article.link
            selectedArticleTitle = article.title
            selectedArticleAuthor = article.author
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.headline)
                    .lineLimit(2)
                
                if let desc = article.description, !desc.isEmpty {
                    Text(desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                if let date = article.pubDate {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func loadArticles() async {
        let url = source.sourceUrl
        
        do {
            let items: [RSSArticle]
            if RuleBasedRSSParser.shouldUseRuleParsing(source: source) {
                let (_, parsedItems) = try await RSSParser.fetchAndParse(url: url, source: source)
                items = parsedItems
            } else {
                let (_, parsedItems) = try await RSSParser.fetchAndParse(url: url)
                items = parsedItems
            }
            articles = items
        } catch {
            print("RSS load error: \(error)")
        }
        
        isLoading = false
    }
}

struct AddRSSSourceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var name = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("订阅地址") {
                    TextField("RSS/Atom 链接", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                Section("名称（可选）") {
                    TextField("自定义名称", text: $name)
                }
            }
            .navigationTitle("添加订阅")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { addSource() }
                        .disabled(url.isEmpty)
                }
            }
        }
    }
    
    private func addSource() {
        let context = CoreDataStack.shared.viewContext
        let source = RssSource.create(in: context)
        source.sourceUrl = url
        source.sourceName = name.isEmpty ? url : name
        try? context.save()
        dismiss()
    }
}

struct RSSArticle: Identifiable {
    let id = UUID()
    let title: String
    let link: String
    let description: String?
    let pubDate: Date?
    let author: String?
}

class RSSParser {
    static func parse(xmlData: Data, sourceUrl _: String) -> [RSSArticle] {
        let parser = XMLFeedParser(data: xmlData)
        parser.parse()
        return parser.articles
    }
    
    static func fetchAndParse(url: String) async throws -> (String, [RSSArticle]) {
        try await fetchAndParse(url: url, source: nil)
    }

    static func fetchAndParse(url: String, source: RssSource?) async throws -> (String, [RSSArticle]) {
        let source = try source.map { try RssSourceSnapshot.capture($0) }
        guard let feedUrl = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: feedUrl)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        if let source, RuleBasedRSSParser.shouldUseRuleParsing(source: source) {
            let parser = RuleBasedRSSParser()
            let articles = try parser.parse(data: data, source: source, sourceUrl: url)
            let title = source.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (title.isEmpty ? "未知订阅" : title, articles)
        }

        let parser = XMLFeedParser(data: data)
        parser.parse()
        
        return (parser.feedTitle ?? "未知订阅", parser.articles)
    }
}

private class XMLFeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    var feedTitle: String?
    var articles: [RSSArticle] = []
    
    private var currentText = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentAuthor = ""
    private var isInItem = false
    private var isInAuthor = false
    
    init(data: Data) {
        self.data = data
    }
    
    func parse() {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = elementName.lowercased()
        currentText = ""

        if name == "item" || name == "entry" {
            isInItem = true
            resetCurrentArticle()
            return
        }

        if isInItem && name == "author" {
            isInAuthor = true
            return
        }

        if isInItem && name == "link", let href = attributeDict["href"], !href.isEmpty {
            currentLink = href
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
            case "title":
                if currentTitle.isEmpty { currentTitle = text }
            case "link", "id":
                if currentLink.isEmpty { currentLink = text }
            case "description", "summary", "content", "content:encoded":
                if currentDescription.isEmpty {
                    currentDescription = text
                } else if !text.isEmpty {
                    currentDescription += "\n" + text
                }
            case "pubdate", "published", "updated", "dc:date":
                if currentPubDate.isEmpty { currentPubDate = text }
            case "author":
                if currentAuthor.isEmpty { currentAuthor = text }
                isInAuthor = false
            case "name":
                if isInAuthor && currentAuthor.isEmpty {
                    currentAuthor = text
                }
            case "item", "entry":
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

    private func appendCurrentArticle() {
        let trimmedTitle = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = currentAuthor.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty || !trimmedLink.isEmpty || !trimmedDescription.isEmpty else {
            return
        }

        let article = RSSArticle(
            title: trimmedTitle.isEmpty ? "无标题" : trimmedTitle,
            link: trimmedLink,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            pubDate: parseDate(currentPubDate),
            author: trimmedAuthor.isEmpty ? nil : trimmedAuthor
        )
        articles.append(article)
    }

    private func resetCurrentArticle() {
        currentText = ""
        currentTitle = ""
        currentLink = ""
        currentDescription = ""
        currentPubDate = ""
        currentAuthor = ""
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

#Preview {
    NavigationStack {
        RSSSubscriptionView()
    }
}
