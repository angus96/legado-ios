import SwiftUI
import CoreData

struct SourceHealthReport {
    enum Outcome: Equatable { case otherBooksWork, sourceIssue, inconclusive }
    struct Sample: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let succeeded: Bool
        let uncertain: Bool
    }
    let outcome: Outcome
    let summary: String
    let samples: [Sample]
}

enum SourceHealthChecker {
    typealias Search = (BookSourceSnapshot, String) async throws -> [SearchBookResult]
    typealias Probe = (BookSourceSnapshot, SearchBookResult) async throws -> Int

    static func check(
        source: BookSourceSnapshot, bookName: String, failingBookURL: String,
        search: @escaping Search = { try await WebBook.searchBook(source: $0, key: $1, timeout: 12) },
        probe: @escaping Probe = { source, result in
            var book = BookRequestSnapshot(origin: source.bookSourceUrl, bookUrl: result.bookUrl, tocUrl: "",
                                           name: result.name, author: result.author)
            if source.getBookInfoRule() != nil { book = try await WebBook.getBookInfo(source: source, book: book) }
            return try await WebBook.getChapterList(source: source, book: book).count
        }
    ) async throws -> SourceHealthReport {
        guard !(source.searchUrl?.isEmpty ?? true), source.getSearchRule() != nil, source.getTocRule() != nil else {
            return SourceHealthReport(outcome: .sourceIssue, summary: "书源缺少搜索地址、搜索规则或目录规则，无法完成搜书和加载目录。", samples: [])
        }
        var candidates: [SearchBookResult] = []
        var samples: [SourceHealthReport.Sample] = []
        var seen = Set<String>()
        for keyword in [bookName, "我的"].filter({ !$0.isEmpty }) {
            try Task.checkCancellation()
            do {
                let found = try await ConcurrentSourceSearch.withTimeout(seconds: 12) {
                    try await search(source, keyword)
                }
                candidates.append(contentsOf: found.filter {
                    !$0.bookUrl.isEmpty && !$0.name.isEmpty && $0.bookUrl != failingBookURL && $0.name != bookName &&
                    seen.insert($0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "|" +
                                $0.author.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted
                })
                if candidates.count >= 3 { break }
            } catch is CancellationError { throw CancellationError() }
            catch {
                samples.append(.init(title: "搜索“\(keyword)”", detail: NetworkError.message(for: error), succeeded: false, uncertain: true))
            }
        }
        for candidate in candidates.prefix(3) {
            try Task.checkCancellation()
            do {
                let count = try await ConcurrentSourceSearch.withTimeout(seconds: 15) {
                    try await probe(source, candidate)
                }
                samples.append(.init(title: candidate.name, detail: count > 0 ? "目录正常，共 \(count) 章" : "目录为空",
                                     succeeded: count > 0, uncertain: false))
                if count > 0 {
                    return SourceHealthReport(outcome: .otherBooksWork,
                                              summary: "其他书的目录可以加载，不能认定整个书源失效。当前这本书可以重试或换源。", samples: samples)
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                let detail = NetworkError.message(for: error)
                let uncertain = (error as NSError).domain == NSURLErrorDomain ||
                    detail.contains("401") || detail.contains("403") || detail.contains("验证") || detail.contains("登录")
                samples.append(.init(title: candidate.name, detail: detail, succeeded: false, uncertain: uncertain))
            }
        }
        let failedBooks = samples.filter { !$0.uncertain && !$0.succeeded }.count
        if failedBooks >= 2 {
            return SourceHealthReport(outcome: .sourceIssue,
                                      summary: "抽查的 \(failedBooks) 本其他书都无法加载目录，书源规则可能已失效。可以先停用，或确认后删除。", samples: samples)
        }
        return SourceHealthReport(outcome: .inconclusive,
                                  summary: "暂时无法判断整个书源是否失效。没有足够的其他书可检查，或请求遇到网络、登录、验证问题，请稍后重试。", samples: samples)
    }
}

struct SourceDiagnosticView: View {
    let source: BookSource
    let bookName: String
    let failingBookURL: String
    private let sourceID: UUID
    private let sourceName: String
    @Environment(\.dismiss) private var dismiss
    @State private var report: SourceHealthReport?
    @State private var isChecking = false
    @State private var checkTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var confirmingDeletion = false

    init(source: BookSource, bookName: String, failingBookURL: String) {
        self.source = source
        self.bookName = bookName
        self.failingBookURL = failingBookURL
        sourceID = source.sourceId
        sourceName = source.bookSourceName
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(sourceName)
                    Text("检查该书源能否搜索，并抽查最多 3 本其他书的详情和目录。只校验，不修改书架、章节或阅读进度。")
                        .font(.footnote).foregroundColor(.secondary)
                    if isChecking {
                        HStack { ProgressView(); Text("正在校验书源…") }
                        Button("停止校验") { stop() }
                    } else {
                        Button(report == nil ? "开始校验" : "重新校验") { check() }
                            .accessibilityIdentifier("sourceCheck.start")
                    }
                }
                if let report {
                    Section("校验结果") {
                        Text(report.summary).accessibilityIdentifier("sourceCheck.summary")
                        ForEach(report.samples) { sample in
                            VStack(alignment: .leading, spacing: 6) {
                                Label(sample.title, systemImage: sample.succeeded ? "checkmark.circle" : "exclamationmark.circle")
                                Text(sample.detail).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    if report.outcome == .sourceIssue && !isChecking {
                        Section {
                            Button("停用这个书源") { cleanUp(delete: false) }
                            Button("删除这个书源", role: .destructive) { confirmingDeletion = true }
                            Text("停用或删除书源会保留书架、本地文件、已缓存章节和阅读进度。删除后需要重新导入书源才能恢复。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("校验书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("关闭") { stop(); dismiss() } } }
            .confirmationDialog("确认删除这个书源？", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("删除书源，保留书架和阅读数据", role: .destructive) { cleanUp(delete: true) }
            }
            .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("确定") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .task { check() }
        .onDisappear { stop() }
    }

    private func check() {
        guard !isChecking else { return }
        isChecking = true
        report = nil
        checkTask = Task {
            defer { if !Task.isCancelled { isChecking = false; checkTask = nil } }
            do {
                let definition = try BookSourceSnapshot.capture(source)
                let result = try await SourceHealthChecker.check(source: definition, bookName: bookName, failingBookURL: failingBookURL)
                guard !Task.isCancelled else { return }
                report = result
            } catch is CancellationError { return }
            catch { if !Task.isCancelled { errorMessage = NetworkError.message(for: error) } }
        }
    }

    private func stop() {
        checkTask?.cancel()
        checkTask = nil
        isChecking = false
    }

    private func cleanUp(delete: Bool) {
        let context = CoreDataStack.shared.newBackgroundContext()
        let sourceID = sourceID
        Task {
            do {
                try await context.perform {
                    let request = BookSource.fetchRequest()
                    request.fetchLimit = 1
                    request.predicate = NSPredicate(format: "sourceId == %@", sourceID as CVarArg)
                    if let saved = try context.fetch(request).first {
                        if delete { context.delete(saved) } else { saved.enabled = false }
                        try context.save()
                    }
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
