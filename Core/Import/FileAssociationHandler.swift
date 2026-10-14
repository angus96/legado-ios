import SwiftUI
import UniformTypeIdentifiers

struct FileAssociationHandler: View {
    let url: URL
    var automaticallyImportText = false
    var onImported: () -> Void = {}
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isImporting = false
    @State private var didAttemptAutomaticImport = false
    @State private var importResult: String?
    @State private var importSucceeded = false
    @State private var importedBookID: UUID?
    @State private var bookName = ""
    @State private var chapterCount = 0
    @State private var canContinueReading = false
    @State private var showingReader = false

    private var isBook: Bool { ["txt", "epub"].contains(url.pathExtension.lowercased()) }
    private var isSupported: Bool { isBook || url.pathExtension.lowercased() == "json" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: importSucceeded ? "checkmark.circle.fill" : "doc.text")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(importSucceeded ? Color.green : Color.accentColor)
                        .padding(.top, 24)
                    VStack(spacing: 10) {
                        Text(importSucceeded && isBook ? bookName : url.deletingPathExtension().lastPathComponent)
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(url.lastPathComponent).font(.footnote).foregroundStyle(.secondary)
                        if isImporting {
                            ProgressView("正在保存到书架")
                        } else if let result = importResult {
                            Text(result)
                                .foregroundStyle(importSucceeded ? Color.secondary : Color.red)
                                .multilineTextAlignment(.center)
                                .accessibilityIdentifier("fileImport.status")
                        }
                    }
                    if let bookID = importedBookID {
                        VStack(spacing: 12) {
                            Text("共 \(chapterCount) 章 · 可离线阅读").font(.subheadline).foregroundStyle(.secondary)
                            Button { showingReader = true } label: {
                                Label(canContinueReading ? "继续阅读" : "开始阅读", systemImage: "book")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("fileImport.read")
                            Text("正文已保存在本机，原文件移除后仍可阅读。")
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .navigationDestination(isPresented: $showingReader) { ReaderView(bookId: bookID) }
                    } else if !importSucceeded {
                        Button(importResult == nil ? (isBook ? "加入书架" : "导入书源") : "重试导入") {
                            Task { await importFile() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isImporting || !isSupported)
                        .accessibilityIdentifier("fileImport.retry")
                    }
                    if importSucceeded {
                        Button("返回书架", action: close)
                            .accessibilityIdentifier("fileImport.bookshelf")
                    }
                }
                .frame(maxWidth: 540)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isBook ? "导入书籍" : "导入文件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭", action: close).disabled(isImporting)
                        .accessibilityIdentifier("fileImport.close")
                }
            }
            .task {
                guard automaticallyImportText, url.pathExtension.lowercased() == "txt", !didAttemptAutomaticImport else { return }
                didAttemptAutomaticImport = true
                await importFile()
            }
        }
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    @MainActor
    private func importFile() async {
        guard !isImporting, !importSucceeded else { return }
        isImporting = true
        importResult = nil
        defer { isImporting = false }
        do {
            if isBook {
                let book = try await LocalBookViewModel().importBook(url: url)
                bookName = book.name
                chapterCount = Int(book.totalChapterNum)
                canContinueReading = book.durChapterIndex > 0 || book.durChapterPos > 0
                importedBookID = book.bookId
                importResult = "已加入书架"
            } else if url.pathExtension.lowercased() == "json" {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let text = try String(contentsOf: url, encoding: .utf8)
                importResult = try await withCheckedThrowingContinuation { continuation in
                    URLSchemeHandler.importBookSourceJSON(text) { continuation.resume(with: $0) }
                }
            } else {
                throw LocalBookError.unsupportedFormat
            }
            importSucceeded = true
            onImported()
        } catch {
            importResult = "导入失败：\(error.localizedDescription)"
        }
    }
}
