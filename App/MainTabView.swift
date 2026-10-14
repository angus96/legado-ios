//
//  MainTabView.swift
//  Legado-iOS
//
//  主 Tab 视图（完善版）
//

import SwiftUI
import UniformTypeIdentifiers

struct MainTabView: View {
    var initialTab: Int? = nil
    @State private var selectedTab = 0
    @AppStorage("app.defaultHomePage") private var defaultHomePage = 0
    @AppStorage("app.showDiscoveryPage") private var showDiscoveryPage = true
    @AppStorage("app.showRssPage") private var showRssPage = true
    @AppStorage("app_theme") private var selectedTheme = "system"

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { BookshelfView() }
                .tabItem {
                    Label("书架", systemImage: "books.vertical.fill")
                }
                .tag(0)

            if showDiscoveryPage {
                NavigationStack { DiscoveryView() }
                    .tabItem {
                        Label("发现", systemImage: "safari.fill")
                    }
                    .tag(1)
            }

            if showRssPage {
                NavigationStack { RSSSubscriptionView() }
                    .tabItem {
                        Label("订阅", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .tag(2)
            }

            NavigationStack { MyView() }
                .tabItem {
                    Label("我的", systemImage: "person.fill")
                }
                .tag(3)
        }
        .accentColor(.blue)
        .preferredColorScheme(
            selectedTheme == "dark" ? .dark :
            selectedTheme == "light" ? .light : nil
        )
        .onAppear {
            selectedTab = availableTab(initialTab ?? defaultHomePage)
        }
        .onChange(of: showDiscoveryPage) { _ in selectedTab = availableTab(selectedTab) }
        .onChange(of: showRssPage) { _ in selectedTab = availableTab(selectedTab) }
        .onReceive(NotificationCenter.default.publisher(for: .localBookImported)) { _ in selectedTab = 0 }
    }

    private func availableTab(_ tab: Int) -> Int {
        if tab == 1 && !showDiscoveryPage || tab == 2 && !showRssPage { return 0 }
        return (0...3).contains(tab) ? tab : 0
    }
}

// MARK: - 关于视图（占位，实际实现见 Features/Config/AboutView.swift）
// AboutView 定义在 Features/Config/AboutView.swift 中

// MARK: - 辅助视图
struct AboutFeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.blue)
            
            Text(text)
                .font(.body)
        }
    }
}

struct AboutSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            content
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - 主题设置视图
struct AppThemeSettingsView: View {
    @AppStorage("app_theme") private var selectedTheme = "system"
    
    var body: some View {
        List {
            Section("外观模式") {
                ForEach([
                    ("system", "跟随系统", "iphone"),
                    ("light", "浅色模式", "sun.max"),
                    ("dark", "深色模式", "moon")
                ], id: \.0) { (value, label, icon) in
                    Button(action: { selectedTheme = value }) {
                        HStack {
                            Image(systemName: icon)
                                .frame(width: 24)
                                .foregroundColor(.blue)
                            Text(label)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedTheme == value {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            
            Section("阅读背景") {
                ForEach([
                    ("白色", Color.white),
                    ("米黄", Color(red: 0.98, green: 0.95, blue: 0.88)),
                    ("浅绿", Color(red: 0.8, green: 0.93, blue: 0.8)),
                    ("深灰", Color(white: 0.2))
                ], id: \.0) { (name, color) in
                    HStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color)
                            .frame(width: 40, height: 30)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        Text(name)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("主题")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 缓存清理视图
struct CacheCleanView: View {
    @State private var imageCacheSize: String = "计算中..."
    @State private var chapterCacheSize: String = "计算中..."
    @State private var logSize: String = "计算中..."
    @State private var isClearing = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        List {
            Section("缓存占用") {
                HStack {
                    Label("日志文件", systemImage: "doc.text")
                    Spacer()
                    Text(logSize)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Label("图片缓存", systemImage: "photo")
                    Spacer()
                    Text(imageCacheSize)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Label("章节缓存", systemImage: "doc.text")
                    Spacer()
                    Text(chapterCacheSize)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button(action: { clearLog() }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("清理日志")
                    }
                }
                
                Button(action: { clearImageCache() }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("清理图片缓存")
                    }
                }
                
                Button(action: { clearChapterCache() }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("清理章节缓存")
                    }
                }
                
                Button(role: .destructive, action: clearAll) {
                    HStack {
                        Image(systemName: "trash")
                        Text("清理全部缓存")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("清理缓存")
        .navigationBarTitleDisplayMode(.inline)
        .task { calculateCacheSize() }
        .alert("提示", isPresented: $showingAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private func calculateCacheSize() {
        imageCacheSize = folderSize(imageCacheDir())
        chapterCacheSize = folderSize(chapterCacheDir())
        logSize = fileSize(logFile())
    }

    private func logFile() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("debug.log")
    }

    private func imageCacheDir() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("images", isDirectory: true)
    }

    private func chapterCacheDir() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("chapters", isDirectory: true)
    }
    
    private func fileSize(_ url: URL?) -> String {
        guard let url = url else { return "0 B" }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    private func folderSize(_ url: URL?) -> String {
        guard let url = url else { return "0 B" }
        let fm = FileManager.default
        var total: Int64 = 0
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else {
            return "0 B"
        }

        for case let itemURL as URL in enumerator {
            guard let values = try? itemURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
            guard values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    
    private func clearLog(showMessage: Bool = true) {
        if let url = logFile() {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        calculateCacheSize()
        if showMessage {
            alertMessage = "日志已清理"
            showingAlert = true
        }
    }
    
    private func clearImageCache(showMessage: Bool = true) {
        let dir = imageCacheDir()
        clearDir(dir)
        ImageCacheManager.shared.clearCache()
        calculateCacheSize()

        if showMessage {
            alertMessage = "图片缓存已清理"
            showingAlert = true
        }
    }
    
    private func clearChapterCache(showMessage: Bool = true) {
        let dir = chapterCacheDir()
        clearDir(dir)
        calculateCacheSize()

        if showMessage {
            alertMessage = "章节缓存已清理"
            showingAlert = true
        }
    }
    
    private func clearAll() {
        isClearing = true
        defer { isClearing = false }

        clearLog(showMessage: false)
        clearImageCache(showMessage: false)
        clearChapterCache(showMessage: false)
        alertMessage = "全部缓存已清理"
        showingAlert = true
    }
    
    private func clearDir(_ url: URL?) {
        guard let url = url else { return }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

struct DataMigrationView: View {
    @StateObject private var manager = DataMigrationManager()
    @State private var selectedType: MigrationType = .legadoAndroid
    @State private var showingImporter = false

    @State private var includeBooks = true
    @State private var includeSources = true
    @State private var includeBookmarks = true
    @State private var includeRules = true
    @State private var showingExporter = false
    @State private var exportDocument = JSONDataDocument()

    var body: some View {
        List {
            Section("导入") {
                Picker("类型", selection: $selectedType) {
                    ForEach(MigrationType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                Button("选择文件导入") {
                    showingImporter = true
                }
                .disabled(manager.isMigrating)

                if manager.isMigrating {
                    ProgressView(value: manager.migrationProgress)
                }
            }

            Section("导出") {
                Toggle("包含书籍", isOn: $includeBooks)
                Toggle("包含书源", isOn: $includeSources)
                Toggle("包含书签", isOn: $includeBookmarks)
                Toggle("包含替换规则", isOn: $includeRules)

                Button("导出备份") {
                    exportBackup()
                }
            }

            if let result = manager.migrationResult {
                Section("结果") {
                    Text(result.summary)

                    if !result.errors.isEmpty {
                        Text("错误：")
                            .font(.headline)
                        ForEach(result.errors, id: \.self) { err in
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle("数据迁移")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.json, .zip, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { @MainActor in
                    let granted = url.startAccessingSecurityScopedResource()
                    defer {
                        if granted {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    _ = await manager.migrateFromFile(url, type: selectedType)
                }
            case .failure:
                break
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "legado-ios-backup"
        ) { _ in }
    }

    private func exportBackup() {
        guard let data = manager.exportData(
            includeBooks: includeBooks,
            includeSources: includeSources,
            includeBookmarks: includeBookmarks,
            includeRules: includeRules
        ) else {
            return
        }

        exportDocument = JSONDataDocument(data: data)
        showingExporter = true
    }
}

struct JSONDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SourceSubscriptionView: View {
    @StateObject private var manager = SourceSubscriptionManager()
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var newUrl = ""

    var body: some View {
        List {
            Section {
                if manager.subscriptions.isEmpty {
                    Text("暂无订阅")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(manager.subscriptions) { sub in
                        subscriptionRow(sub)
                    }
                    .onDelete { indexSet in
                        if let index = indexSet.first {
                            manager.removeSubscription(at: index)
                        }
                    }
                }
            } header: {
                Text("订阅列表")
            }

            Section("操作") {
                Button("更新所有订阅") {
                    Task { @MainActor in
                        await manager.updateAllSubscriptions()
                    }
                }

                if manager.isUpdating {
                    ProgressView(value: manager.updateProgress)
                }

                if let err = manager.lastUpdateError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("书源订阅")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("添加订阅", isPresented: $showingAdd) {
            TextField("名称", text: $newName)
            TextField("订阅 URL", text: $newUrl)
                .textInputAutocapitalization(.never)
            Button("取消", role: .cancel) {
                newName = ""
                newUrl = ""
            }
            Button("添加") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                let url = newUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, !url.isEmpty {
                    manager.addSubscription(name: name, url: url)
                }
                newName = ""
                newUrl = ""
            }
        }
    }

    @ViewBuilder
    private func subscriptionRow(_ sub: SourceSubscription) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(sub.name)
                    .font(.headline)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { sub.enabled },
                    set: { newValue in
                        var updated = sub
                        updated.enabled = newValue
                        manager.updateSubscription(updated)
                    }
                ))
                .labelsHidden()
            }

            Text(sub.url)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 8) {
                Toggle("自动更新", isOn: Binding(
                    get: { sub.autoUpdate },
                    set: { newValue in
                        var updated = sub
                        updated.autoUpdate = newValue
                        manager.updateSubscription(updated)
                    }
                ))
                .font(.caption)

                Spacer()

                if let last = sub.lastUpdateTime {
                    Text("上次：\(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("从未更新")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button("立即更新") {
                    Task { @MainActor in
                        try? await manager.updateSubscription(id: sub.id)
                    }
                }
                .font(.caption)

                Spacer()

                Menu {
                    ForEach([3600.0, 21600.0, 43200.0, 86400.0, 172800.0], id: \.self) { seconds in
                        Button("每 \(Int(seconds / 3600)) 小时") {
                            var updated = sub
                            updated.updateInterval = seconds
                            manager.updateSubscription(updated)
                        }
                    }
                } label: {
                    Text("间隔：\(Int(sub.updateInterval / 3600))h")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DebugLogView: View {
    @State private var logLines: [String] = []
    @State private var showShareSheet = false
    
    private let maxLines = 500
    
    var body: some View {
        VStack {
            if logLines.isEmpty {
                Text("暂无日志")
                    .foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logLines.indices, id: \.self) { index in
                            Text(logLines[index])
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("调试日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { showShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Button("清空") {
                        try? "".write(toFile: DebugLogger.shared.logFilePath, atomically: true, encoding: .utf8)
                        logLines = []
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [URL(fileURLWithPath: DebugLogger.shared.logFilePath)])
        }
        .onAppear {
            loadLog()
        }
    }
    
    private func loadLog() {
        guard let content = try? String(contentsOfFile: DebugLogger.shared.logFilePath, encoding: .utf8) else {
            logLines = []
            return
        }
        let allLines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let startIndex = max(0, allLines.count - maxLines)
        logLines = Array(allLines[startIndex...])
    }
}

#Preview {
    MainTabView()
}
